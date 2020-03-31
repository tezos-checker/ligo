(* Driver for the PascaLIGO lexer *)

module Region = Simple_utils.Region

module IO =
  struct
    let options = EvalOpt.(read ~lang:PascaLIGO ~ext:".ligo")
  end

module M = LexerUnit.Make (IO) (Lexer.Make (LexToken))

let () =
  match M.trace () with
    Stdlib.Ok () -> ()
  | Error Region.{value; _} -> Utils.highlight value
