open Errors
open Ast_typed
open Trace

let field_checks kvl loc =
  let%bind () = Assert.assert_true
    (too_small_record loc)
    (List.length kvl >=2) in
  let all_undefined = List.for_all (fun (_,{decl_pos;_}) -> decl_pos = 0) kvl in
  let%bind () = Assert.assert_true
    (declaration_order_record loc)
    (not all_undefined) in
  ok ()

let annotate_field (field:row_element) (ann:string) : row_element =
  {field with michelson_annotation=Some ann}


let comb_pair (t:type_content) : row_element =
  let associated_type = {
    type_content = t ;
    type_meta = None ;
    location = Location.generated ; } in
  {associated_type ; michelson_annotation = Some "" ; decl_pos = 0}

let comb_ctor (t:type_content) : row_element =
  let associated_type = {
    type_content = t ;
    type_meta = None ;
    location = Location.generated ; } in
  {associated_type ; michelson_annotation = Some "" ; decl_pos = 0}

let rec to_right_comb_pair l new_map =
  match l with
  | [] -> new_map
  | [ (Label ann_l, row_element_l) ; (Label ann_r, row_element_r) ] ->
    LMap.add_bindings [
      (Label "0" , annotate_field row_element_l ann_l) ;
      (Label "1" , annotate_field row_element_r ann_r) ] new_map
  | (Label ann, field)::tl ->
    let new_map' = LMap.add (Label "0") (annotate_field field ann) new_map in
    LMap.add (Label "1") (comb_pair (T_record (to_right_comb_pair tl new_map'))) new_map'

let rec to_right_comb_variant l new_map =
  match l with
  | [] -> new_map
  | [ (Label ann_l, row_element_l) ; (Label ann_r, row_element_r) ] ->
    LMap.add_bindings [
      (Label "M_left"  , annotate_field row_element_l ann_l) ;
      (Label "M_right" , annotate_field row_element_r ann_r) ] new_map
  | (Label ann, field)::tl ->
    let new_map' = LMap.add (Label "M_left") (annotate_field field ann) new_map in
    LMap.add (Label "M_right") (comb_ctor (T_sum (to_right_comb_variant tl new_map'))) new_map'

let rec to_left_comb_pair' first l new_map =
  match l with
  | [] -> new_map
  | (Label ann_l, row_element_l) :: (Label ann_r, row_element_r) ::tl when first ->
    let new_map' = LMap.add_bindings [
      (Label "0" , annotate_field row_element_l ann_l) ;
      (Label "1" , annotate_field row_element_r ann_r) ] LMap.empty in
    to_left_comb_pair' false tl new_map'
  | (Label ann, field)::tl ->
    let new_map' = LMap.add_bindings [
      (Label "0" , comb_pair (T_record new_map)) ;
      (Label "1" , annotate_field field ann ) ;] LMap.empty in
    to_left_comb_pair' first tl new_map'
let to_left_comb_pair = to_left_comb_pair' true

let rec to_left_comb_variant' first l new_map =
  match l with
  | [] -> new_map
  | (Label ann_l, row_element_l) :: (Label ann_r, row_element_r) ::tl when first ->
    let new_map' = LMap.add_bindings [
      (Label "M_left"  , annotate_field row_element_l ann_l) ;
      (Label "M_right" , annotate_field row_element_r ann_r) ] LMap.empty in
    to_left_comb_variant' false tl new_map'
  | (Label ann, ctor)::tl ->
    let new_map' = LMap.add_bindings [
      (Label "M_left"  , comb_ctor (T_sum new_map)) ;
      (Label "M_right" , annotate_field ctor ann ) ;] LMap.empty in
    to_left_comb_variant' first tl new_map'
let to_left_comb_variant = to_left_comb_variant' true

let rec from_right_comb_pair (l:row_element label_map) (size:int) : (row_element list , typer_error) result =
  let l' = List.rev @@ LMap.to_kv_list l in
  match l' , size with
  | [ (_,l) ; (_,r) ] , 2 -> ok [ l ; r ]
  | [ (_,l) ; (_,{associated_type=tr;_}) ], _ ->
    let%bind comb_lmap = trace_option (expected_record tr) @@ get_t_record tr in
    let%bind next = from_right_comb_pair comb_lmap (size-1) in
    ok (l :: next)
  | _ -> fail (corner_case "Could not convert michelson_pair_right_comb pair to a record")

let rec from_left_comb_pair (l:row_element label_map) (size:int) : (row_element list , typer_error) result =
  let l' = List.rev @@ LMap.to_kv_list l in
  match l' , size with
  | [ (_,l) ; (_,r) ] , 2 -> ok [ l ; r ]
  | [ (_,{associated_type=tl;_}) ; (_,r) ], _ ->
    let%bind comb_lmap = trace_option (expected_record tl) @@ get_t_record tl in
    let%bind next = from_left_comb_pair comb_lmap (size-1) in
    ok (List.append next [r])
  | _ -> fail (corner_case "Could not convert michelson_pair_left_comb pair to a record")

let rec from_right_comb_variant (l:row_element label_map) (size:int) : (row_element list , typer_error) result =
  let l' = List.rev @@ LMap.to_kv_list l in
  match l' , size with
  | [ (_,l) ; (_,r) ] , 2 -> ok [ l ; r ]
  | [ (_,l) ; (_,{associated_type=tr;_}) ], _ ->
    let%bind comb_cmap = trace_option (expected_variant tr) @@ get_t_sum tr in
    let%bind next = from_right_comb_variant comb_cmap (size-1) in
    ok (l :: next)
  | _ -> fail (corner_case "Could not convert michelson_or right comb to a variant")

let rec from_left_comb_variant (l:row_element label_map) (size:int) : (row_element list , typer_error) result =
  let l' = List.rev @@ LMap.to_kv_list l in
  match l' , size with
  | [ (_,l) ; (_,r) ] , 2 -> ok [ l ; r ]
  | [ (_,{associated_type=tl;_}) ; (_,r) ], _ ->
    let%bind comb_cmap = trace_option (expected_variant tl) @@ get_t_sum tl in
    let%bind next = from_left_comb_variant comb_cmap (size-1) in
    ok (List.append next [r])
  | _ -> fail (corner_case "Could not convert michelson_or left comb to a record")

let convert_pair_to_right_comb l =
  let l' = List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b) l in
  T_record (to_right_comb_pair l' LMap.empty)

let convert_pair_to_left_comb l =
  let l' = List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b) l in
  T_record (to_left_comb_pair l' LMap.empty)

let convert_pair_from_right_comb (src: row_element label_map) (dst: row_element label_map) : (type_content , typer_error) result =
  let%bind fields = from_right_comb_pair src (LMap.cardinal dst) in
  let labels = List.map (fun (l,_) -> l) @@
    List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b ) @@
    LMap.to_kv_list dst in
  ok @@ (T_record (LMap.of_list @@ List.combine labels fields))

let convert_pair_from_left_comb (src: row_element label_map) (dst: row_element label_map) : (type_content , typer_error) result =
  let%bind fields = from_left_comb_pair src (LMap.cardinal dst) in
  let labels = List.map (fun (l,_) -> l) @@
    List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b ) @@
    LMap.to_kv_list dst in
  ok @@ (T_record (LMap.of_list @@ List.combine labels fields))

let convert_variant_to_right_comb l =
  let l' = List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b) l in
  T_sum (to_right_comb_variant l' LMap.empty)

let convert_variant_to_left_comb l =
  let l' = List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b) l in
  T_sum (to_left_comb_variant l' LMap.empty)

let convert_variant_from_right_comb (src: row_element label_map) (dst: row_element label_map) : (type_content , typer_error) result =
  let%bind ctors = from_right_comb_variant src (LMap.cardinal dst) in
  let ctors_name = List.map (fun (l,_) -> l) @@
    List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b ) @@
    LMap.to_kv_list dst in
  ok @@ (T_sum (LMap.of_list @@ List.combine ctors_name ctors))

let convert_variant_from_left_comb (src: row_element label_map) (dst: row_element label_map) : (type_content , typer_error) result =
  let%bind ctors = from_left_comb_variant src (LMap.cardinal dst) in
  let ctors_name = List.map (fun (l,_) -> l) @@
    List.sort (fun (_,{decl_pos=a;_}) (_,{decl_pos=b;_}) -> Int.compare a b ) @@
    LMap.to_kv_list dst in
  ok @@ (T_sum (LMap.of_list @@ List.combine ctors_name ctors))