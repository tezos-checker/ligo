let test (k : int) : int =
  let j : int = k + 5
  in let close : int -> int = fun (i : int) -> i + j
     in let j : int = 20
        in close 20
