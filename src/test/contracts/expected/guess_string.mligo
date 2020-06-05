type storage = {challenge : string}

type param = {new_challenge : string; attempt : string}

type return = operation list * storage

let attempt (p, store : param * storage) : return =
  let contract : unit contract =
    match (Tezos.get_contract_opt Tezos.sender
           : unit contract option)
    with
      Some contract -> contract
    | None -> (failwith "No contract" : unit contract)
  in let transfer : operation =
       Tezos.transaction (unit, contract, 10000000mutez)
     in let store : storage = {challenge = p.new_challenge}
        in ([] : operation list), store
