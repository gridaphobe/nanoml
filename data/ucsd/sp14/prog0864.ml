
let rec digitsOfInt n =
  if n < 0
  then []
  else
    if (n / 10) = 0 then [n mod 10] else (digitsOfInt (n / 10)) @ [n mod 10];;

let rec sumList xs = match xs with | [] -> 0 | a::b -> a + (sumList b);;

let rec digitalRoot n =
  let sum = sumList (digitsOfInt n) in
  if sum < 10 then sum else digitalRoot sum;;

let _ = [digitalRoot 0 1; 2];;
