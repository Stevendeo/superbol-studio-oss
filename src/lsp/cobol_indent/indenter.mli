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

(*indent a range of file, with the user-defined or default indent_config*)
val indent_range'
  : dialect: Cobol_config.dialect
  -> source_format:Cobol_config.source_format_spec
  -> indent_config:string option
  -> range:Indent_type.range option
  -> filename:string
  -> contents:string
  -> string
