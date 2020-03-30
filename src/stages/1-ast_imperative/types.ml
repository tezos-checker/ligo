[@@@warning "-30"]

module Location = Simple_utils.Location

module Ast_imperative_parameter = struct
  type type_meta = unit
end

include Stage_common.Types

(*include Ast_generic_type(Ast_core_parameter)
*)
include Ast_generic_type (Ast_imperative_parameter)

type inline = bool 
type program = declaration Location.wrap list
and declaration =
  | Declaration_type of (type_variable * type_expression)

  (* A Declaration_constant is described by
   *   a name
   *   an optional type annotation
   *   a boolean indicating whether it should be inlined
   *   an expression *)
  | Declaration_constant of (expression_variable * type_expression option * inline * expression)

(* | Macro_declaration of macro_declaration *)
and expression = {expression_content: expression_content; location: Location.t}

and expression_content =
  (* Base *)
  | E_literal of literal
  | E_constant of constant (* For language constants, like (Cons hd tl) or (plus i j) *)
  | E_variable of expression_variable
  | E_application of application
  | E_lambda of lambda
  | E_recursive of recursive
  | E_let_in of let_in
  (* Variant *)
  | E_constructor of constructor (* For user defined constructors *)
  | E_matching of matching
  (* Record *)
  | E_record of expression label_map
  | E_record_accessor of accessor
  | E_record_update of update
  (* Advanced *)
  | E_ascription of ascription
  (* Sugar *)
  | E_sequence of sequence
  | E_skip
  (* Data Structures *)
  | E_map of (expression * expression) list 
  | E_big_map of (expression * expression) list
  | E_list of expression list
  | E_set of expression list
  | E_look_up of (expression * expression)
  (* Imperative *)
  | E_assign of assign
  | E_for of for_
  | E_for_each of for_each
  | E_while of while_loop

and constant =
  { cons_name: constant' (* this is at the end because it is huge *)
  ; arguments: expression list }

and application = {
  lamb: expression ; 
  args: expression ;
  }

and lambda =
  { binder: expression_variable
  ; input_type: type_expression option
  ; output_type: type_expression option
  ; result: expression }

and recursive = {
  fun_name :  expression_variable;
  fun_type : type_expression;
  lambda : lambda;
}

and let_in =
  { let_binder: expression_variable * type_expression option
  ; rhs: expression
  ; let_result: expression
  ; inline: bool }

and constructor = {constructor: constructor'; element: expression}

and accessor = {record: expression; label: label}

and update = {record: expression; path: label ; update: expression}

and matching_expr = (expr,unit) matching_content
and matching =
  { matchee: expression
  ; cases: matching_expr
  }

and ascription = {anno_expr: expression; type_annotation: type_expression}
and sequence = {
  expr1: expression ;
  expr2: expression ;
  }

and assign = {
  variable : expression_variable;
  access_path : access list;
  expression : expression;
}

and access =
  | Access_tuple of int
  | Access_record of string
  | Access_map of expr

and for_ = {
  binder : expression_variable;
  start : expression;
  final : expression;
  increment : expression;
  body : expression;
}

and for_each = {
  binder : expression_variable * expression_variable option;
  collection : expression;
  collection_type : collect_type;
  body : expression;
}

and collect_type = 
 | Map
 | Set
 | List

and while_loop = {
  condition : expression;
  body : expression;
}

and environment_element_definition =
  | ED_binder
  | ED_declaration of (expression * free_variables)

and free_variables = expression_variable list

and environment_element =
  { type_value: type_expression
  ; source_environment: full_environment
  ; definition: environment_element_definition }

and environment = (expression_variable * environment_element) list

and type_environment = (type_variable * type_expression) list

(* SUBST ??? *)
and small_environment = environment * type_environment

and full_environment = small_environment List.Ne.t

and expr = expression

and texpr = type_expression
