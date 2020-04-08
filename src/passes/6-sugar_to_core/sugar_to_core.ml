module I = Ast_sugar
module O = Ast_core
open Trace

let rec idle_type_expression : I.type_expression -> O.type_expression result =
  fun te ->
  let return te = ok @@ O.make_t te in
  match te.type_content with
    | I.T_sum sum -> 
      let sum = I.CMap.to_kv_list sum in
      let%bind sum = 
        bind_map_list (fun (k,v) ->
          let%bind v = idle_type_expression v in
          ok @@ (k,v)
        ) sum
      in
      return @@ O.T_sum (O.CMap.of_list sum)
    | I.T_record record -> 
      let record = I.LMap.to_kv_list record in
      let%bind record = 
        bind_map_list (fun (k,v) ->
          let%bind v = idle_type_expression v in
          ok @@ (k,v)
        ) record
      in
      return @@ O.T_record (O.LMap.of_list record)
    | I.T_tuple tuple ->
      let aux (i,acc) el = 
        let%bind el = idle_type_expression el in
        ok @@ (i+1,(O.Label (string_of_int i), el)::acc) in
      let%bind (_, lst ) = bind_fold_list aux (0,[]) tuple in
      let record = O.LMap.of_list lst in
      return @@ O.T_record record
    | I.T_arrow {type1;type2} ->
      let%bind type1 = idle_type_expression type1 in
      let%bind type2 = idle_type_expression type2 in
      return @@ T_arrow {type1;type2}
    | I.T_variable type_variable -> return @@ T_variable type_variable 
    | I.T_constant type_constant -> return @@ T_constant type_constant
    | I.T_operator type_operator ->
      let%bind type_operator = idle_type_operator type_operator in
      return @@ T_operator type_operator

and idle_type_operator : I.type_operator -> O.type_operator result =
  fun t_o ->
  match t_o with
    | TC_contract c -> 
      let%bind c = idle_type_expression c in
      ok @@ O.TC_contract c
    | TC_option o ->
      let%bind o = idle_type_expression o in
      ok @@ O.TC_option o
    | TC_list l ->
      let%bind l = idle_type_expression l in
      ok @@ O.TC_list l
    | TC_set s ->
      let%bind s = idle_type_expression s in
      ok @@ O.TC_set s
    | TC_map (k,v) ->
      let%bind (k,v) = bind_map_pair idle_type_expression (k,v) in
      ok @@ O.TC_map (k,v)
    | TC_big_map (k,v) ->
      let%bind (k,v) = bind_map_pair idle_type_expression (k,v) in
      ok @@ O.TC_big_map (k,v)
    | TC_michelson_or (l,r) ->
      let%bind (l,r) = bind_map_pair idle_type_expression (l,r) in
      ok @@ O.TC_michelson_or (l,r)
    | TC_arrow (i,o) ->
      let%bind (i,o) = bind_map_pair idle_type_expression (i,o) in
      ok @@ O.TC_arrow (i,o)

