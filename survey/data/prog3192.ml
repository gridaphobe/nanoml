let rec sumList xs =
  match sumList with
  | [] -> 0
  | h::t -> h + sumList t

let _ = sumList [1]
