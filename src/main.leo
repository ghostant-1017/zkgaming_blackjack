// The 'zkgaming_blackjack' program.
import random.leo;
import start_request.leo;
import hit_request.leo;
import stand_request.leo;


program zkgaming_blackjack.aleo {
    record game_state {
        owner: address,
        gates: u64,

        // `cards` is caculated from `nonce`, fisher_yates_shuffle(nonce) -> cards
        // For simplicity,`fisher_yates_shuffle` is executed OFFLINE.
        // And we will reveal the `nonce` and `cards` for verifying.
        // We can just use u128 to represent 16 cards.
        // Because (A * 4 + 2 * 4 + 3 * 4 + 4 * 4 + 5 = 45 > 21 * 2)
        // Actually (4 + 4 + 4 + 4 + 1 = 17) cards is needed, but we just use 16 cards.
        nonce: u64,
        cards: cards,
        index: u8, // The index of next card in cards

        player: address,
        points_of_player: u128,

        game_id: u64,
        // For simplicity
        // request_count: u64
    }

    // `cards` contains the orders of 16 cards
    struct cards {
        state: u128,
    }

    struct card {
        player: address,
        raw_point: u128,
        point: u128,
        game_id: u64,
    }

    // Player's transition
    transition request_start() -> start_request.leo/start_request {
        let sr: start_request = start_request.leo/new_start_reqeust(aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return sr;
    }

    // Casino's transition
    transition process_start_request(sr: start_request.leo/start_request, game_id: u64, nonce: u64) -> (random.leo/part1, random.leo/part2) {
        assert_eq(self.caller, aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return random.leo/exchange(game_id, nonce, sr.signer);
    }

    transition set_part2_nonce(p2: random.leo/part2, nonce: u64) -> random.leo/part2 {
        return random.leo/set_nonce(p2, nonce);
    }

    // Casino's transition
    transition start_game(p1: random.leo/part1, p2: random.leo/part2, state: u128) -> (game_state, public card, public card, public card) {
        assert_eq(self.caller, aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        // This transition ensure p1.id == p2.id
        let r: u64 = random.leo/combine(p1, p2);
        // let cs: cards = fisher_yates_shuffle(r);
        let cs: cards = cards {
            state: state,
        };
        //  card0 is the hidden card belongs to casino
        let card1: card = get_card(cs, 1u8, self.caller, p2.id);

        // p2.signer is this game's player
        let card2: card = get_card(cs, 2u8, p2.signer, p2.id);
        let card3: card = get_card(cs, 3u8, p2.signer, p2.id);

        // we return card1 card2 card3 as public output so that players could see them; 
        return (game_state {
            owner: self.caller,
            gates: 0u64,

            nonce: r,
            cards: cs,
            // Indicates next card is the 4th in cards 
            index: 4u8,

            player: p2.signer,
            points_of_player: card2.point + card3.point,
            game_id: p2.id
        }, card1, card2, card3);
    }

    // Player's transition
    // Generate a hit_request record for casino, then casino can call process_hit to get the next card for player
    transition request_hit() -> hit_request.leo/hit_request {
        let hr: hit_request = hit_request.leo/new_hit_request(aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return hr;
    }
    // Casino's transition
    // Return the new game_state and the next card, bool for the game is over;
    transition process_hit_request(gs: game_state, hr: hit_request.leo/hit_request) -> (public game_state, public card, public bool) {
        assert_eq(self.caller, aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        assert(gs.points_of_player <= 21u128);
        let c: card = get_card(gs.cards, gs.index, gs.player, gs.game_id);
        let new_gs: game_state = game_state {
            owner: gs.owner,
            gates: gs.gates,
            nonce: gs.nonce,
            cards: gs.cards,
            index: gs.index + 1u8,
            player: gs.player,
            points_of_player: gs.points_of_player + c.point,
            game_id: gs.game_id
        };
        // Game over, player's points > 21, winner is casino
        if new_gs.points_of_player > 21u128 {
            return (new_gs, c, true);
        }
        return (new_gs, c, false);
    }

    // Player's transition
    transition request_stand() -> stand_request.leo/stand_request {
        let sr: stand_request = stand_request.leo/new_stand_request(aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return sr;
    }

    // Casino's transition
    // Return the winner address of this game
    // TODO: Reveal nonce;
    transition process_stand_request(gs: game_state, sr: stand_request.leo/stand_request) -> (public address, public u128, public u64, public u8) {
        assert(gs.player == sr.signer);
        // Check
        if gs.points_of_player > 21u128 {
            return (gs.owner, gs.cards.state, gs.game_id, gs.index);
        }
        // The first two cards owned by casino
        let c0: card = get_card(gs.cards, 0u8, gs.player, gs.game_id);
        let c1: card = get_card(gs.cards, 1u8, gs.player, gs.game_id);
        let points_of_casino: u128 = c0.point + c1.point;

        if points_of_casino >= gs.points_of_player {
            return (gs.owner, gs.cards.state, gs.game_id, gs.index);
        }

        for i:u8 in 0u8..11u8 {
            let c: card = get_card(gs.cards, gs.index + i, gs.player, gs.game_id);
            points_of_casino = points_of_casino + c.point;
            
            // Broken, Winner is player
            if points_of_casino > 21u128 {
                return (sr.signer, gs.cards.state, gs.game_id, gs.index);
            }
            // Winner is casino
            if points_of_casino >= gs.points_of_player {
                return (gs.owner, gs.cards.state, gs.game_id, gs.index);
            }

            // There is no more cards, winner is player
            if i + gs.index == 15u8 {
                return (sr.signer, gs.cards.state, gs.game_id, gs.index);
            }
        }

        // unreachable
        return (gs.owner, gs.cards.state, gs.game_id, gs.index);
    }

    // Helper function to return the cards[index]
    function get_card(cs: cards, index: u8, player: address, game_id: u64) -> card {
        let state: u128 = cs.state;
        let v: u128 = (state >> (index * 8u8));
        let mask: u128 = 255u128;
        v = v.and(mask);
        // let color: u128 = v / 13u128;
        let point: u128 = v % 13u128;
        if point >= 10u128 {
            point = 10u128;
        }

        return card {
            player: player,
            raw_point: v,
            point: point,
            game_id: game_id,
        };
    }

    // // ATTENTION: THIS IS A MOCK FUNCTION
    // function fisher_yates_shuffle(r: u64) -> cards {
    //     // 01: ♠️A 02: ♠️2 ... 13: ♠️K
    //     // 14: ♥️A 15: ♥️2 ... 26: ♥️K
    //     // 27: ♣️A 28: ♣️2 ... 39: ♣️K
    //     // 40: ♦️A 41: ♦️2 ... 52: ♦️K
    //     // 2^64 = 18,446,744,073,709,551,616
    //     // part1:u64 010203040506070809   ♠️A -> ♠️9   9 cards
    //     // part2:u64 101112131415161718   ♠️10 -> ♥️5  9 cards
    //     // part3:u64 192021222324252627   ♥️6 ... ♣️2  9 cards
    //     // part4:u64 282930313233343536   ♣️2 ... ♣️10  9 cards
    //     // part5:u64 373839404142434445   ♣️8 ... ♦️6  9 cards
    //     // part6:u64 46474849505152       ♦️7 ... ♦️K  7 cards
    //     // reorder part1 part2 part3 part4 part5 part6 by nonce
    //     let cs: cards = cards {
    //         card1: 1u64,
    //         card2: 2u64,
    //         card3: 3u64,
    //         card4: 4u64,
    //         card52: 52u64,
    //     };
    //     let state: u64 = r;
    //     for i:u64 in 0u64..52u64 {
    //         let j: u64 = state.mod(i + 1u64);
    //         state = (state.mul(1103515245u64) + 12345u64).mod(2u64.pow(31u8));
    //         cs = swap_cards(cs, i, j);
    //     }
    //     return cs;
    // }

    // inline swap_cards(cs: cards, i: u64, j: u64) -> cards {
    //     let new_cs: cards = cards {
    //         card1: 1u64,
    //         card2: 2u64,
    //         card3: 3u64,
    //         card4: 4u64,
    //         card52: 52u64,
    //     };
    //     return new_cs;
    // }
}

// Player's functions:
// 1. request_start() -> start_request.leo/start_request
// 2. random.leo/set_nonce(random.leo/part2);
// 3. request_hit() -> hit_request.leo/hit_request
// 4. request_stand() -> stand_request.leo/stand_request


// Casino's functions
// 1. process_start_request(gs: game_state, sr: start_request.leo/start_request) -> (random.leo/part1, random.leo/part2)
// 2. process_hit_request(gs: game_state, hr: hit_request.leo/hit_request) -> game_state
// 3. process_stand_request(gs: game_state, sr: stand_request.leo/stand_request) -> public address