let rec compile_expression : I.expression -> O.expression result =
  fun e ->
  let return expr = ok @@ O.make_e ~loc:e.location expr in
  match e.expression_content with
    | I.E_literal literal   -> return @@ O.E_literal literal
    | I.E_constant {cons_name;arguments} -> 
      let%bind arguments = bind_map_list compile_expression arguments in
      return @@ O.E_constant {cons_name;arguments}
    | I.E_variable name     -> return @@ O.E_variable name
    | I.E_application {lamb;args} -> 
      let%bind lamb = compile_expression lamb in
      let%bind args = compile_expression args in
      return @@ O.E_application {lamb; args}
    | I.E_lambda lambda ->
      let%bind lambda = compile_lambda lambda in
      return @@ O.E_lambda lambda
    | I.E_recursive {fun_name;fun_type;lambda} ->
      let%bind fun_type = idle_type_expression fun_type in
      let%bind lambda = compile_lambda lambda in
      return @@ O.E_recursive {fun_name;fun_type;lambda}
    | I.E_let_in {let_binder;inline;rhs;let_result} ->
      let (binder,ty_opt) = let_binder in
      let%bind ty_opt = bind_map_option idle_type_expression ty_opt in
      let%bind rhs = compile_expression rhs in
      let%bind let_result = compile_expression let_result in
      return @@ O.E_let_in {let_binder=(binder,ty_opt);inline;rhs;let_result}
    | I.E_constructor {constructor;element} ->
      let%bind element = compile_expression element in
      return @@ O.E_constructor {constructor;element}
    | I.E_matching {matchee; cases} ->
      let%bind matchee = compile_expression matchee in
      let%bind cases   = compile_matching cases in
      return @@ O.E_matching {matchee;cases}
    | I.E_record record ->
      let record = I.LMap.to_kv_list record in
      let%bind record = 
        bind_map_list (fun (k,v) ->
          let%bind v =compile_expression v in
          ok @@ (k,v)
        ) record
      in
      return @@ O.E_record (O.LMap.of_list record)
    | I.E_record_accessor {record;path} ->
      let%bind record = compile_expression record in
      return @@ O.E_record_accessor {record;path}
    | I.E_record_update {record;path;update} ->
      let%bind record = compile_expression record in
      let%bind update = compile_expression update in
      return @@ O.E_record_update {record;path;update}
    | I.E_map map -> (
      let map = List.sort_uniq compare map in
      let aux = fun prev (k, v) ->
        let%bind (k', v') = bind_map_pair (compile_expression) (k, v) in
        return @@ E_constant {cons_name=C_MAP_ADD;arguments=[k' ; v' ; prev]}
      in
      let%bind init = return @@ E_constant {cons_name=C_MAP_EMPTY;arguments=[]} in
      bind_fold_right_list aux init map
    )
    | I.E_big_map big_map -> (
      let big_map = List.sort_uniq compare big_map in
      let aux = fun prev (k, v) ->
        let%bind (k', v') = bind_map_pair (compile_expression) (k, v) in
        return @@ E_constant {cons_name=C_MAP_ADD;arguments=[k' ; v' ; prev]}
      in
      let%bind init = return @@ E_constant {cons_name=C_BIG_MAP_EMPTY;arguments=[]} in
      bind_fold_right_list aux init big_map
    )
    | I.E_list lst ->
      let%bind lst' = bind_map_list (compile_expression) lst in
      let aux = fun prev cur ->
        return @@ E_constant {cons_name=C_CONS;arguments=[cur ; prev]} in
      let%bind init  = return @@ E_constant {cons_name=C_LIST_EMPTY;arguments=[]} in
      bind_fold_right_list aux init lst'
    | I.E_set set -> (
      let%bind lst' = bind_map_list (compile_expression) set in
      let lst' = List.sort_uniq compare lst' in
      let aux = fun prev cur ->
        return @@ E_constant {cons_name=C_SET_ADD;arguments=[cur ; prev]} in
      let%bind init = return @@ E_constant {cons_name=C_SET_EMPTY;arguments=[]} in
      bind_fold_list aux init lst'
      )
    | I.E_look_up look_up ->
      let%bind (path, index) = bind_map_pair compile_expression look_up in
      return @@ O.E_constant {cons_name=C_MAP_FIND_OPT;arguments=[index;path]}
    | I.E_ascription {anno_expr; type_annotation} ->
      let%bind anno_expr = compile_expression anno_expr in
      let%bind type_annotation = idle_type_expression type_annotation in
      return @@ O.E_ascription {anno_expr; type_annotation}
    | I.E_cond {condition; then_clause; else_clause} ->
      let%bind matchee = compile_expression condition in
      let%bind match_true = compile_expression then_clause in
      let%bind match_false = compile_expression else_clause in
      return @@ O.E_matching {matchee; cases=Match_bool{match_true;match_false}}
    | I.E_sequence {expr1; expr2} ->
      let%bind expr1 = compile_expression expr1 in
      let%bind expr2 = compile_expression expr2 in
      return @@ O.E_let_in {let_binder=(Var.of_name "_", Some O.t_unit); rhs=expr1;let_result=expr2; inline=false}
    | I.E_skip -> ok @@ O.e_unit ~loc:e.location ()
    | I.E_tuple t ->
      let aux (i,acc) el = 
        let%bind el = compile_expression el in
        ok @@ (i+1,(O.Label (string_of_int i), el)::acc) in
      let%bind (_, lst ) = bind_fold_list aux (0,[]) t in
      let m = O.LMap.of_list lst in
      return @@ O.E_record m
    | I.E_tuple_accessor {tuple;path} ->
      let%bind record = compile_expression tuple in
      let path        = O.Label (string_of_int path) in
      return @@ O.E_record_accessor {record;path}
    | I.E_tuple_update {tuple;path;update} ->
      let%bind record = compile_expression tuple in
      let path        = O.Label (string_of_int path) in
      let%bind update = compile_expression update in
      return @@ O.E_record_update {record;path;update}

and compile_lambda : I.lambda -> O.lambda result =
  fun {binder;input_type;output_type;result}->
    let%bind input_type = bind_map_option idle_type_expression input_type in
    let%bind output_type = bind_map_option idle_type_expression output_type in
    let%bind result = compile_expression result in
    ok @@ O.{binder;input_type;output_type;result}
