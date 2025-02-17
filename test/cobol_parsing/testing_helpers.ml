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

open Cobol_common.Srcloc.INFIX

module type TAGS = sig
  val loc: Cobol_common.Srcloc.srcloc
end

module Make (Tags: TAGS) = struct
  open Cobol_ptree

  module Term = struct
    let name x : qualname = Name (x &@ Tags.loc)
    let qualident x : qualident =
      { ident_name = name x; ident_subscripts = [] }
    let ident x : ident_or_literal = QualIdent (qualident x)
    let strlit l : ident_or_literal = Alphanum (l, Dquote)
  end

  module Cond = struct
    open Term
    let ident x : condition = Expr (Atom (ident x))
  end

end
