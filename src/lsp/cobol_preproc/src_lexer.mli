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

(* First lexer *)

val line: ('k Src_lexing.state as 's) -> Lexing.lexbuf -> 's * Text.text

(* Second lexer *)

val keyword_of_cdtoken: (Compdir_grammar.token, string) Hashtbl.t

type cdtoken_component =
  | CDTok of Compdir_grammar.token
  | CDEnd
val cdtoken: Lexing.lexbuf -> cdtoken_component

(* Third lexer *)

val keyword_of_pptoken: (Preproc_tokens.token, string) Hashtbl.t

type pptoken_component =
  | PPTok of Preproc_tokens.token
  | PPEnd
val pptoken: Lexing.lexbuf -> pptoken_component
