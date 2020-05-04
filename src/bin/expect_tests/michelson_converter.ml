open Cli_expect

let contract basename =
  "../../test/contracts/" ^ basename
let bad_contract basename =
  "../../test/contracts/negative/" ^ basename

let%expect_test _ =
  run_ligo_bad [ "interpret" ; "--init-file="^(bad_contract "michelson_converter_no_annotation.mligo") ; "l4"] ;
  [%expect {|
    ligo: in file "michelson_converter_no_annotation.mligo", line 4, characters 9-39. can't retrieve type declaration order in the converted record, you need to annotate it

     If you're not sure how to fix this error, you can
     do one of the following:

    * Visit our documentation: https://ligolang.org/docs/intro/introduction
    * Ask a question on our Discord: https://discord.gg/9rhYaEt
    * Open a gitlab issue: https://gitlab.com/ligolang/ligo/issues/new
    * Check the changelog by running 'ligo changelog' |}] ;

  run_ligo_bad [ "interpret" ; "--init-file="^(bad_contract "michelson_converter_short_record.mligo") ; "l1"] ;
  [%expect {|
    ligo: in file "michelson_converter_short_record.mligo", line 4, characters 9-44. converted record must have at least two elements

     If you're not sure how to fix this error, you can
     do one of the following:

    * Visit our documentation: https://ligolang.org/docs/intro/introduction
    * Ask a question on our Discord: https://discord.gg/9rhYaEt
    * Open a gitlab issue: https://gitlab.com/ligolang/ligo/issues/new
    * Check the changelog by running 'ligo changelog' |}]

let%expect_test _ =
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_pair.mligo") ; "r3"] ;
  [%expect {|
    ( 2 , ( +3 , "q" ) ) |}] ;
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_pair.mligo") ; "r4"] ;
  [%expect {|
    ( 2 , ( +3 , ( "q" , true(unit) ) ) ) |}] ;
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_pair.mligo") ; "l3"] ;
  [%expect {|
    ( ( 2 , +3 ) , "q" ) |}] ;
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_pair.mligo") ; "l4"] ;
  [%expect {|
    ( ( ( 2 , +3 ) , "q" ) , true(unit) ) |}];
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_or.mligo") ; "str3"] ;
  [%expect {|
    M_right(M_left(+3)) |}] ;
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_or.mligo") ; "str4"] ;
  [%expect {|
    M_right(M_right(M_left("eq"))) |}] ;
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_or.mligo") ; "stl3"] ;
  [%expect {|
    M_left(M_right(+3)) |}] ;
  run_ligo_good [ "interpret" ; "--init-file="^(contract "michelson_converter_or.mligo") ; "stl4"] ;
  [%expect {|
    M_left(M_right("eq")) |}]

