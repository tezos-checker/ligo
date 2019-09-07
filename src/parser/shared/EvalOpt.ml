(* Parsing the command-line options of PascaLIGO *)

(* The type [command] denotes some possible behaviours of the
   compiler. *)

type command = Quiet | Copy | Units | Tokens

(* The type [options] gathers the command-line options. *)

type options = {
  input   : string option;
  libs    : string list;
  verbose : Utils.String.Set.t;
  offsets : bool;
  mode    : [`Byte | `Point];
  cmd     : command
}

(* Auxiliary functions *)

let  printf = Printf.printf
let sprintf = Printf.sprintf
let   print = print_endline

let abort msg =
  Utils.highlight (sprintf "Command-line error: %s\n" msg); exit 1

(* Help *)

let help () =
  let file = Filename.basename Sys.argv.(0) in
  printf "Usage: %s [<option> ...] [<input>.ligo | \"-\"]\n" file;
  print "where <input>.ligo is the PascaLIGO source file (default: stdin),";
  print "and each <option> (if any) is one of the following:";
  print "  -I <paths>             Library paths (colon-separated)";
  print "  -c, --copy             Print lexemes of tokens and markup (lexer)";
  print "  -t, --tokens           Print tokens (lexer)";
  print "  -u, --units            Print tokens and markup (lexer)";
  print "  -q, --quiet            No output, except errors (default)";
  print "      --columns          Columns for source locations";
  print "      --bytes            Bytes for source locations";
  print "      --verbose=<stages> cmdline, cpp, ast (colon-separated)";
  print "      --version          Commit hash on stdout";
  print "  -h, --help             This help";
  exit 0

(* Version *)

let version () = printf "%s\n" Version.version; exit 0

(* Specifying the command-line options a la GNU *)

let copy     = ref false
and tokens   = ref false
and units    = ref false
and quiet    = ref false
and columns  = ref false
and bytes    = ref false
and verbose  = ref Utils.String.Set.empty
and input    = ref None
and libs     = ref []
and verb_str = ref ""

let split_at_colon = Str.(split (regexp ":"))

let add_path p = libs := !libs @ split_at_colon p

let add_verbose d =
  verbose := List.fold_left (Utils.swap Utils.String.Set.add)
                            !verbose
                            (split_at_colon d)

let specs =
  let open! Getopt in [
    'I',     nolong,    None, Some add_path;
    'c',     "copy",    set copy true, None;
    't',     "tokens",  set tokens true, None;
    'u',     "units",   set units true, None;
    'q',     "quiet",   set quiet true, None;
    noshort, "columns", set columns true, None;
    noshort, "bytes",   set bytes true, None;
    noshort, "verbose", None, Some add_verbose;
    'h',     "help",    Some help, None;
    noshort, "version", Some version, None
  ]
;;

(* Handler of anonymous arguments *)

let anonymous arg =
  match !input with
      None -> input := Some arg
  | Some s -> Printf.printf "s=%s\n" s;
             abort (sprintf "Multiple inputs")
;;

(* Checking options and exporting them as non-mutable values *)

let string_of convert = function
    None -> "None"
| Some s -> sprintf "Some %s" (convert s)

let string_of_path p =
  let apply s a = if a = "" then s else s ^ ":" ^ a
  in List.fold_right apply p ""

let quote s = sprintf "\"%s\"" s

let print_opt () =
  printf "COMMAND LINE\n";
  printf "copy     = %b\n" !copy;
  printf "tokens   = %b\n" !tokens;
  printf "units    = %b\n" !units;
  printf "quiet    = %b\n" !quiet;
  printf "columns  = %b\n" !columns;
  printf "bytes    = %b\n" !bytes;
  printf "verbose  = %s\n" !verb_str;
  printf "input    = %s\n" (string_of quote !input);
  printf "libs     = %s\n" (string_of_path !libs)
;;

let check () =
  let () =
    if Utils.String.Set.mem "cmdline" !verbose then print_opt () in

  let input =
    match !input with
      None | Some "-" -> !input
    | Some file_path ->
        if   Filename.check_suffix file_path ".ligo"
        then if   Sys.file_exists file_path
             then Some file_path
             else abort "Source file not found."
        else abort "Source file lacks the extension .ligo." in

  (* Exporting remaining options as non-mutable values *)

  let copy    = !copy
  and tokens  = !tokens
  and units   = !units
  and quiet   = !quiet
  and offsets = not !columns
  and mode    = if !bytes then `Byte else `Point
  and verbose = !verbose
  and libs    = !libs in

  let () =
    if Utils.String.Set.mem "cmdline" verbose then
      begin
        printf "\nEXPORTED COMMAND LINE\n";
        printf "copy     = %b\n" copy;
        printf "tokens   = %b\n" tokens;
        printf "units    = %b\n" units;
        printf "quiet    = %b\n" quiet;
        printf "offsets  = %b\n" offsets;
        printf "mode     = %s\n" (if mode = `Byte then "`Byte" else "`Point");
        printf "verbose  = %s\n" !verb_str;
        printf "input    = %s\n" (string_of quote input);
        printf "libs     = %s\n" (string_of_path libs)
      end in

  let cmd =
    match quiet, copy, units, tokens with
      false, false, false, false
    |  true, false, false, false -> Quiet
    | false,  true, false, false -> Copy
    | false, false,  true, false -> Units
    | false, false, false,  true -> Tokens
    | _ -> abort "Choose one of -q, -c, -u, -t."

  in {input; libs; verbose; offsets; mode; cmd}

(* Parsing the command-line options *)

let read () =
  try
    Getopt.parse_cmdline specs anonymous;
    (verb_str :=
       let apply e a =
         if a <> "" then Printf.sprintf "%s, %s" e a else e
       in Utils.String.Set.fold apply !verbose "");
    check ()
  with Getopt.Error msg -> abort msg