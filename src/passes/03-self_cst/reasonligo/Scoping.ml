[@@@warning "-42"]

(* Dependencies *)

module Region = Simple_utils.Region
module CST    = Cst.Reasonligo

open Region
open Errors
open Trace

(* TODO don't *)
let ignore x =
  let _ = x in
  ()

(* Useful modules *)

module SSet = Set.Make (String)

module Ord =
  struct
    type t = CST.variable
    let compare v1 v2 =
      String.compare v1.value v2.value
  end

module VarSet = Set.Make (Ord)

(* Checking the definition of reserved names (shadowing) *)

let reserved =
  let open SSet in
  empty
  |> add "abs"
  |> add "address"
  |> add "amount"
  |> add "assert"
  |> add "balance"
  |> add "black2b"
  |> add "check"
  |> add "continue"
  |> add "failwith"
  |> add "gas"
  |> add "hash"
  |> add "hash_key"
  |> add "implicit_account"
  |> add "int"
  |> add "pack"
  |> add "self_address"
  |> add "sender"
  |> add "sha256"
  |> add "sha512"
  |> add "source"
  |> add "stop"
  |> add "time"
  |> add "unit"
  |> add "unpack"

let check_reserved_names ~raise vars =
  let is_reserved elt = SSet.mem elt.value reserved in
  let inter = VarSet.filter is_reserved vars in
  if not (VarSet.is_empty inter) then
    let clash = VarSet.choose inter in
    raise.raise @@ reserved_name clash
  else vars

let check_reserved_name ~raise var =
  if SSet.mem var.value reserved then
    raise.raise @@ reserved_name var
  else ()

let is_wildcard var =
  let var = var.value in
  String.compare var Var.wildcard = 0

(* Checking the linearity of patterns *)

open! CST

let rec vars_of_pattern ~raise env = function
  PConstr p -> vars_of_pconstr ~raise env p
| PUnit _
| PInt _ | PNat _ | PBytes _
| PString _ | PVerbatim _ -> env
| PVar {var} when is_wildcard var -> env
| PVar {var} ->
    if VarSet.mem var env then
      raise.raise @@ non_linear_pattern var
    else VarSet.add var env
| PList l -> vars_of_plist ~raise env l
| PTuple t -> Helpers.fold_npseq (vars_of_pattern ~raise) env t.value
| PPar p -> vars_of_pattern ~raise env p.value.inside
| PRecord p -> vars_of_fields ~raise env p.value.ne_elements
| PTyped p -> vars_of_pattern ~raise env p.value.pattern

and vars_of_fields ~raise env fields =
  Helpers.fold_npseq (vars_of_field_pattern ~raise) env fields

and vars_of_field_pattern ~raise env field =
  let var = field.value.field_name in
  if VarSet.mem var env then
    raise.raise @@ non_linear_pattern var
  else
    let p = field.value.pattern
    in vars_of_pattern ~raise (VarSet.add var env) p

and vars_of_pconstr ~raise env = function
  PNone _ -> env
| PSomeApp {value=_, pattern; _} ->
    vars_of_pattern ~raise env pattern
| PFalse _ | PTrue _ -> env
| PConstrApp {value=_, Some pattern; _} ->
    vars_of_pattern ~raise env pattern
| PConstrApp {value=_,None; _} -> env

and vars_of_plist ~raise env = function
  PListComp {value; _} ->
    Helpers.bind_fold_pseq (vars_of_pattern ~raise) env value.elements
| PCons {value; _} ->
    let {lpattern;rpattern;_} = value in
    List.fold ~f:(vars_of_pattern ~raise) ~init:env [lpattern; rpattern]

let check_linearity ~raise = vars_of_pattern ~raise VarSet.empty

(* Checking patterns *)

let check_pattern ~raise p =
  check_linearity ~raise p |> check_reserved_names ~raise |> ignore

(* Checking variants for duplicates *)

let check_variants ~raise variants =
  let add acc {value; _} =
    if VarSet.mem value.constr acc then
      raise.raise @@ duplicate_variant value.constr
    else VarSet.add value.constr acc in
  let variants =
    List.fold ~f:add ~init:VarSet.empty variants
  in ignore variants

(* Checking record fields *)

let check_fields ~raise fields =
  let add acc {value; _} =
    let field_name = (value: field_decl).field_name in
    if VarSet.mem field_name acc then
      raise.raise @@ duplicate_field_name value.field_name
    else
      VarSet.add value.field_name acc
  in ignore (List.fold ~f:add ~init:VarSet.empty fields)

let peephole_type ~raise : unit -> type_expr -> unit = fun _ t ->
  match t with
    TProd   {value=_;region=_} -> ()
  | TSum    {value;region=_} ->
    let () = Utils.nsepseq_to_list value.variants |> check_variants ~raise in
    ()
  | TRecord {value;region=_} ->
    let () = Utils.nsepseq_to_list value.ne_elements |> check_fields ~raise in
    ()
  | TApp    {value=_;region=_} -> ()
  | TFun    {value=_;region=_} -> ()
  | TPar    {value=_;region=_} -> ()
  | TModA   {value=_;region=_} -> ()
  | TVar    {value=_;region=_} -> ()
  | TWild   _                  -> ()
  | TString {value=_;region=_} -> ()
  | TInt    {value=_;region=_} -> ()


let peephole_expression ~raise : unit -> expr -> unit = fun () e ->
  match e with
    ECase    {value;region=_}   ->
    let () =
      List.iter
        ~f:(fun ({value;region=_}: _ case_clause reg) ->
           check_pattern ~raise value.pattern)
        (Utils.nsepseq_to_list value.cases.value) in
    ()
  | ECond    {value=_;region=_} -> ()
  | EAnnot   {value=_;region=_} -> ()
  | ELogic   _                  -> ()
  | EArith   _                  -> ()
  | EString  _                  -> ()
  | EList    _                  -> ()
  | EConstr  _                  -> ()
  | ERecord  {value=_;region=_} -> ()
  | EProj    {value=_;region=_} -> ()
  | EUpdate  {value=_;region=_} -> ()
  | EModA   {value=_;region=_} -> ()
  | EVar     {value=_;region=_} -> ()
  | ECall    {value=_;region=_} -> ()
  | EBytes   {value=_;region=_} -> ()
  | EUnit    {value=_;region=_} -> ()
  | ETuple   {value=_;region=_} -> ()
  | EPar     {value=_;region=_} -> ()
  | ELetIn   {value;region=_}   ->
    let () = check_pattern ~raise value.binding.binders in
    ()
  | ETypeIn   {value;region=_}   ->
    let () = check_reserved_name ~raise value.type_decl.name in
    ()
  | EModIn   {value;region=_}   ->
    let () = check_reserved_name ~raise value.mod_decl.name in
    ()
  | EModAlias {value;region=_}   ->
    let () = check_reserved_name ~raise value.mod_alias.alias in
    ()
  | EFun     {value=_;region=_} -> ()
  | ESeq     {value=_;region=_} -> ()
  | ECodeInj {value=_;region=_} -> ()

let peephole_declaration ~raise : unit -> declaration -> unit =
  fun _ d ->
  match d with
    ConstDecl  {value;region=_} ->
    let (_,_,binding,_) = value in
    let () = check_pattern ~raise binding.binders in
    ()
  | TypeDecl {value;region=_} ->
    let () = check_reserved_name ~raise value.name in
    ()
  | ModuleDecl {value;region=_} ->
    let () = check_reserved_name ~raise value.name in
    ()
  | ModuleAlias {value;region=_} ->
    let () = check_reserved_name ~raise value.alias in
    ()
  | Directive _ -> ()

let peephole ~raise : (unit,'err) Helpers.folder = {
  t = peephole_type ~raise;
  e = peephole_expression ~raise;
  d = peephole_declaration ~raise;
}