let%expect_test _ =
  run_ligo_good [ "dry-run" ; (contract "michelson_converter_pair.mligo") ; "main_r" ; "test_input_pair_r" ; "s"] ;
  [%expect {|
    ( LIST_EMPTY() , "eqeq" ) |}] ;
  run_ligo_good [ "compile-contract" ; (contract "michelson_converter_pair.mligo") ; "main_r" ] ;
  [%expect {|
    { parameter (pair (int %one) (pair (nat %two) (pair (string %three) (bool %four)))) ;
      storage string ;
      code { DUP ;
             CAR ;
             DUP ;
             CDR ;
             CDR ;
             CAR ;
             DIG 1 ;
             DUP ;
             DUG 2 ;
             CDR ;
             CDR ;
             CAR ;
             CONCAT ;
             NIL operation ;
             PAIR ;
             DIP { DROP 2 } } } |}];
  run_ligo_good [ "dry-run" ; (contract "michelson_converter_pair.mligo") ; "main_l" ; "test_input_pair_l" ; "s"] ;
  [%expect {|
    ( LIST_EMPTY() , "eqeq" ) |}] ;
  run_ligo_good [ "compile-contract" ; (contract "michelson_converter_pair.mligo") ; "main_l" ] ;
  [%expect {|
    { parameter (pair (pair (pair (int %one) (nat %two)) (string %three)) (bool %four)) ;
      storage string ;
      code { DUP ;
             CAR ;
             DUP ;
             CAR ;
             CDR ;
             DIG 1 ;
             DUP ;
             DUG 2 ;
             CAR ;
             CDR ;
             CONCAT ;
             NIL operation ;
             PAIR ;
             DIP { DROP 2 } } } |}];
  run_ligo_good [ "dry-run" ; contract "michelson_converter_or.mligo" ; "main_r" ; "vr" ; "Foo4 2"] ;
  [%expect {|
    ( LIST_EMPTY() , Baz4("eq") ) |}] ;
  run_ligo_good [ "compile-contract" ; contract "michelson_converter_or.mligo" ; "main_r" ] ;
  [%expect {|
    { parameter (or (int %foo4) (or (nat %bar4) (or (string %baz4) (bool %boz4)))) ;
      storage (or (or (nat %bar4) (string %baz4)) (or (bool %boz4) (int %foo4))) ;
      code { PUSH string "eq" ;
             LEFT bool ;
             RIGHT nat ;
             RIGHT int ;
             PUSH string "eq" ;
             RIGHT (or (int %foo4) (nat %bar4)) ;
             LEFT bool ;
             DIG 2 ;
             DUP ;
             DUG 3 ;
             CAR ;
             IF_LEFT
               { DUP ; RIGHT bool ; RIGHT (or nat string) ; DIP { DROP } }
               { DUP ;
                 IF_LEFT
                   { DUP ; LEFT string ; LEFT (or bool int) ; DIP { DROP } }
                   { DUP ;
                     IF_LEFT
                       { DUP ; RIGHT nat ; LEFT (or bool int) ; DIP { DROP } }
                       { DUP ; LEFT int ; RIGHT (or nat string) ; DIP { DROP } } ;
                     DIP { DROP } } ;
                 DIP { DROP } } ;
             DUP ;
             NIL operation ;
             PAIR ;
             DIP { DROP 4 } } } |}] ;
  run_ligo_good [ "dry-run" ; contract "michelson_converter_or.mligo" ; "main_l" ; "vl" ; "Foo4 2"] ;
  [%expect {|
    ( LIST_EMPTY() , Baz4("eq") ) |}] ;
  run_ligo_good [ "compile-contract" ; contract "michelson_converter_or.mligo" ; "main_l" ] ;
  [%expect {|
    { parameter (or (or (or (int %foo4) (nat %bar4)) (string %baz4)) (bool %boz4)) ;
      storage (or (or (nat %bar4) (string %baz4)) (or (bool %boz4) (int %foo4))) ;
      code { PUSH string "eq" ;
             LEFT bool ;
             RIGHT nat ;
             RIGHT int ;
             PUSH string "eq" ;
             RIGHT (or (int %foo4) (nat %bar4)) ;
             LEFT bool ;
             DIG 2 ;
             DUP ;
             DUG 3 ;
             CAR ;
             IF_LEFT
               { DUP ;
                 IF_LEFT
                   { DUP ;
                     IF_LEFT
                       { DUP ; RIGHT bool ; RIGHT (or nat string) ; DIP { DROP } }
                       { DUP ; LEFT string ; LEFT (or bool int) ; DIP { DROP } } ;
                     DIP { DROP } }
                   { DUP ; RIGHT nat ; LEFT (or bool int) ; DIP { DROP } } ;
                 DIP { DROP } }
               { DUP ; LEFT int ; RIGHT (or nat string) ; DIP { DROP } } ;
             DUP ;
             NIL operation ;
             PAIR ;
             DIP { DROP 4 } } } |}]


let%expect_test _ =
  run_ligo_good [ "compile-contract" ; contract "michelson_comb_type_operators.mligo" ; "main_r"] ;
  [%expect {|
    { parameter (pair (int %foo) (pair (nat %bar) (string %baz))) ;
      storage unit ;
      code { UNIT ; NIL operation ; PAIR ; DIP { DROP } } } |}] ;

  run_ligo_good [ "compile-contract" ; contract "michelson_comb_type_operators.mligo" ; "main_l"] ;
  [%expect {|
    { parameter (pair (pair (int %foo) (nat %bar)) (string %baz)) ;
      storage unit ;
      code { UNIT ; NIL operation ; PAIR ; DIP { DROP } } } |}]