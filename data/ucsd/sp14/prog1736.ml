
type expr =
  | VarX
  | VarY
  | Sine of expr
  | Cosine of expr
  | Average of expr* expr
  | Times of expr* expr
  | Thresh of expr* expr* expr* expr
  | Timmy1 of expr* expr;;

let pi = 4.0 *. (atan 1.0);;

let rec eval (e,x,y) =
  match e with
  | VarX  -> x
  | VarY  -> y
  | Sine e -> sin (pi *. (eval (e, x, y)))
  | Cosine e -> cos (pi *. (eval (e, x, y)))
  | Average (e1,e2) -> ((eval (e1, x, y)) +. (eval (e2, x, y))) /. 2.0
  | Times (e1,e2) -> (eval (e1, x, y)) *. (eval (e2, x, y))
  | Thresh (e1,e2,e3,e4) ->
      if (eval (e1, x, y)) < (eval (e2, x, y))
      then eval (e3, x, y)
      else eval (e4, x, y)
  | Timmy1 (e1,e2) ->
      ((sin (pi *. (eval (e1, x, y)))) ** 2.0) *.
        (cos (pi *. (eval (e2, x, y))));;

let rec ffor (low,high,f) =
  if low > high then () else (let _ = f low in ffor ((low + 1), high, f));;

let toIntensity z = int_of_float (127.5 +. (127.5 *. z));;

let toReal (i,n) = (float_of_int i) /. (float_of_int n);;

type expr =
  | VarX
  | VarY
  | Sine of expr
  | Cosine of expr
  | Average of expr* expr
  | Times of expr* expr
  | Thresh of expr* expr* expr* expr
  | Timmy1 of expr* expr
  | Timmy2 of expr* expr* expr;;

let buildAverage (e1,e2) = Average (e1, e2);;

let buildCosine e = Cosine e;;

let buildSine e = Sine e;;

let buildThresh (a,b,a_less,b_less) = Thresh (a, b, a_less, b_less);;

let buildTimes (e1,e2) = Times (e1, e2);;

let buildTimmy1 (e1,e2) = Timmy1 (e1, e2);;

let buildTimmy2 (e1,e2,e3) = Timmy2 (e1, e2, e3);;

let buildX () = VarX;;

let buildY () = VarY;;

let rec build (rand,depth) =
  if depth > 0
  then
    let rnd = rand (0, 6) in
    (if (rnd mod 7) = 0
     then buildSine (build (rand, (depth - 1)))
     else
       if (rnd mod 7) = 1
       then buildCosine (build (rand, (depth - 1)))
       else
         if (rnd mod 7) = 2
         then
           buildAverage
             ((build (rand, (depth - 1))), (build (rand, (depth - 1))))
         else
           if (rnd mod 7) = 3
           then
             buildTimes
               ((build (rand, (depth - 1))), (build (rand, (depth - 1))))
           else
             if (rnd mod 7) = 4
             then
               buildThresh
                 ((build (rand, (depth - 1))), (build (rand, (depth - 1))),
                   (build (rand, (depth - 1))), (build (rand, (depth - 1))))
             else
               if (rnd mod 7) = 5
               then
                 buildTimmy1
                   ((build (rand, (depth - depth))),
                     (build (rand, (depth - depth))))
               else
                 buildTimmy2
                   ((build (rand, (depth - 1))), (build (rand, (depth - 1))),
                     (build (rand, (depth - 1)))))
  else
    (let rnd = rand (0, 2) in
     if (rnd mod 2) = 0 then buildX () else buildY ());;

let emitGrayscale (f,n,name) =
  let fname = "art_g_" ^ name in
  let chan = open_out (fname ^ ".pgm") in
  let n2p1 = (n * 2) + 1 in
  let _ = output_string chan (Format.sprintf "P5 %d %d 255\n" n2p1 n2p1) in
  let _ =
    ffor
      ((- n), n,
        (fun ix  ->
           ffor
             ((- n), n,
               (fun iy  ->
                  let x = toReal (ix, n) in
                  let y = toReal (iy, n) in
                  let z = f (x, y) in
                  let iz = toIntensity z in output_char chan (char_of_int iz))))) in
  close_out chan;
  ignore (Sys.command ("convert " ^ (fname ^ (".pgm " ^ (fname ^ ".jpg")))));
  ignore (Sys.command ("rm " ^ (fname ^ ".pgm")));;

let eval_fn e (x,y) =
  let rv = eval (e, x, y) in assert (((-1.0) <= rv) && (rv <= 1.0)); rv;;

let rec exprToString e =
  match e with
  | VarX  -> "x"
  | VarY  -> "y"
  | Sine e -> "sin(pi*" ^ ((exprToString e) ^ ")")
  | Cosine e -> "cos(pi*" ^ ((exprToString e) ^ ")")
  | Average (e,f) ->
      "((" ^ ((exprToString e) ^ ("*" ^ ((exprToString f) ^ ")/2)")))
  | Times (e,f) ->
      "(" ^ ((exprToString e) ^ ("*" ^ ((exprToString f) ^ ")")))
  | Thresh (e,f,g,h) ->
      "(" ^
        ((exprToString e) ^
           ("<" ^
              ((exprToString f) ^
                 ("?" ^ ((exprToString g) ^ (":" ^ ((exprToString h) ^ ")")))))))
  | Timmy1 (e1,e2) ->
      "sin^2(pi*" ^
        ((exprToString e1) ^ (")*" ^ ("cos(pi*" ^ ((exprToString e2) ^ ")"))))
  | Timmy2 (e1,e2,e3) ->
      "sin^.5(pi*" ^
        ((exprToString e1) ^
           (")*" ^
              ("(cos^2(pi*" ^
                 ((exprToString e2) ^
                    (")*" ^ ("cos(" ^ ((exprToString e3) ^ "))")))))));;

let makeRand (seed1,seed2) =
  let seed = Array.of_list [seed1; seed2] in
  let s = Random.State.make seed in
  fun (x,y)  -> x + (Random.State.int s (y - x));;

let doRandomGray (depth,seed1,seed2) =
  let g = makeRand (seed1, seed2) in
  let e = build (g, depth) in
  let _ = print_string (exprToString e) in
  let f = eval_fn e in
  let n = 150 in
  let name = Format.sprintf "%d_%d_%d" depth seed1 seed2 in
  emitGrayscale (f, n, name);;
