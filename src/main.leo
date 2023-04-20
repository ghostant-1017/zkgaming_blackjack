// The 'zkgaming_blackjack' program.
import random.leo;
import start_request.leo;
import hit_request.leo;
import stand_request.leo;


program zkgaming_blackjack.aleo {
    record game_state {
        owner: address,
        gates: u64,

        cards: cards,
        index: u64,
        // 0: started
        // 1: player2 has STAND
        // 2: player2 has BROKEN
        player: address,
        points_of_player: u64,

        game_id: u64,
    }

    // cards contains the orders of 52 cards
    struct cards {
        card1: u64,
        card2: u64,
        card3: u64,
        card4: u64,
        // ....
        // ....
        card52: u64,
    }

    struct card {
        player: address,
        point: u64,
        game_id: u64,
    }

    transition request_start() -> start_request.leo/start_request {
        let sr: start_request = start_request.leo/new_start_reqeust(aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return sr;
    }

    transition process_start_request(sr: start_request.leo/start_request, game_id: u64, nonce: u64) -> (random.leo/part1, random.leo/part2) {
        return random.leo/exchange(game_id, nonce, sr.signer);
    }

    // Only casino can call this transition to generate a game_state 
    transition start_game(p1: random.leo/part1, p2: random.leo/part2) -> (game_state, public card, public card, public card) {
        assert_eq(self.caller, aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        // This transition ensure p1.id == p2.id
        let r: u64 = random.leo/combine(p1, p2);
        let cs: cards = fisher_yates_shuffle(r);

        //  card0 is the hidden card belongs to casino
        let card1: card = get_card(cs, 1u64, self.caller, p2.id);

        // p2.signer is this game's player
        let card2: card = get_card(cs, 2u64, p2.signer, p2.id);
        let card3: card = get_card(cs, 3u64, p2.signer, p2.id);

        // we return card1 card2 card3 as public output so that players could see them; 
        return (game_state {
            owner: self.caller,
            gates: 0u64,

            cards: cs,

            // Indicates next card is the 4th in cards 
            index: 4u64,

            player: p2.signer,
            points_of_player: card2.point + card3.point,
            game_id: p2.id
        }, card1, card2, card3);
    }

    // Generate a hit_request record for casino, then casino can call process_hit to get the next card for player
    transition request_hit() -> hit_request.leo/hit_request {
        let hr: hit_request = hit_request.leo/new_hit_request(aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return hr;
    }

    // return the new game_state and the next card, bool for the game is over;
    transition process_hit_request(gs: game_state, hr: hit_request.leo/hit_request) -> (game_state, public card, public bool) {
        assert_eq(self.caller, aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        assert(gs.points_of_player <= 21u64);
        let c: card = get_card(gs.cards, gs.index, gs.player, gs.game_id);
        let new_gs: game_state = game_state {
            owner: gs.owner,
            gates: gs.gates,
            cards: gs.cards,
            index: gs.index + 1u64,
            player: gs.player,
            points_of_player: gs.points_of_player + c.point,
            game_id: gs.game_id
        };
        if new_gs.points_of_player > 21u64 {
            return (new_gs, c, true);
        }
        return (new_gs, c, false);
    }

    
    transition request_stand() -> stand_request.leo/stand_request {
        let sr: stand_request = stand_request.leo/new_stand_request(aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px);
        return sr;
    }

    // return the winner address of this game
    transition process_stand_request(gs: game_state, sr: stand_request.leo/stand_request) -> public address {
        assert(gs.player == sr.signer);
        // The first two cards owned by casino
        let c0: card = get_card(gs.cards, 0u64, gs.player, gs.game_id);
        let c1: card = get_card(gs.cards, 1u64, gs.player, gs.game_id);
        let points_of_casino: u64 = c0.point + c1.point;

        if points_of_casino >= gs.points_of_player {
            return gs.owner;
        }

        // loop until winner comes, there is at most ten cards. A A A A 2 2 2 2 3 3 3
        for i:u64 in 0u64..9u64 {
            let c: card = get_card(gs.cards, gs.index + i, gs.player, gs.game_id);
            points_of_casino = points_of_casino + c.point;
            
            // broken
            if points_of_casino > 21u64 {
                return sr.signer;
            }
            // winner
            if points_of_casino >= gs.points_of_player {
                return gs.owner;
            }
        } 

        // unreachable
        return gs.owner;
    }

    // ATTENTION: THIS IS A MOCK FUNCTION
    function fisher_yates_shuffle(r: u64) -> cards {
        // 01: ♠️A 02: ♠️2 ... 13: ♠️K
        // 14: ♥️A 15: ♥️2 ... 26: ♥️K
        // 27: ♣️A 28: ♣️2 ... 39: ♣️K
        // 40: ♦️A 41: ♦️2 ... 52: ♦️K
        // 2^64 = 18,446,744,073,709,551,616
        // part1:u64 010203040506070809   ♠️A -> ♠️9   9 cards
        // part2:u64 101112131415161718   ♠️10 -> ♥️5  5 cards
        // part3:u64 192021222324252627   ♥️6 ... ♣️2  9 cards
        // part4:u64 282930313233343536   ♣️2 ... ♣️10  9 cards
        // part5:u64 373839404142434445   ♣️8 ... ♦️6  9 cards
        // part6:u64 46474849505152       ♦️7 ... ♦️K  7 cards
        // reorder part1 part2 part3 part4 part5 part6 by nonce
        let cs: cards = cards {
            card1: 1u64,
            card2: 2u64,
            card3: 3u64,
            card4: 4u64,
            card52: 52u64,
        };
        let state: u64 = r;
        for i:u64 in 0u64..52u64 {
            let j: u64 = state.mod(i + 1u64);
            state = (state.mul(1103515245u64) + 12345u64).mod(2u64.pow(31u8));
            cs = swap_cards(cs, i, j);
        }
        return cs;
    }

    // Helper function to return the cards[index]
    function get_card(cs: cards, index: u64, player: address, game_id: u64) -> card {
        return card{
            player: player,
            point: 1u64,
            game_id: game_id,
        };
    }

    inline swap_cards(cs: cards, i: u64, j: u64) -> cards {
        let new_cs: cards = cards {
            card1: 1u64,
            card2: 2u64,
            card3: 3u64,
            card4: 4u64,
            card52: 52u64,
        };
        return new_cs;
    }
}
