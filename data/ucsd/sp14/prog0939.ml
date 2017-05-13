
type expr =
  | VarX
  | VarY
  | Sine of expr
  | Cosine of expr
  | Average of expr* expr
  | Times of expr* expr
  | Thresh of expr* expr* expr* expr;;

let buildAverage (e1,e2) = Average (e1, e2);;

let buildCosine e = Cosine e;;

let buildSine e = Sine e;;

let buildTimes (e1,e2) = Times (e1, e2);;

let buildX () = VarX;;

let buildY () = VarY;;

type expr =
  | VarX
  | VarY
  | Sine of expr
  | Cosine of expr
  | Average of expr* expr
  | Times of expr* expr
  | Thresh of expr* expr* expr* expr;;

let pi = 4.0 *. (atan 1.0);;

let rec eval (e,x,y) =
  match e with
  | VarX  -> x
  | VarY  -> y
  | Sine e1 -> sin (pi *. (eval (e1, x, y)))
  | Cosine e1 -> cos (pi *. (eval (e1, x, y)))
  | Average (e1,e2) -> ((eval (e1, x, y)) +. (eval (e2, x, y))) /. 2.0
  | Times (e1,e2) -> (eval (e1, x, y)) *. (eval (e2, x, y))
  | Thresh (a,b,a_less,b_less) ->
      if (eval (a, x, y)) < (eval (b, x, y))
      then (Printf.printf "hi"; eval (a_less, x, y))
      else (Printf.printf "bye"; eval (b_less, x, y));;

let sampleExpr =
  buildCosine
    (buildSine
       (buildTimes
          ((buildCosine
              (buildAverage
                 ((buildCosine (buildX ())),
                   (buildTimes
                      ((buildCosine
                          (buildCosine
                             (buildAverage
                                ((buildTimes ((buildY ()), (buildY ()))),
                                  (buildCosine (buildX ())))))),
                        (buildCosine
                           (buildTimes
                              ((buildSine (buildCosine (buildY ()))),
                                (buildAverage
                                   ((buildSine (buildX ())),
                                     (buildTimes ((buildX ()), (buildX ()))))))))))))),
            (buildY ()))));;

let _ = eval (sampleExpr, 0.5, 0.2);;
