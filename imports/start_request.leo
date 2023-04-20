program start_request.aleo {

    record start_request {
        public owner: address,
        gates: u64,
        signer: address,
    }

    transition new_start_reqeust(owner: address) -> start_request {
        return start_request {
            owner: owner,
            gates: 0u64,
            signer: self.caller,
        };
    }
}