and compile_matching : I.matching_expr -> O.matching_expr result =
  fun m -> 
  match m with 
    | I.Match_bool {match_true;match_false} ->
      let%bind match_true = compile_expression match_true in
      let%bind match_false = compile_expression match_false in
      ok @@ O.Match_bool {match_true;match_false}
    | I.Match_list {match_nil;match_cons} ->
      let%bind match_nil = compile_expression match_nil in
      let (hd,tl,expr,tv) = match_cons in
      let%bind expr = compile_expression expr in
      ok @@ O.Match_list {match_nil; match_cons=(hd,tl,expr,tv)}
    | I.Match_option {match_none;match_some} ->
      let%bind match_none = compile_expression match_none in
      let (n,expr,tv) = match_some in
      let%bind expr = compile_expression expr in
      ok @@ O.Match_option {match_none; match_some=(n,expr,tv)}
    | I.Match_tuple ((lst,expr), tv) ->
      let%bind expr = compile_expression expr in
      ok @@ O.Match_tuple ((lst,expr), tv)
    | I.Match_variant (lst,tv) ->
      let%bind lst = bind_map_list (
        fun ((c,n),expr) ->
          let%bind expr = compile_expression expr in
          ok @@ ((c,n),expr)
      ) lst 
      in
      ok @@ O.Match_variant (lst,tv)
 
let compile_declaration : I.declaration Location.wrap -> _ =
  fun {wrap_content=declaration;location} ->
  let return decl = ok @@ Location.wrap ~loc:location decl in
  match declaration with 
  | I.Declaration_constant (n, te_opt, inline, expr) ->
    let%bind expr = compile_expression expr in
    let%bind te_opt = bind_map_option idle_type_expression te_opt in
    return @@ O.Declaration_constant (n, te_opt, inline, expr)
  | I.Declaration_type (n, te) ->
    let%bind te = idle_type_expression te in
    return @@ O.Declaration_type (n,te)

let compile_program : I.program -> O.program result =
  fun p ->
  bind_map_list compile_declaration p

(* uncompiling *)
let rec uncompile_type_expression : O.type_expression -> I.type_expression result =
  fun te ->
  let return te = ok @@ I.make_t te in
  match te.type_content with
    | O.T_sum sum -> 
      let sum = I.CMap.to_kv_list sum in
      let%bind sum = 
        bind_map_list (fun (k,v) ->
          let%bind v = uncompile_type_expression v in
          ok @@ (k,v)
        ) sum
      in
      return @@ I.T_sum (O.CMap.of_list sum)
    | O.T_record record -> 
      let record = I.LMap.to_kv_list record in
      let%bind record = 
        bind_map_list (fun (k,v) ->
          let%bind v = uncompile_type_expression v in
          ok @@ (k,v)
        ) record
      in
      return @@ I.T_record (O.LMap.of_list record)
    | O.T_arrow {type1;type2} ->
      let%bind type1 = uncompile_type_expression type1 in
      let%bind type2 = uncompile_type_expression type2 in
      return @@ T_arrow {type1;type2}
    | O.T_variable type_variable -> return @@ T_variable type_variable 
    | O.T_constant type_constant -> return @@ T_constant type_constant
    | O.T_operator type_operator ->
      let%bind type_operator = uncompile_type_operator type_operator in
      return @@ T_operator type_operator

and uncompile_type_operator : O.type_operator -> I.type_operator result =
  fun t_o ->
  match t_o with
    | TC_contract c -> 
      let%bind c = uncompile_type_expression c in
      ok @@ I.TC_contract c
    | TC_option o ->
      let%bind o = uncompile_type_expression o in
      ok @@ I.TC_option o
    | TC_list l ->
      let%bind l = uncompile_type_expression l in
      ok @@ I.TC_list l
    | TC_set s ->
      let%bind s = uncompile_type_expression s in
      ok @@ I.TC_set s
    | TC_map (k,v) ->
      let%bind (k,v) = bind_map_pair uncompile_type_expression (k,v) in
      ok @@ I.TC_map (k,v)
    | TC_big_map (k,v) ->
      let%bind (k,v) = bind_map_pair uncompile_type_expression (k,v) in
      ok @@ I.TC_big_map (k,v)
    | TC_map_or_big_map _ -> failwith "TC_map_or_big_map shouldn't be uncompiled"
    | TC_michelson_or (l,r) ->
      let%bind (l,r) = bind_map_pair uncompile_type_expression (l,r) in
      ok @@ I.TC_michelson_or (l,r)
    | TC_arrow (i,o) ->
      let%bind (i,o) = bind_map_pair uncompile_type_expression (i,o) in
      ok @@ I.TC_arrow (i,o)

