
let rec wwhile (f,b) =
  match f b with | (a,b) -> if not b then a else wwhile (f, a);;

let fixpoint (f,b) = if (wwhile (f, b)) = b then b else wwhile (f, (f b));;