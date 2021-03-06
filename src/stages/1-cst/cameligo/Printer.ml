[@@@warning "-42"]
[@@@coverage exclude_file]

open CST

module Directive = LexerLib.Directive
module Region = Simple_utils.Region
open! Region

let sprintf = Printf.sprintf

type state = <
  offsets  : bool;
  mode     : [`Point | `Byte];
  buffer   : Buffer.t;
  pad_path : string;
  pad_node : string;
  pad      : int -> int -> state
>

let mk_state ~offsets ~mode ~buffer =
  object
    method offsets  = offsets;
    method mode     = mode;
    method buffer   = buffer
    val pad_path    = ""
    method pad_path = pad_path
    val pad_node    = ""
    method pad_node = pad_node

    (* The method [pad] updates the current padding, which is
       comprised of two components: the padding to reach the new node
       (space before reaching a subtree, then a vertical bar for it)
       and the padding for the new node itself (Is it the last child
       of its parent?).

       A child node that is not the last satisfies [rank < arity] and
       the last child satisfies [rank = arity], where the rank of the
       first child is 0. *)

    method pad arity rank =
      {< pad_path =
           pad_node ^ (if rank = arity-1 then "`-- " else "|-- ");
         pad_node =
           pad_node ^ (if rank = arity-1 then "    " else "|   ")
      >}
  end

let compact state (region: Region.t) =
  region#compact ~offsets:state#offsets state#mode

(* Printing the tokens with their source regions *)

