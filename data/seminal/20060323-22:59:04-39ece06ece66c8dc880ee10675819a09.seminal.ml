type exp = Int of int | Var of string 
       | Plus of exp * exp | Times of exp * exp
type stmt = Skip | Assign of string * exp
         | Seq of stmt * stmt 
         | If of exp * stmt * stmt
         | While of exp * stmt
         | SaveHeap of string
         | RestoreHeap of string
         
type heap = heapElement list
and heapElement = Var of (string * int)
  | Heap of (string * heap)

let rec lookup_raw h str =
  match h with
    [] -> 0 (* ############### *)
  | Var(s,i)::tl -> if s=str then Var(s,i) else lookup_raw tl str
  | Heap(s,newHeap)::tl -> if s=str then Heap(s,newHeap) else lookup_raw tl str

let lookup_var h str = 
  match lookup_raw h str with
    0 -> 0
  | Var(_,i) -> i
  | Heap(_) -> 0

let update_raw h he = he::h
  
let update_var h str i = update_raw h Var(str, i)

let update_heap h str = update_raw h Heap(str, h)
  
let rec interp_e (h:heap) (e:exp) =
 match e with
  Int i       ->i
 |Var str     ->lookup_var h str
 |Plus(e1,e2) ->(interp_e h e1)+(interp_e h e2)
 |Times(e1,e2)->(interp_e h e1)*(interp_e h e2)

let rec interp_s (h:heap) (s:stmt) =
  match s with
   Skip -> h
  |Seq(s1,s2) -> let h2 = interp_s h s1 in 
                 interp_s h2 s2
  |If(e,s1,s2) -> if (interp_e h e) <> 0
                  then interp_s h s1 
                  else interp_s h s2
  |Assign(str,e) -> update h str (interp_e h e)
  |While(e,s1) -> if (interp_e h e) <> 0
                  then let h2 = interp_s h s1 in
                       interp_s h2 s
                  else h
  |SaveHeap(str) -> update_heap h str
  |RestoreHeap(str) -> (match lookup_raw h str with
                          0 -> h
                        | Var(_) -> h
                        | Heap(_, newHeap) -> newHeap)

let mt_heap = [] 

let interp_prog s = 
  lookup (interp_s mt_heap s) "ans"
