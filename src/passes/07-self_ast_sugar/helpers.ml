open Ast_sugar
open Trace
open Stage_common.Helpers
open Stage_common

let bind_map_lmap_t f map = bind_lmap (
  LMap.map
    (fun ({associated_type;_} as field : _ row_element) ->
      let%bind field' = f associated_type in
      ok {field with associated_type = field'})
    map)

type ('a , 'err) folder = 'a -> expression -> ('a , 'err) result
let rec fold_expression : ('a, 'err) folder -> 'a -> expression -> ('a, 'err) result = fun f init e ->
  let self = fold_expression f in
  let%bind init' = f init e in
  match e.expression_content with
  | E_literal _ | E_variable _ | E_raw_code _ | E_skip -> ok init'
  | E_list lst | E_set lst  -> (
    let%bind res = bind_fold_list self init' lst in
    ok res
  )
  | E_map lst | E_big_map lst -> (
    let%bind res = bind_fold_list (bind_fold_pair self) init' lst in
    ok res
  )
  | E_constant c -> Folds.constant self init' c
  | E_application app -> Folds.application self init' app
  | E_lambda l -> Folds.lambda self (fun _ -> ok) init' l
  | E_ascription a -> Folds.ascription self (fun _ -> ok) init' a
  | E_constructor c -> Folds.constructor self init' c
  | E_matching {matchee=e; cases} -> (
      let%bind res = self init' e in
      let aux acc ({body ; _ }: _ Ast_sugar.match_case) = self acc body in
      let%bind res = bind_fold_list aux res cases in
      ok res
    )
  | E_record m -> Folds.record self init' m
  | E_update u -> Folds.update self init' u
  | E_accessor a -> Folds.accessor self init' a
  | E_tuple t -> Folds.tuple self init' t
  | E_let_in { let_binder = _ ; rhs ; let_result } -> (
      let%bind res = self init' rhs in
      let%bind res = self res let_result in
      ok res
    )
  | E_type_in ti -> Folds.type_in self (fun _ -> ok) init' ti
  | E_mod_in  mi -> Folds.mod_in  self (fun _ -> ok) init' mi
  | E_mod_alias  mi -> Folds.mod_alias  self init' mi
  | E_cond c -> Folds.conditional self init' c
  | E_recursive r -> Folds.recursive self (fun _ -> ok) init' r
  | E_sequence s -> Folds.sequence self init' s
  | E_module_accessor { module_name = _ ; element } -> (
    let%bind res = self init' element in
    ok res
  )

type 'err exp_mapper = expression -> (expression, 'err) result
type 'err ty_exp_mapper = type_expression -> (type_expression, 'err) result
type 'err abs_mapper =
  | Expression of 'err exp_mapper
  | Type_expression of 'err ty_exp_mapper
