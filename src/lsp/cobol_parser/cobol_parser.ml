(**************************************************************************)
(*                                                                        *)
(*                        SuperBOL OSS Studio                             *)
(*                                                                        *)
(*  Copyright (c) 2022-2023 OCamlPro SAS                                  *)
(*                                                                        *)
(* All rights reserved.                                                   *)
(* This source code is licensed under the GNU Affero General Public       *)
(* License version 3 found in the LICENSE.md file in the root directory   *)
(* of this source tree.                                                   *)
(*                                                                        *)
(**************************************************************************)

(** {1 Exported modules} *)

(** Options to tune the parser engine *)
module Options = Parser_options

(** Output types for the engine *)
module Outputs = Parser_outputs

module Tokens = Grammar_tokens
module Keywords = Text_keywords

(** {1 Exported functions} *)

include Parser_engine

(** {1 Modules and functions exported for testing purposes}

    Signatures of modules below may change unexpectedly. *)

module INTERNAL = struct

  (** {2 COBOL tokens} *)

  module Tokens = Grammar_tokens

  let pp_token = Text_tokenizer.pp_token
  let pp_tokens = Text_tokenizer.pp_tokens

  (** {2 COBOL grammar} *)

  module Grammar (* : Grammar_sig.S *) = Grammar

  (** {2 Dummy parser} *)

  (** Parser with dummy source locations, that can be fed directly with a
      list of tokens *)
  module Dummy = struct
    module Tags = struct
      let loc = Cobol_common.Srcloc.raw Lexing.(dummy_pos, dummy_pos)
    end

    let parse_as item toks =
      let toks = ref toks
      and dummy_lexer = Lexing.from_string ~with_positions:false "" in
      item begin fun _ -> match !toks () with
        | Seq.Nil -> Grammar_tokens.EOF
        | Cons (x, tl) -> toks := tl; x
      end dummy_lexer

    let parse_list_as parse lx = parse_as parse (List.to_seq lx)
  end
end
