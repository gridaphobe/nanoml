
let stringOfList f l =
  match l with
  | [] -> ""
  | h::t ->
      let m b = "[" ^ (b ^ "]") in
      let n a x = a ^ (" ;" ^ x) in let base = f h in List.fold_left n base t;;

let _ = stringOfList string_of_int [1; 2; 3; 4; 5; 6];;