let rec map_expression : 'err exp_mapper -> expression -> (expression, 'err) result = fun f e ->
  let self = map_expression f in
  let%bind e' = f e in
  let return expression_content = ok { e' with expression_content } in
  match e'.expression_content with
  | E_list lst -> (
    let%bind lst' = bind_map_list self lst in
    return @@ E_list lst'
  )
  | E_set lst -> (
    let%bind lst' = bind_map_list self lst in
    return @@ E_set lst'
  )
  | E_map lst -> (
    let%bind lst' = bind_map_list (bind_map_pair self) lst in
    return @@ E_map lst'
  )
  | E_big_map lst -> (
    let%bind lst' = bind_map_list (bind_map_pair self) lst in
    return @@ E_big_map lst'
  )
  | E_ascription ascr -> (
      let%bind ascr = Maps.ascription self ok ascr in
      return @@ E_ascription ascr
  )
  | E_matching {matchee=e;cases} ->
    let%bind e' = self e in
    let aux { pattern ; body } =
      let%bind body' = self body in
      ok { pattern ; body = body'}
    in
    let%bind cases' = bind_map_list aux cases in
    return @@ E_matching {matchee=e';cases=cases'}
  | E_record m -> (
    let%bind m' = bind_map_lmap self m in
    return @@ E_record m'
  )
  | E_accessor acc -> (
      let%bind acc = Maps.accessor self acc in
      return @@ E_accessor acc
    )
  | E_update u -> (
    let%bind u = Maps.update self u in
    return @@ E_update u
  )
  | E_constructor c -> (
      let%bind c = Maps.constructor self c in
      return @@ E_constructor c
  )
  | E_application app -> (
    let%bind app = Maps.application self app in
    return @@ E_application app
  )
  | E_let_in { let_binder ; mut; rhs ; let_result; attributes } -> (
      let%bind rhs = self rhs in
      let%bind let_result = self let_result in
      return @@ E_let_in { let_binder ; mut; rhs ; let_result; attributes }
    )
  | E_type_in ti -> (
      let%bind ti = Maps.type_in self ok ti in
      return @@ E_type_in ti
    )
  | E_mod_in mi -> (
      let%bind mi = Maps.mod_in self ok mi in
      return @@ E_mod_in mi
    )
  | E_mod_alias ma -> (
      let%bind ma = Maps.mod_alias self ma in
      return @@ E_mod_alias ma
    )
  | E_lambda l -> (
      let%bind l = Maps.lambda self ok l in
      return @@ E_lambda l
    )
  | E_recursive r ->
      let%bind r = Maps.recursive self ok r in
      return @@ E_recursive r
  | E_constant c -> (
      let%bind c = Maps.constant self c in
      return @@ E_constant c
    )
  | E_cond c ->
      let%bind c = Maps.conditional self c in
      return @@ E_cond c
  | E_sequence s -> (
      let%bind s = Maps.sequence self s in
      return @@ E_sequence s
    )
  | E_tuple t -> (
    let%bind t' = bind_map_list self t in
    return @@ E_tuple t'
  )
  | E_module_accessor { module_name; element } -> (
    let%bind element = self element in
    return @@ E_module_accessor { module_name; element }
  )
  | E_literal _ | E_variable _ | E_raw_code _ | E_skip as e' -> return e'

and map_type_expression : 'err ty_exp_mapper -> type_expression -> (type_expression, 'err) result = fun f te ->
  let self = map_type_expression f in
  let%bind te' = f te in
  let return type_content = ok { type_content; location=te.location } in
  match te'.type_content with
  | T_sum temap ->
    let%bind temap' = Maps.rows self temap in
    return @@ T_sum temap'
  | T_record temap ->
    let%bind temap' = Maps.rows self temap in
    return @@ T_record temap'
  | T_tuple telst ->
    let%bind telst' = bind_map_list self telst in
    return @@ (T_tuple telst')
  | T_arrow arr ->
    let%bind arr = Maps.arrow self arr in
    return @@ T_arrow arr
  | T_app {type_operator;arguments} ->
    let%bind arguments = bind_map_list self arguments in
    return @@ T_app {type_operator;arguments}
  | T_variable _ -> ok te'
  | T_module_accessor ma ->
    let%bind ma = Maps.module_access self ma in
    return @@ T_module_accessor ma
  | T_singleton _ -> ok te'

and map_module : 'err abs_mapper -> module_ -> (module_, 'err) result = fun m p ->
  let aux = fun (x : declaration) ->
    match x,m with
    | (Declaration_constant dc, Expression m') -> (
        let%bind dc = Maps.declaration_constant (map_expression m') (ok) dc in
        ok (Declaration_constant dc)
      )
    | (Declaration_type dt, Type_expression m') -> (
        let%bind dt = Maps.declaration_type (map_type_expression m') dt in
        ok (Declaration_type dt)
      )
    | decl,_ -> ok decl
  (* | Declaration_type of (type_variable * type_expression) *)
  in
  bind_map_list (bind_map_location aux) p

type ('a, 'err) fold_mapper = 'a -> expression -> (bool * 'a * expression, 'err) result
let rec fold_map_expression : ('a, 'err) fold_mapper -> 'a -> expression -> ('a * expression, 'err) result = fun f a e ->
  let self = fold_map_expression f in
  let idle acc a = ok @@ (acc,a) in
  let%bind (continue, init',e') = f a e in
  if (not continue) then ok(init',e')
  else
  let return expression_content = { e' with expression_content } in
  match e'.expression_content with
  | E_list lst -> (
    let%bind (res, lst') = bind_fold_map_list self init' lst in
    ok (res, return @@ E_list lst')
  )
  | E_set lst -> (
    let%bind (res, lst') = bind_fold_map_list self init' lst in
    ok (res, return @@ E_set lst')
  )
  | E_map lst -> (
    let%bind (res, lst') = bind_fold_map_list (bind_fold_map_pair self) init' lst in
    ok (res, return @@ E_map lst')
  )
  | E_big_map lst -> (
    let%bind (res, lst') = bind_fold_map_list (bind_fold_map_pair self) init' lst in
    ok (res, return @@ E_big_map lst')
  )
  | E_ascription ascr -> (
      let%bind (res,ascr) = Fold_maps.ascription self idle init' ascr in
      ok (res, return @@ E_ascription ascr)
    )
  | E_matching {matchee=e;cases} ->
    let%bind (res,e') = self init' e in
    let aux acc { pattern ; body } =
      let%bind (res,body') = self acc body in
      ok (res,{ pattern ; body = body'})
    in
    let%bind (res, cases') = bind_fold_map_list aux res cases in
    ok @@ (res, return @@ E_matching {matchee=e';cases=cases'})
  | E_record m -> (
    let%bind (res, m') = bind_fold_map_lmap (fun res _ e -> self res e) init' m in
    ok (res, return @@ E_record m')
  )
  | E_accessor acc -> (
      let%bind (res, acc) = Fold_maps.accessor self init' acc in
      ok (res, return @@ E_accessor acc)
    )
  | E_update u -> (
    let%bind res,u = Fold_maps.update self init' u in
    ok (res, return @@ E_update u)
  )
  | E_tuple t -> (
    let%bind (res, t') = bind_fold_map_list self init' t in
    ok (res, return @@ E_tuple t')
  )
  | E_constructor c -> (
      let%bind (res,c) = Fold_maps.constructor self init' c in
      ok (res, return @@ E_constructor c)
  )
  | E_application app -> (
      let%bind res,app = Fold_maps.application self init' app in
      ok (res, return @@ E_application app)
    )
  | E_let_in { let_binder ; mut; rhs ; let_result; attributes } -> (
      let%bind (res,rhs) = self init' rhs in
      let%bind (res,let_result) = self res let_result in
      ok (res, return @@ E_let_in { let_binder ; mut; rhs ; let_result ; attributes })
    )
  | E_type_in ti -> (
      let%bind res,ti = Fold_maps.type_in self idle init' ti in
      ok (res, return @@ E_type_in ti)
    )
  | E_mod_in mi -> (
      let%bind res,mi = Fold_maps.mod_in self idle init' mi in
      ok (res, return @@ E_mod_in mi)
    )
  | E_mod_alias ma -> (
      let%bind res,ma = Fold_maps.mod_alias self init' ma in
      ok (res, return @@ E_mod_alias ma)
    )
  | E_lambda l -> (
      let%bind res,l = Fold_maps.lambda self idle init' l in
      ok ( res, return @@ E_lambda l)
    )
  | E_recursive r ->
      let%bind res,r = Fold_maps.recursive self idle init' r in
      ok ( res, return @@ E_recursive r)
  | E_constant c -> (
      let%bind res,c = Fold_maps.constant self init' c in
      ok (res, return @@ E_constant c)
    )
  | E_cond c ->
      let%bind res,c = Fold_maps.conditional self init' c in
      ok (res, return @@ E_cond c)
  | E_sequence s -> (
      let%bind res,s = Fold_maps.sequence self init' s in
      ok (res, return @@ E_sequence s)
    )
  | E_module_accessor { module_name; element } -> (
    let%bind (res,element) = self init' element in
    ok (res, return @@ E_module_accessor { module_name; element })
  )
  | E_literal _ | E_variable _ | E_raw_code _ | E_skip as e' -> ok (init', return e')