let rec uncompile_expression : O.expression -> I.expression result =
  fun e ->
  let return expr = ok @@ I.make_e ~loc:e.location expr in
  match e.expression_content with 
    O.E_literal lit -> return @@ I.E_literal lit
  | O.E_constant {cons_name;arguments} -> 
    let%bind arguments = bind_map_list uncompile_expression arguments in
    return @@ I.E_constant {cons_name;arguments}
  | O.E_variable name     -> return @@ I.E_variable name
  | O.E_application {lamb; args} -> 
    let%bind lamb = uncompile_expression lamb in
    let%bind args = uncompile_expression args in
    return @@ I.E_application {lamb; args}
  | O.E_lambda lambda ->
    let%bind lambda = uncompile_lambda lambda in
    return @@ I.E_lambda lambda
  | O.E_recursive {fun_name;fun_type;lambda} ->
    let%bind fun_type = uncompile_type_expression fun_type in
    let%bind lambda = uncompile_lambda lambda in
    return @@ I.E_recursive {fun_name;fun_type;lambda}
  | O.E_let_in {let_binder;inline=false;rhs=expr1;let_result=expr2} when let_binder = (Var.of_name "_", Some O.t_unit) ->
    let%bind expr1 = uncompile_expression expr1 in
    let%bind expr2 = uncompile_expression expr2 in
    return @@ I.E_sequence {expr1;expr2}
  | O.E_let_in {let_binder;inline;rhs;let_result} ->
    let (binder,ty_opt) = let_binder in
    let%bind ty_opt = bind_map_option uncompile_type_expression ty_opt in
    let%bind rhs = uncompile_expression rhs in
    let%bind let_result = uncompile_expression let_result in
    return @@ I.E_let_in {let_binder=(binder,ty_opt);mut=false;inline;rhs;let_result}
  | O.E_constructor {constructor;element} ->
    let%bind element = uncompile_expression element in
    return @@ I.E_constructor {constructor;element}
  | O.E_matching {matchee; cases} ->
    let%bind matchee = uncompile_expression matchee in
    let%bind cases   = uncompile_matching cases in
    return @@ I.E_matching {matchee;cases}
  | O.E_record record ->
    let record = I.LMap.to_kv_list record in
    let%bind record = 
      bind_map_list (fun (k,v) ->
        let%bind v = uncompile_expression v in
        ok @@ (k,v)
      ) record
    in
    return @@ I.E_record (O.LMap.of_list record)
  | O.E_record_accessor {record;path} ->
    let%bind record = uncompile_expression record in
    return @@ I.E_record_accessor {record;path}
  | O.E_record_update {record;path;update} ->
    let%bind record = uncompile_expression record in
    let%bind update = uncompile_expression update in
    return @@ I.E_record_update {record;path;update}
  | O.E_ascription {anno_expr; type_annotation} ->
    let%bind anno_expr = uncompile_expression anno_expr in
    let%bind type_annotation = uncompile_type_expression type_annotation in
    return @@ I.E_ascription {anno_expr; type_annotation}

and uncompile_lambda : O.lambda -> I.lambda result =
  fun {binder;input_type;output_type;result}->
    let%bind input_type = bind_map_option uncompile_type_expression input_type in
    let%bind output_type = bind_map_option uncompile_type_expression output_type in
    let%bind result = uncompile_expression result in
    ok @@ I.{binder;input_type;output_type;result}
and uncompile_matching : O.matching_expr -> I.matching_expr result =
  fun m -> 
  match m with 
    | O.Match_bool {match_true;match_false} ->
      let%bind match_true = uncompile_expression match_true in
      let%bind match_false = uncompile_expression match_false in
      ok @@ I.Match_bool {match_true;match_false}
    | O.Match_list {match_nil;match_cons} ->
      let%bind match_nil = uncompile_expression match_nil in
      let (hd,tl,expr,tv) = match_cons in
      let%bind expr = uncompile_expression expr in
      ok @@ I.Match_list {match_nil; match_cons=(hd,tl,expr,tv)}
    | O.Match_option {match_none;match_some} ->
      let%bind match_none = uncompile_expression match_none in
      let (n,expr,tv) = match_some in
      let%bind expr = uncompile_expression expr in
      ok @@ I.Match_option {match_none; match_some=(n,expr,tv)}
    | O.Match_tuple ((lst,expr), tv) ->
      let%bind expr = uncompile_expression expr in
      ok @@ O.Match_tuple ((lst,expr), tv)
    | O.Match_variant (lst,tv) ->
      let%bind lst = bind_map_list (
        fun ((c,n),expr) ->
          let%bind expr = uncompile_expression expr in
          ok @@ ((c,n),expr)
      ) lst 
      in
      ok @@ I.Match_variant (lst,tv)
