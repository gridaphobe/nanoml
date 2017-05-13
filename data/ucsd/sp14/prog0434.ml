
let explode s =
  let rec go i =
    if i >= (String.length s) then [] else (s.[i]) :: (go (i + 1)) in
  go 0;;

let palindrome w = failwith "TBD";;

let rec append xs1 xs2 =
  match xs1 with | [] -> xs2 | hd::tl -> hd :: (append tl xs2);;

let explode s =
  let rec go i =
    if i >= (String.length s) then [] else (s.[i]) :: (go (i + 1)) in
  go 0;;

let rec listReverse l =
  match l with | [] -> [] | hd::tl -> append (listReverse tl) [hd];;

let palindrome w =
  match explode w with
  | [] -> true
  | head::[] -> true
  | head::tail ->
      if head = (List.hd (listReverse tail))
      then palindrome (List.tl (listReverse tail))
      else false;;

let palindrome w =
  match explode w with
  | [] -> true
  | hd::[] -> true
  | hd::tl ->
      (match listReverse tl with
       | hdr::tlr -> if hdr = hd then palindrome tlr else false);;