let print_nsepseq :
  state -> string -> (state -> 'a -> unit) ->
  ('a, Region.t) Utils.nsepseq -> unit =
  fun state sep print (head, tail) ->
    let print_aux (sep_reg, item) =
      let sep_line =
        sprintf "%s: %s\n" (compact state sep_reg) sep in
      Buffer.add_string state#buffer sep_line;
      print state item
    in print state head; List.iter print_aux tail

let print_sepseq :
  state -> string -> (state -> 'a -> unit) ->
  ('a, Region.t) Utils.sepseq -> unit =
  fun state sep print -> function
        None -> ()
  | Some seq -> print_nsepseq state sep print seq

let print_option : state -> (state -> 'a -> unit ) -> 'a option -> unit =
  fun state print -> function
    None -> ()
  | Some opt -> print state opt

let print_csv state print {value; _} =
  print_nsepseq state "," print value

let print_markup state c = 
  let markup = match c with 
    LineCom (c, _) -> sprintf "// %s" c.value
  | BlockCom (c, _) -> sprintf "(* %s *)" c.value
  in
  Buffer.add_string state#buffer markup

let print_markup state comments = 
  List.iter (print_markup state) comments

let print_token state region lexeme =
  print_markup state region#markup;
  let line =
    sprintf "%s: %s\n" (compact state region) lexeme
  in Buffer.add_string state#buffer line

let print_var state {region; value} =
  let line =
    sprintf "%s: Ident %s\n"
            (compact state region)value
  in Buffer.add_string state#buffer line

let print_constr state {region; value} =
  let line =
    sprintf "%s: Constr \"%s\"\n"
            (compact state region) value
  in Buffer.add_string state#buffer line

let print_pvar state {region; value} =
  let line =
    sprintf "%s: PVar %s\n"
            (compact state region) value
  in Buffer.add_string state#buffer line

let print_string state {region; value} =
  let line =
    sprintf "%s: String %S\n"
            (compact state region) value
  in Buffer.add_string state#buffer line

let print_verbatim state {region; value} =
  let line =
    sprintf "%s: Verbatim %S\n"
            (compact state region) value
  in Buffer.add_string state#buffer line

let print_bytes state {region; value} =
  let lexeme, abstract = value in
  let line =
    sprintf "%s: Bytes (\"%s\", \"0x%s\")\n"
            (compact state region) lexeme
            (Hex.show abstract)
  in Buffer.add_string state#buffer line

let print_int state {region; value} =
  let lexeme, abstract = value in
  let line =
    sprintf "%s: Int (\"%s\", %s)\n"
            (compact state region) lexeme
            (Z.to_string abstract)
  in Buffer.add_string state#buffer line

let print_nat state {region; value} =
  let lexeme, abstract = value in
  let line =
    sprintf "%s: Nat (\"%s\", %s)\n"
            (compact state region) lexeme
            (Z.to_string abstract)
  in Buffer.add_string state#buffer line

let rec print_tokens state {decl;eof} =
  Utils.nseq_iter (print_statement state) decl;
  print_token state eof "EOF"

and print_attributes state attributes =
  let apply {value = attribute; region} =
    let attribute_formatted = sprintf "[@%s]" attribute in
    print_token state region attribute_formatted
  in List.iter apply attributes

and print_statement state = function
  Let {value=kwd_let, kwd_rec, let_binding, attributes; _} ->
    print_attributes   state attributes;
    print_token        state kwd_let "let";
    print_token_opt    state kwd_rec "rec";
    print_let_binding  state let_binding;
| TypeDecl {value={kwd_type; name; eq; type_expr}; _} ->
    print_token     state kwd_type "type";
    print_var       state name;
    print_token     state eq "=";
    print_type_expr state type_expr
| ModuleDecl {value={kwd_module; name; eq; kwd_struct; module_; kwd_end}; _} ->
    print_token  state kwd_module "module";
    print_var    state name;
    print_token  state eq "=";
    print_token  state kwd_struct "struct";
    print_tokens state module_;
    print_token  state kwd_end "end";
| ModuleAlias {value={kwd_module; alias; eq; binders}; _} ->
    print_token   state kwd_module "module";
    print_var     state alias;
    print_token   state eq "=";
    print_nsepseq state "." print_var binders;
| Directive dir -> print_directive state dir

and print_directive state dir =
  let s =
    Directive.to_string ~offsets:state#offsets state#mode dir
  in Buffer.add_string state#buffer s

and print_type_expr state = function
  TProd prod      -> print_cartesian state prod
| TSum sum        -> print_sum_type state sum
| TRecord t       -> print_record_type state t
| TApp app        -> print_type_app state app
| TPar par        -> print_type_par state par
| TVar var        -> print_var state var
| TWild wild      -> print_token state wild " "
| TFun t          -> print_fun_type state t
| TString s       -> print_string state s
| TInt x          -> print_int state x
| TModA   ma          -> print_module_access print_type_expr state ma

and print_sum_type state {value; _} =
  let {variants; attributes; lead_vbar} = value in
  print_attributes state attributes;
  print_token_opt  state lead_vbar "|";
  print_nsepseq    state "|" print_variant variants

and print_fun_type state {value; _} =
  let domain, arrow, range = value in
  print_type_expr state domain;
  print_token     state arrow "->";
  print_type_expr state range

and print_type_app state {value; _} =
  let type_constr, type_tuple = value in
  print_type_tuple state type_tuple;
  print_var        state type_constr

and print_type_tuple state {value; _} =
  let {lpar; inside; rpar} = value in
  print_token   state lpar "(";
  print_nsepseq state "," print_type_expr inside;
  print_token   state rpar ")"

and print_type_par state {value; _} =
  let {lpar; inside=t; rpar} = value in
  print_token     state lpar "(";
  print_type_expr state t;
  print_token     state rpar ")"

and print_projection state {value; _} =
  let {struct_name; selector; field_path} = value in
  print_var     state struct_name;
  print_token   state selector ".";
  print_nsepseq state "." print_selection field_path

and print_module_access : type a.(state -> a -> unit ) -> state -> a module_access reg -> unit =
fun f state {value; _} ->
  let {module_name; selector; field} = value in
  print_var     state module_name;
  print_token   state selector ".";
  f             state field;

and print_update state {value; _} =
 let {lbrace; record; kwd_with; updates; rbrace} = value in
 print_token state lbrace "{";
 print_path   state record;
 print_token state kwd_with "with";
 print_ne_injection state print_field_path_assign updates;
 print_token state rbrace "}"

and print_path state = function
  Name var  -> print_var        state var
| Path path -> print_projection state path

and print_selection state = function
  FieldName id -> print_var state id
| Component c  -> print_int state c

and print_cartesian state Region.{value;_} =
  print_nsepseq state "*" print_type_expr value

and print_variant state {value; _} =
  let {constr; arg; attributes=attr} = value in
  print_attributes state attr;
  print_constr state constr;
  match arg with
    None -> ()
  | Some (kwd_of, t_expr) ->
      print_token     state kwd_of "of";
      print_type_expr state t_expr

and print_field_decl state {value; _} =
  let {field_name; colon; field_type; attributes} = value
  in print_attributes state attributes;
     print_var        state field_name;
     print_token      state colon ":";
     print_type_expr  state field_type

and print_injection :
  'a.state -> (state -> 'a -> unit) -> 'a injection reg -> unit =
  fun state print {value; _} ->
    let {compound; elements; terminator} = value in
    print_open_compound  state compound;
    print_sepseq         state ";" print elements;
    print_terminator     state terminator;
    print_close_compound state compound

and print_ne_injection :
  'a.state -> (state -> 'a -> unit) -> 'a ne_injection reg -> unit =
  fun state print {value; _} ->
    let {compound; ne_elements; terminator; attributes} = value in
    print_attributes     state attributes;
    print_open_compound  state compound;
    print_nsepseq        state ";" print ne_elements;
    print_terminator     state terminator;
    print_close_compound state compound

and print_record_type state =
  print_ne_injection state print_field_decl

and print_open_compound state = function
  None -> ()
| Some compound -> match compound with
    BeginEnd (kwd_begin,_) -> print_token state kwd_begin "begin"
  | Braces   (lbrace,_)    -> print_token state lbrace    "{"
  | Brackets (lbracket,_)  -> print_token state lbracket  "["

and print_close_compound state = function
  None -> ()
| Some compound -> match compound with
    BeginEnd (_,kwd_end)  -> print_token state kwd_end  "end"
  | Braces   (_,rbrace)   -> print_token state rbrace   "}"
  | Brackets (_,rbracket) -> print_token state rbracket "]"

and print_terminator state = function
  Some semi -> print_token state semi ";"
| None -> ()

and print_let_binding state {binders; lhs_type; eq; let_rhs} =
  let () = Utils.nseq_iter (print_pattern state) binders in
  let () =
    match lhs_type with
      None -> ()
    | Some (colon, type_expr) ->
        print_token     state colon ":";
        print_type_expr state type_expr in
  let () = print_token state eq "="
  in print_expr state let_rhs

and print_pattern state = function
  PTuple ptuple ->
    print_csv state print_pattern ptuple
| PList p ->
    print_list_pattern state p
| PVar {var; attributes} ->
    print_pvar state var;
    print_attributes state attributes
| PInt i -> print_int state i
| PNat i -> print_nat state i
| PBytes b -> print_bytes state b
| PString s -> print_string state s
| PVerbatim v -> print_verbatim state v
| PPar {value={lpar;inside=p;rpar}; _} ->
    print_token   state lpar "(";
    print_pattern state p;
    print_token   state rpar ")"
| PConstr p ->
    print_constr_pattern state p
| PRecord r ->
    print_record_pattern state r
| PTyped t ->
    print_typed_pattern state t
| PUnit p -> print_unit state p

and print_list_pattern state = function
  PListComp p -> print_injection state print_pattern p
| PCons p     -> print_raw       state p

and print_raw state {value=p1,c,p2; _} =
  print_pattern state p1;
  print_token   state c "::";
  print_pattern state p2

and print_typed_pattern state {value; _} =
  let {pattern; colon; type_expr} = value in
  print_pattern   state pattern;
  print_token     state colon ":";
  print_type_expr state type_expr

and print_record_pattern state record_pattern =
  print_ne_injection state print_field_pattern record_pattern

and print_field_pattern state {value; _} =
  let {field_name; eq; pattern} = value in
  print_var     state field_name;
  print_token   state eq "=";
  print_pattern state pattern

and print_constr_pattern state = function
  PNone p      -> print_none_pattern state p
| PSomeApp p   -> print_some_app_pattern state p
| PFalse kwd_false -> print_token state kwd_false "false"
| PTrue kwd_true -> print_token state kwd_true "true"
| PConstrApp p -> print_constr_app_pattern state p

and print_none_pattern state value =
  print_token state value "None"

and print_some_app_pattern state {value; _} =
  let c_Some, argument = value in
  print_token   state c_Some "Some";
  print_pattern state argument

and print_constr_app_pattern state node =
  let {value=constr, p_opt; _} = node in
  print_constr state constr;
  match p_opt with
    None -> ()
  | Some pattern -> print_pattern state pattern

and print_expr state = function
  ELetIn let_in       -> print_let_in      state let_in
| ETypeIn type_in     -> print_type_in     state type_in
| EModIn mod_in       -> print_mod_in      state mod_in
| EModAlias mod_alias -> print_mod_alias   state mod_alias
| ECond cond          -> print_conditional state cond
| ETuple tuple        -> print_csv         state print_expr tuple
| ECase case          -> print_match_expr  state case
| EFun e              -> print_fun_expr    state e
| EAnnot e            -> print_annot_expr  state e
| ELogic e            -> print_logic_expr  state e
| EArith e            -> print_arith_expr  state e
| EString e           -> print_string_expr state e
| ECall e             -> print_fun_call    state e
| EVar v              -> print_var         state v
| EProj p             -> print_projection  state p
| EModA ma            -> print_module_access print_expr state ma
| EUpdate u           -> print_update      state u
| EUnit e             -> print_unit        state e
| EBytes b            -> print_bytes       state b
| EPar e              -> print_expr_par    state e
| EList e             -> print_list_expr   state e
| ESeq seq            -> print_sequence    state seq
| ERecord e           -> print_record_expr state e
| EConstr e           -> print_constr_expr state e
| ECodeInj e          -> print_code_inj    state e

and print_constr_expr state = function
  ENone e      -> print_none_expr       state e
| ESomeApp e   -> print_some_app_expr   state e
| EConstrApp e -> print_constr_app_expr state e

and print_none_expr state value = print_token state value "None"

and print_some_app_expr state {value; _} =
  let c_Some, argument = value in
  print_token state c_Some "Some";
  print_expr  state argument

and print_constr_app_expr state {value; _} =
  let constr, argument = value in
  print_constr state constr;
  match argument with
    None -> ()
  | Some arg -> print_expr state arg

and print_expr_par state {value; _} =
  let {lpar;inside=e;rpar} = value in
  print_token state lpar "(";
  print_expr  state e;
  print_token state rpar ")"

and print_unit state {value=lpar,rpar; _} =
  print_token state lpar "(";
  print_token state rpar ")"

and print_fun_call state {value=f,l; _} =
  print_expr state f;
  Utils.nseq_iter (print_expr state) l

and print_annot_expr state {value; _} =
  let {lpar; inside=e,colon,t; rpar} = value in
  print_token state lpar "(";
  print_expr  state e;
  print_token state colon ":";
  print_type_expr state t;
  print_token state rpar ")"

and print_list_expr state = function
  ECons {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "::";
    print_expr  state arg2
| EListComp e ->
   if e.value.elements = None
   then print_token state e.region "[]"
   else print_injection state print_expr e
(*
| Append {value=e1,append,e2; _} ->
    print_expr  state e1;
    print_token state append "@";
    print_expr  state e2
*)

and print_arith_expr state = function
  Add {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "+";
    print_expr  state arg2
| Sub {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "-";
    print_expr  state arg2
| Mult {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "*";
    print_expr  state arg2
| Div {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "/";
    print_expr  state arg2
| Mod {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "mod";
    print_expr  state arg2
| Land {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "land";
    print_expr  state arg2
| Lor {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "lor";
    print_expr  state arg2
| Lxor {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "lxor";
    print_expr  state arg2
| Lsl {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "lsl";
    print_expr  state arg2
| Lsr {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "lsr";
    print_expr  state arg2
| Neg {value={op;arg}; _} ->
    print_token state op "-";
    print_expr  state arg
| Int {region; value=lex,z} ->
    let line = sprintf "Int %s (%s)" lex (Z.to_string z)
    in print_token state region line
| Mutez {region; value=lex,z} ->
    let line = sprintf "Mutez %s (%s)" lex (Z.to_string z)
    in print_token state region line
| Nat {region; value=lex,z} ->
    let line = sprintf "Nat %s (%s)" lex (Z.to_string z)
    in print_token state region line

and print_string_expr state = function
  Cat {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "^";
    print_expr  state arg2
| String s ->
    print_string state s
| Verbatim v ->
    print_verbatim state v

and print_logic_expr state = function
  BoolExpr e -> print_bool_expr state e
| CompExpr e -> print_comp_expr state e

and print_bool_expr state = function
  Or {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "||";
    print_expr  state arg2
| And {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "&&";
    print_expr  state arg2
| Not {value={op;arg}; _} ->
    print_token state op "not";
    print_expr  state arg
| True kwd_true ->
    print_token state kwd_true "true"
| False kwd_false ->
    print_token state kwd_false "false"

and print_comp_expr state = function
  Lt {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "<";
    print_expr  state arg2
| Leq {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "<=";
    print_expr  state arg2
| Gt {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op ">";
    print_expr  state arg2
| Geq {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op ">=";
    print_expr  state arg2
| Neq {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "<>";
    print_expr  state arg2
| Equal {value={arg1;op;arg2}; _} ->
    print_expr  state arg1;
    print_token state op "=";
    print_expr  state arg2

and print_record_expr state e =
  print_ne_injection state print_field_assign e

and print_code_inj state {value; _} =
  let {language; code; rbracket} = value in
  let {value=lang; region} = language in
  let header_stop = region#start#shift_bytes 1 in
  let header_reg  = Region.make ~start:region#start ~stop:header_stop in
  print_token  state header_reg "[%";
  print_string state lang;
  print_expr   state code;
  print_token  state rbracket "]"

and print_field_assign state {value; _} =
  let {field_name; assignment; field_expr} = value in
  print_var   state field_name;
  print_token state assignment "=";
  print_expr  state field_expr

and print_field_path_assign state {value; _} =
  let {field_path; assignment; field_expr} = value in
  print_path  state field_path;
  print_token state assignment "=";
  print_expr  state field_expr

and print_sequence state seq =
  print_injection state print_expr seq

and print_match_expr state {value; _} =
  let {kwd_match; expr; kwd_with; lead_vbar; cases} = value in
  print_token     state kwd_match "match";
  print_expr      state expr;
  print_token     state kwd_with "with";
  print_token_opt state lead_vbar "|";
  print_cases     state cases

and print_token_opt state = function
         None -> fun _ -> ()
| Some region -> print_token state region

and print_cases state {value; _} =
  print_nsepseq state "|" print_case_clause value

and print_case_clause state {value; _} =
  let {pattern; arrow; rhs} = value in
  print_pattern state pattern;
  print_token   state arrow "->";
  print_expr    state rhs

and print_let_in state {value; _} =
  let {kwd_let; kwd_rec; binding; kwd_in; body; attributes} = value in
  print_attributes   state attributes;
  print_token        state kwd_let "let";
  print_token_opt    state kwd_rec "rec";
  print_let_binding  state binding;
  print_token        state kwd_in "in";
  print_expr         state body

and print_type_in state {value; _} =
  let {type_decl; kwd_in; body} = value in
  let {kwd_type; name; eq; type_expr} = type_decl in
  print_token        state kwd_type "type";
  print_var          state name;
  print_token        state eq     "eq";
  print_type_expr    state type_expr;
  print_token        state kwd_in "in";
  print_expr         state body

and print_mod_in state {value; _} =
  let {mod_decl; kwd_in; body} = value in
  let {kwd_module; name; eq; kwd_struct; module_; kwd_end} = mod_decl in
  print_token        state kwd_module "module";
  print_var          state name;
  print_token        state eq     "eq";
  print_token        state kwd_struct "struct";
  print_tokens       state module_;
  print_token        state kwd_end "end";
  print_token        state kwd_in "in";
  print_expr         state body

and print_mod_alias state {value; _} =
  let {mod_alias; kwd_in; body} = value in
  let {kwd_module; alias; eq; binders} = mod_alias in
  print_token        state kwd_module "module";
  print_var          state alias;
  print_token        state eq     "eq";
  print_nsepseq      state "." print_var binders;
  print_token        state kwd_in "in";
  print_expr         state body

and print_fun_expr state {value; _} =
  let {kwd_fun; binders; lhs_type; arrow; body} = value in
  let () = print_token state kwd_fun "fun" in
  let () = Utils.nseq_iter (print_pattern state) binders in
  let () =
    match lhs_type with
      None -> ()
    | Some (colon, type_expr) ->
        print_token     state colon ":";
        print_type_expr state type_expr in
  let () =
    print_token state arrow "->"
  in print_expr state body

and print_conditional state {value; _} =
  let {kwd_if; test; kwd_then; ifso; ifnot} = value in
  print_token  state ghost "(";
  print_token  state kwd_if "if";
  print_expr   state test;
  print_token  state kwd_then "then";
  print_expr   state ifso;
  print_option state
    (fun state (kwd_else,ifnot) ->
      print_token state kwd_else "else";
      print_expr  state ifnot) ifnot;
  print_token state ghost ")"

(* Conversion to string *)

let to_string ~offsets ~mode printer node =
  let buffer = Buffer.create 131 in
  let state = mk_state ~offsets ~mode ~buffer in
  let () = printer state node
  in Buffer.contents buffer

let tokens_to_string ~offsets ~mode =
  to_string ~offsets ~mode print_tokens
let pattern_to_string ~offsets ~mode =
  to_string ~offsets ~mode print_pattern
let expr_to_string ~offsets ~mode =
  to_string ~offsets ~mode print_expr
let type_expr_to_string ~offsets ~mode =
  to_string ~offsets ~mode print_type_expr

(* Pretty-printing the CST*)

let pp_ident state {value=name; region} =
  let reg  = compact state region in
  let node = sprintf "%s%s (%s)\n" state#pad_path name reg
  in Buffer.add_string state#buffer node

let pp_node state name =
  let node = sprintf "%s%s\n" state#pad_path name
  in Buffer.add_string state#buffer node

let pp_string state {value=name; region} =
  let reg  = compact state region in
  let node = sprintf "%s%S (%s)\n" state#pad_path name reg
  in Buffer.add_string state#buffer node

let pp_verbatim state {value=name; region} =
  let reg  = compact state region in
  let node = sprintf "%s{|%s|} (%s)\n" state#pad_path name reg
  in Buffer.add_string state#buffer node

let pp_markup_item state c = 
  let comment = match c with 
    LineCom (c, _) -> sprintf "//%s" c.value
  | BlockCom (c, _) -> sprintf "(*%s*)" c.value
  in
  Buffer.add_string state#buffer comment

let pp_markup state comments = 
  List.iter (pp_markup_item state) comments

let pp_loc_node state name region =
  pp_markup state region#markup;
  pp_ident state {value=name; region}

let rec pp_cst state {decl; _} =
  let apply len rank =
    pp_declaration (state#pad len rank) in
  let decls = Utils.nseq_to_list decl in
  pp_node state "<ast>";
  List.iteri (List.length decls |> apply) decls

and pp_declaration state = function
  Let {value = (kwd_let, kwd_rec, let_binding, attr); region} ->
    pp_markup state kwd_let#markup;
    pp_loc_node state "Let" region;
    (if kwd_rec <> None then pp_node (state#pad 0 0) "rec"); (* Hack *)
    pp_let_binding state let_binding attr
| TypeDecl {value; region} ->
    pp_loc_node  state "TypeDecl" region;
    pp_type_decl state value
| ModuleDecl {value; region} ->
    pp_loc_node    state "ModuleDecl" region;
    pp_module_decl state value
| ModuleAlias {value; region} ->
    pp_loc_node    state "ModuleDecl" region;
    pp_module_alias state value
| Directive dir ->
    let region, string = Directive.project dir in
    pp_loc_node state "Directive" region;
    pp_node state string

and pp_let_binding state node attr =
  let {binders; lhs_type; let_rhs; _} = node in
  let arity = if lhs_type = None then 2 else 3 in
  let arity = if attr = [] then arity else arity+1 in
  let rank =
    let state = state#pad arity 0 in
    pp_node    state "<binders>";
    pp_binders state binders; 0 in
  let rank =
    match lhs_type with
      None -> rank
    | Some (_, type_expr) ->
       let state = state#pad arity (rank+1) in
       pp_node state "<lhs type>";
       pp_type_expr (state#pad 1 0) type_expr;
       rank+1 in
  let rank =
    let state = state#pad arity (rank+1) in
    pp_node state "<rhs>";
    pp_expr (state#pad 1 0) let_rhs;
    rank+1 in
  let () =
    if attr <> [] then
      let state = state#pad arity (rank+1) in
      pp_node state "<attributes>";
      let length         = List.length attr in
      let apply len rank = pp_ident (state#pad len rank)
      in List.iteri (apply length) attr
  in ()

and pp_type_decl state decl =
  pp_ident     (state#pad 2 0) decl.name;
  pp_type_expr (state#pad 2 1) decl.type_expr

and pp_module_decl state decl =
  pp_ident     (state#pad 2 0) decl.name;
  pp_cst       (state#pad 2 1) decl.module_

and pp_module_alias state decl =
  let binders     = Utils.nsepseq_to_list decl.binders in
  let len            = List.length binders in
  let apply len rank = pp_ident (state#pad len rank) in
  pp_ident (state#pad (1+len) 0) decl.alias;
  List.iteri (apply len) binders

and pp_binders state patterns =
  let patterns       = Utils.nseq_to_list patterns in
  let arity          = List.length patterns in
  let apply len rank = pp_pattern (state#pad len rank)
  in List.iteri (apply arity) patterns

and pp_pattern state = function
  PConstr p ->
    pp_node state "PConstr";
    pp_constr_pattern (state#pad 1 0) p
| PVar {var;attributes} ->
   pp_node state "PVar";
   let arity = if attributes = [] then 1 else 2 in
   pp_ident (state#pad 1 0) var;
   if attributes <> [] then
     pp_attributes (state#pad arity 1) attributes
| PInt i ->
    pp_node state "PInt";
    pp_int  state i
| PNat n ->
    pp_node state "PNat";
    pp_int  state n
| PBytes b ->
    pp_node  state "PBytes";
    pp_bytes state b
| PString s ->
    pp_node   state "PString";
    pp_string (state#pad 1 0) s
| PVerbatim v ->
    pp_node   state "PVerbatim";
    pp_verbatim (state#pad 1 0) v
| PUnit {region; _} ->
    pp_loc_node state "PUnit" region
| PList plist ->
    pp_node state "PList";
    pp_list_pattern (state#pad 1 0) plist
| PTuple t ->
    pp_loc_node state "PTuple" t.region;
    pp_tuple_pattern (state#pad 1 0) t.value
| PPar {value; _} ->
    pp_node state "PPar";
    pp_pattern (state#pad 1 0) value.inside
| PRecord {value; _} ->
    pp_node state "PRecord";
    pp_ne_injection pp_field_pattern state value
| PTyped {value; _} ->
    pp_node state "PTyped";
    pp_typed_pattern state value

and pp_field_pattern state {value; _} =
  pp_node    state value.field_name.value;
  pp_pattern (state#pad 1 0) value.pattern

and pp_typed_pattern state node =
  pp_pattern   (state#pad 2 0) node.pattern;
  pp_type_expr (state#pad 2 1) node.type_expr

and pp_tuple_pattern state tuple =
  let patterns       = Utils.nsepseq_to_list tuple in
  let length         = List.length patterns in
  let apply len rank = pp_pattern (state#pad len rank)
  in List.iteri (apply length) patterns

and pp_list_pattern state = function
  PCons {value; region} ->
    let pat1, _, pat2 = value in
    pp_loc_node state "PCons" region;
    pp_pattern  (state#pad 2 0) pat1;
    pp_pattern  (state#pad 2 1) pat2
| PListComp {value; region} ->
    pp_loc_node state "PListComp" region;
    if value.elements = None
    then pp_node (state#pad 1 0) "<nil>"
    else pp_injection pp_pattern state value

and pp_injection :
  'a.(state -> 'a -> unit) -> state -> 'a injection -> unit =
  fun printer state inj ->
    let elements       = Utils.sepseq_to_list inj.elements in
    let length         = List.length elements in
    let apply len rank = printer (state#pad len rank)
    in List.iteri (apply length) elements

and pp_ne_injection :
  'a.(state -> 'a -> unit) -> state -> 'a ne_injection -> unit =
  fun printer state inj ->
    let ne_elements = Utils.nsepseq_to_list inj.ne_elements in
    let length      = List.length ne_elements in
    let arity       = if inj.attributes = [] then length else length+1
    and apply len rank = printer (state#pad len rank)
    in List.iteri (apply arity) ne_elements;
       if inj.attributes <> [] then
         let state = state#pad arity (arity-1)
         in pp_attributes state inj.attributes

and pp_record_type state = pp_ne_injection pp_field_decl state

and pp_bytes state {value=lexeme,hex; region} =
  pp_loc_node (state#pad 2 0) lexeme region;
  pp_node     (state#pad 2 1) (Hex.show hex)

and pp_int state {value=lexeme,z; region} =
  pp_loc_node (state#pad 2 0) lexeme region;
  pp_node     (state#pad 2 1) (Z.to_string z)

and pp_constr_pattern state = function
  PNone region ->
    pp_loc_node state "PNone" region
| PSomeApp {value=_,param; region} ->
    pp_loc_node state "PSomeApp" region;
    pp_pattern  (state#pad 1 0) param
| PFalse region ->
    pp_loc_node state "PFalse" region
| PTrue region ->
    pp_loc_node state "PTrue" region
| PConstrApp {value; region} ->
    pp_loc_node state "PConstrApp" region;
    pp_constr_app_pattern (state#pad 1 0) value

and pp_constr_app_pattern state (constr, pat_opt) =
  pp_ident state constr;
  match pat_opt with
    None -> ()
  | Some pat -> pp_pattern state pat

and pp_expr state = function
  ECase {value; region} ->
    pp_loc_node state "ECase" region;
    pp_case pp_expr state value
| ECond {value; region} ->
    pp_loc_node state "ECond" region;
    pp_cond_expr state value
| EAnnot {value; region} ->
    pp_loc_node  state "EAnnot" region;
    pp_annotated state value
| ELogic e_logic ->
    pp_node state "ELogic";
    pp_e_logic (state#pad 1 0) e_logic
| EArith e_arith ->
    pp_node state "EArith";
    pp_arith_expr (state#pad 1 0) e_arith
| EString e_string ->
    pp_node state "EString";
    pp_string_expr (state#pad 1 0) e_string
| EList e_list ->
    pp_node state "EList";
    pp_list_expr (state#pad 1 0) e_list
| EConstr e_constr ->
    pp_node state "EConstr";
    pp_constr_expr (state#pad 1 0) e_constr
| ERecord {value; region} ->
    pp_loc_node state "ERecord" region;
    pp_ne_injection pp_field_assign state value
| EProj {value; region} ->
    pp_loc_node state "EProj" region;
    pp_projection state value
| EModA {value; region} ->
    pp_loc_node state "EModA" region;
    pp_module_access pp_expr state value
| EUpdate {value; region} ->
    pp_loc_node state "EUpdate" region;
    pp_update state value
| EVar v ->
    pp_node  state "EVar";
    pp_ident (state#pad 1 0) v
| ECall {value; region} ->
    pp_loc_node state "ECall" region;
    pp_fun_call state value
| EBytes b ->
    pp_node state "EBytes";
    pp_bytes state b
| EUnit u ->
    pp_loc_node state "EUnit" u.region
| ETuple e_tuple ->
    pp_node state "ETuple";
    pp_tuple_expr state e_tuple
| EPar {value; region} ->
    pp_loc_node state "EPar" region;
    pp_expr (state#pad 1 0) value.inside
| ELetIn {value; region} ->
    pp_loc_node state  "ELetIn" region;
    pp_let_in state value
| ETypeIn {value; region} ->
    pp_loc_node state  "ETypeIn" region;
    pp_type_in state value
| EModIn {value; region} ->
    pp_loc_node state  "EModIn" region;
    pp_mod_in state value
| EModAlias {value; region} ->
    pp_loc_node state  "EModAlias" region;
    pp_mod_alias state value
| EFun {value; region} ->
    pp_loc_node state "EFun" region;
    pp_fun_expr state value
| ESeq {value; region} ->
    pp_loc_node state "ESeq" region;
    pp_injection pp_expr state value
| ECodeInj {value; region} ->
    pp_loc_node state "ECodeInj" region;
    pp_code_inj state value

and pp_fun_expr state node =
  let {binders; lhs_type; body; _} = node in
  let arity = if lhs_type = None then 2 else 3 in
  let () =
    let state = state#pad arity 0 in
    pp_node state "<parameters>";
    pp_binders state binders in
  let () =
    match lhs_type with
      None -> ()
    | Some (_, type_expr) ->
       let state = state#pad arity 1 in
       pp_node state "<lhs type>";
       pp_type_expr (state#pad 1 0) type_expr in
  let () =
    let state = state#pad arity (arity - 1) in
    pp_node state "<body>";
    pp_expr (state#pad 1 0) body
  in ()

and pp_code_inj state rc =
  let () =
    let state = state#pad 2 0 in
    pp_node state "<language>";
    pp_string (state#pad 1 0) rc.language.value in
  let () =
    let state = state#pad 2 1 in
    pp_node state "<code>";
    pp_expr (state#pad 1 0) rc.code
  in ()

and pp_let_in state node =
  let {binding; body; attributes; kwd_rec; _} = node in
  let {binders; lhs_type; let_rhs; _} = binding in
  let arity = if lhs_type = None then 3 else 4 in
  let arity = if kwd_rec = None then arity else arity+1 in
  let arity = if attributes = [] then arity else arity+1 in
  let rank =
    match kwd_rec with
      None -> 0
    | Some (_) ->
      let state = state#pad arity 0 in
      pp_node state "rec"; 0 in
  let rank =
    let state = state#pad arity 0 in
    pp_node state "<binders>";
    pp_binders state binders; rank in
  let rank =
    match lhs_type with
      None -> rank
    | Some (_, type_expr) ->
       let state = state#pad arity (rank+1) in
       pp_node state "<lhs type>";
       pp_type_expr (state#pad 1 0) type_expr;
       rank+1 in
  let rank =
    let state = state#pad arity (rank+1) in
    pp_node state "<rhs>";
    pp_expr (state#pad 1 0) let_rhs;
    rank+1 in
  let rank =
    let state = state#pad arity (rank+1) in
    pp_node state "<body>";
    pp_expr (state#pad 1 0) body;
    rank+1 in
  let () =
    if attributes <> [] then
      let state = state#pad arity (rank+1) in
      pp_node state "<attributes>";
      let length         = List.length attributes in
      let apply len rank = pp_ident (state#pad len rank)
      in List.iteri (apply length) attributes
  in ()

and pp_type_in state node =
  let {type_decl; body; _} = node in
  let {name; type_expr; _} = type_decl in
  let () =
    let state = state#pad 3 0 in
    pp_node  state "<name>";
    pp_ident state name in
  let () =
    let state = state#pad 3 1 in
    pp_node state "<type>";
    pp_type_expr (state#pad 1 0) type_expr in
  let () =
    let state = state#pad 3 2 in
    pp_node state "<body>";
    pp_expr (state#pad 1 0) body
  in ()

and pp_mod_in state node =
  let {mod_decl; body; _} = node in
  let {name; module_; _} = mod_decl in
  let () =
    let state = state#pad 3 0 in
    pp_node state "<name>";
    pp_ident state name in
  let () =
    let state = state#pad 3 1 in
    pp_node state "<module>";
    pp_cst (state#pad 1 0) module_ in
  let () =
    let state = state#pad 3 2 in
    pp_node state "<body>";
    pp_expr (state#pad 1 0) body
  in ()

and pp_mod_alias state node =
  let {mod_alias; body; _} = node in
  let {alias;binders; _} = mod_alias in
  let () =
    let state = state#pad 3 0 in
    pp_node  state "<alias>";
    pp_ident state alias in
  let () =
    let state = state#pad 3 1 in
    let binders     = Utils.nsepseq_to_list binders in
    let len            = List.length binders in
    let apply len rank = pp_ident (state#pad len rank) in
    pp_node state "<module>";
    List.iteri (apply len) binders in
  let () =
    let state = state#pad 3 2 in
    pp_node state "<body>";
    pp_expr (state#pad 1 0) body
  in ()

and pp_attributes state attributes =
  pp_node state "<attributes>";
  let length         = List.length attributes in
  let apply len rank = pp_ident (state#pad len rank)
  in List.iteri (apply length) attributes

and pp_tuple_expr state {value; _} =
  let exprs          = Utils.nsepseq_to_list value in
  let length         = List.length exprs in
  let apply len rank = pp_expr (state#pad len rank)
  in List.iteri (apply length) exprs

and pp_fun_call state (fun_expr, args) =
  let args           = Utils.nseq_to_list args in
  let arity          = List.length args in
  let apply len rank = pp_expr (state#pad len rank)
  in pp_expr (state#pad (1+arity) 0) fun_expr;
     List.iteri (apply arity) args

and pp_projection state proj =
  let selections     = Utils.nsepseq_to_list proj.field_path in
  let len            = List.length selections in
  let apply len rank = pp_selection (state#pad len rank) in
  pp_ident (state#pad (1+len) 0) proj.struct_name;
  List.iteri (apply len) selections

and pp_module_access : type a. (state -> a -> unit ) -> state -> a module_access -> unit
= fun f state ma ->
  pp_ident (state#pad 2 0) ma.module_name;
  f (state#pad 2 1) ma.field

and pp_update state update =
  pp_path (state#pad 2 0) update.record;
  pp_ne_injection pp_field_path_assign state update.updates.value

and pp_path state = function
  Name name ->
    pp_node state "Name";
    pp_ident (state#pad 1 0) name
| Path {value; region} ->
    pp_loc_node state "Path" region;
    pp_projection state value

and pp_selection state = function
  FieldName fn ->
    pp_node state "FieldName";
    pp_ident (state#pad 1 0) fn
| Component c ->
    pp_node state "Component";
    pp_int state c

and pp_field_assign state {value; _} =
  pp_node  state  "<field assignment>";
  pp_ident (state#pad 2 0) value.field_name;
  pp_expr  (state#pad 2 1) value.field_expr

and pp_field_path_assign state {value; _} =
  let {field_path; field_expr; _} = value in
  pp_node state "<update>";
  pp_path (state#pad 2 0) field_path;
  pp_expr (state#pad 2 1) field_expr

and pp_constr_expr state = function
  ENone region ->
    pp_loc_node state "ENone" region
| ESomeApp {value=_,arg; region} ->
    pp_loc_node state "ESomeApp" region;
    pp_expr (state#pad 1 0) arg
| EConstrApp {value; region} ->
    pp_loc_node state "EConstrApp" region;
    pp_constr_app_expr state value

and pp_constr_app_expr state (constr, expr_opt) =
  match expr_opt with
    None -> pp_ident (state#pad 1 0) constr
  | Some expr ->
     pp_ident (state#pad 2 0) constr;
     pp_expr  (state#pad 2 1) expr

and pp_list_expr state = function
  ECons {value; region} ->
    pp_loc_node state "ECons" region;
    pp_expr (state#pad 2 0) value.arg1;
    pp_expr (state#pad 2 1) value.arg2
| EListComp {value; region} ->
    pp_loc_node state "EListComp" region;
    if   value.elements = None
    then pp_node (state#pad 1 0) "<nil>"
    else pp_injection pp_expr state value

and pp_string_expr state = function
  Cat {value; region} ->
    pp_loc_node state "Cat" region;
    pp_expr (state#pad 2 0) value.arg1;
    pp_expr (state#pad 2 1) value.arg2;
| String s ->
    pp_node   state "String";
    pp_string (state#pad 1 0) s
| Verbatim v ->
    pp_node   state "Verbatim";
    pp_string (state#pad 1 0) v

and pp_arith_expr state = function
  Add {value; region} ->
    pp_bin_op "Add" region state value
| Sub {value; region} ->
    pp_bin_op "Sub" region state value
| Mult {value; region} ->
    pp_bin_op "Mult" region state value
| Div {value; region} ->
    pp_bin_op "Div" region state value
| Mod {value; region} ->
    pp_bin_op "Mod" region state value
| Land {value; region} ->
    pp_bin_op "Land" region state value
| Lor {value; region} ->
    pp_bin_op "Lor" region state value
| Lxor {value; region} ->
    pp_bin_op "Lxor" region state value
| Lsl {value; region} ->
    pp_bin_op "Lsl" region state value
| Lsr {value; region} ->
    pp_bin_op "Lsr" region state value
| Neg {value; region} ->
    pp_loc_node state "Neg" region;
    pp_expr (state#pad 1 0) value.arg;
| Int i ->
    pp_node state "Int";
    pp_int  state i
| Nat n ->
    pp_node state "Nat";
    pp_int  state n
| Mutez m ->
    pp_node state "Mutez";
    pp_int  state m

and pp_e_logic state = function
  BoolExpr e ->
    pp_node state "BoolExpr";
    pp_bool_expr (state#pad 1 0) e
| CompExpr e ->
    pp_node state "CompExpr";
    pp_comp_expr (state#pad 1 0) e

and pp_bool_expr state = function
  Or {value; region} ->
    pp_bin_op "Or" region state value
| And {value; region} ->
    pp_bin_op "And" region state value
| Not {value; _} ->
    pp_node state "Not";
    pp_expr (state#pad 1 0) value.arg
| False region ->
    pp_loc_node state "False" region
| True region ->
    pp_loc_node state "True" region

and pp_comp_expr state = function
  Lt {value; region} ->
    pp_bin_op "Lt" region state value
| Leq {value; region} ->
    pp_bin_op "Leq" region state value
| Gt {value; region} ->
    pp_bin_op "Gt" region state value
| Geq {value; region} ->
    pp_bin_op "Geq" region state value
| Equal {value; region} ->
    pp_bin_op "Equal" region state value
| Neq {value; region} ->
    pp_bin_op "Neq" region state value

and pp_bin_op node region state op =
  pp_loc_node state node region;
  pp_expr (state#pad 2 0) op.arg1;
  pp_expr (state#pad 2 1) op.arg2

and pp_annotated state annot =
  let expr, _, t_expr = annot.inside in
  pp_expr      (state#pad 2 0) expr;
  pp_type_expr (state#pad 2 1) t_expr

and pp_cond_expr state (cond: cond_expr) =
  let arity = if cond.ifnot = None then 2 else 3 in
  let () =
    let state = state#pad arity 0 in
    pp_node state "<condition>";
    pp_expr (state#pad 1 0) cond.test in
  let () =
    let state = state#pad arity 1 in
    pp_node state "<true>";
    pp_expr (state#pad 1 0) cond.ifso in
  let () = match cond.ifnot with
    Some (_, ifnot) ->
      let state = state#pad arity 2 in
      pp_node state "<false>";
      pp_expr (state#pad 1 0) ifnot
  | None -> ()
  in ()

and pp_case :
  'a.(state -> 'a -> unit) -> state -> 'a case -> unit =
  fun printer state case ->
  let clauses = Utils.nsepseq_to_list case.cases.value in
  let clauses = List.map (fun x -> x.value) clauses in
  let arity  = List.length clauses + 1 in
  let apply len rank =
    pp_case_clause printer (state#pad len (rank+1))
  in pp_expr (state#pad arity 0) case.expr;
     List.iteri (apply arity) clauses

and pp_case_clause :
  'a.(state -> 'a -> unit) -> state -> 'a case_clause -> unit =
  fun printer state clause ->
  pp_node    state "<clause>";
  pp_pattern (state#pad 2 0) clause.pattern;
  printer    (state#pad 2 1) clause.rhs

and pp_type_expr state = function
  TProd {value; region} ->
    pp_loc_node state "TProd" region;
    pp_cartesian state value
| TSum {value; region} ->
    pp_loc_node state "TSum" region;
    pp_sum_type state value
| TRecord {value; region} ->
    pp_loc_node    state "TRecord" region;
    pp_record_type state value
| TApp {value=name,tuple; region} ->
    pp_loc_node   state "TApp" region;
    pp_ident      (state#pad 2 0) name;
    pp_type_tuple (state#pad 2 1) tuple
| TFun {value; region} ->
    pp_loc_node state "TFun" region;
    let apply len rank =
      pp_type_expr (state#pad len rank) in
    let domain, _, range = value in
    List.iteri (apply 2) [domain; range]
| TPar {value={inside;_}; region} ->
    pp_loc_node  state "TPar" region;
    pp_type_expr (state#pad 1 0) inside
| TVar v ->
    pp_node  state "TVar";
    pp_ident (state#pad 1 0) v
| TWild wild ->
    pp_node  state "TWild";
    pp_loc_node state "TWild" wild
| TString s ->
    pp_node   state "TString";
    pp_string (state#pad 1 0) s
| TInt s ->
    pp_node   state "TInt";
    pp_int (state#pad 1 0) s
| TModA {value; region} ->
    pp_loc_node state "TModA" region;
    pp_module_access pp_type_expr state value


and pp_sum_type state {variants; attributes; _} =
  let variants = Utils.nsepseq_to_list variants in
  let arity    = List.length variants in
  let arity    = if attributes = [] then arity else arity+1 in
  let apply arity rank variant =
    let state = state#pad arity rank in
    pp_variant state variant.value in
  let () = List.iteri (apply arity) variants in
  if attributes <> [] then
    let state = state#pad arity (arity-1)
    in pp_attributes state attributes

and pp_type_tuple state {value; _} =
  let components     = Utils.nsepseq_to_list value.inside in
  let apply len rank = pp_type_expr (state#pad len rank)
  in List.iteri (List.length components |> apply) components

and pp_field_decl state {value; _} =
  let arity = if value.attributes = [] then 1 else 2 in
  pp_ident     state value.field_name;
  pp_type_expr (state#pad arity 0) value.field_type;
  if value.attributes <> [] then
    pp_attributes (state#pad arity 1) value.attributes

and pp_cartesian state t_exprs =
  let t_exprs        = Utils.nsepseq_to_list t_exprs in
  let arity          = List.length t_exprs in
  let apply len rank = pp_type_expr (state#pad len rank)
  in List.iteri (apply arity) t_exprs

and pp_variant state {constr; arg; attributes=attr} =
  let arity = if attr = [] then 0 else 1 in
  let arity = if arg = None then arity else arity + 1 in
  let rank  = 0 in
  let () = pp_ident state constr in
  let rank =
    match arg with
      None -> rank
    | Some (_,c) ->
        pp_type_expr (state#pad arity rank) c; rank+1 in
  let () = if attr <> [] then
             pp_attributes (state#pad arity rank) attr
  in ()
