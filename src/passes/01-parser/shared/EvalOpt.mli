(** Parsing the command-line options of LIGO *)

(** The type [command] denotes some possible behaviours of the
    compiler. The constructors are
    {ul

      {li [Quiet], then no output from the lexer and parser should be
          expected, safe error messages: this is the default value;}

      {li [Copy], then lexemes of tokens and markup will be printed to
          standard output, with the expectation of a perfect match
          with the input file;}

      {li [Units], then the tokens and markup will be printed to
          standard output, that is, the abstract representation of the
          concrete lexical syntax;}

      {li [Tokens], then the tokens only will be printed.}
    }
 *)
type command = Quiet | Copy | Units | Tokens

(** The type [options] gathers the command-line options.
    {ul

      {li If the field [input] is [Some src], the name of the LIGO
          source file is [src]. If [input] is [Some "-"] or [None],
          the source file is read from standard input.}

      {li The field [libs] is the paths where to find LIGO files
          for inclusion (#include).}

      {li The field [verbose] is a set of stages of the compiler
          chain, about which more information may be displayed.}

      {li If the field [offsets] is [true], then the user requested
          that messages about source positions and regions be
          expressed in terms of horizontal offsets.}

      {li If the value [mode] is [`Byte], then the unit in which
          source positions and regions are expressed in messages is
          the byte. If [`Point], the unit is unicode points.}

      {li If the field [mono] is [true], then the monolithic API of
          Menhir is called, otherwise the incremental API is.}

      {li If the field [expr] is [true], then the parser for
          expressions is used, otherwise a full-fledged contract is
          expected.}
} *)

module SSet : Set.S with type elt = string and type t = Set.Make(String).t

type line_comment = string (* Opening of a line comment *)
type block_comment = <opening : string; closing : string>

val mk_block : opening:string -> closing:string -> block_comment

type options = <
  input   : string option;
  libs    : string list;
  verbose : SSet.t;
  offsets : bool;
  block   : block_comment option;
  line    : line_comment option;
  ext     : string;
  mode    : [`Byte | `Point];
  cmd     : command;
  mono    : bool;
  expr    : bool
>

val make :
  input:string option ->
  libs:string list ->
  verbose:SSet.t ->
  offsets:bool ->
  ?block:block_comment ->
  ?line:line_comment ->
  ext:string ->
  mode:[`Byte | `Point] ->
  cmd:command ->
  mono:bool ->
  expr:bool ->
  options

(** Parsing the command-line options on stdin. *)

type extension = string

val read :
  ?block:block_comment -> ?line:line_comment -> extension -> options