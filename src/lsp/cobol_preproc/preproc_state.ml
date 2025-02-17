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

open Text.TYPES

type state =
  | AllowAll
  | AfterControlDivisionHeader
  | AfterSubstitSectionHeader
  | AllowReplace
  | ForbidReplace
type t = state

let initial = AllowAll

type preproc_phrase =
  | Copy of phrase
  | Replace of phrase
  | Header of tracked_header * phrase
and phrase =
  {
    prefix: text;
    phrase: text;
    suffix: text;
  }
and tracked_header =
  | ControlDivision
  | SubstitutionSection
  | IdentificationDivision

(** [find_phrase first_word ~prefix text] looks for a phrase start starts with
    [first_word] and terminates with a period in [text].  If [prefix = `Rev] and
    upon success, the prefix is reveresed in the result. *)
let find_phrase first_word ?(prefix = `Same) text : _ result =
  let split_at_first = Cobol_common.Basics.LIST.split_at_first in
  let split_before_word =
    split_at_first ~prefix ~where:`Before (Text.textword_eqp ~eq:first_word)
  and split_after_period =
    split_at_first ~prefix:`Same ~where:`After (Text.textword_eqp ~eq:".")
  in
  match split_before_word text with
  | Error () ->
      Error `NoneFound
  | Ok (prefix, phrase) ->
      match split_after_period phrase with
      | Error () ->
          Error `MissingPeriod
      | Ok (phrase, suffix) ->
          Ok { prefix; phrase; suffix }

(** [find_full_phrase words ~search_deep ~try_hard ~prefix text] looks for a
    pharse comprised of all words in [words] and termiates with a period in
    [text].  If [prefix = `Rev] and upon success, the prefix is reveresed in the
    returned structure.

    - [search_deep] indicates whether the phrase may not start at the first
      word;

    - [try_hard] indicates whether the phrase may be preceded by incomplete
      prefixes.
*)
let find_full_phrase all_words
    ?(prefix = `Same) ?(search_deep = false) ?(try_hard = false)
  : text -> _ result =
  let all_words = all_words @ ["."] in
  let split_at_first = Cobol_common.Basics.LIST.split_at_first in
  let split_before_word first_word =
    split_at_first ~prefix ~where:`Before (Text.textword_eqp ~eq:first_word)
  and split_after_period =
    split_at_first ~prefix:`Same ~where:`After (Text.textword_eqp ~eq:".")
  and check_phrase =
    let rec aux words phrase = match words, phrase with
      | [], _ -> Ok ()
      | _ :: _, [] -> Error `MissingText
      | w :: wtl, w' :: w'tl when Text.textword_eqp ~eq:w w' -> aux wtl w'tl
      | _ -> Error `NoneFound
    in
    aux all_words
  in
  let rec try_from text : _ result =
    match split_before_word (List.hd all_words) text with
    | Error () ->
        Error `NoneFound
    | Ok (prefix_text, phrase) ->
        try_from_first_word prefix_text phrase
  and try_from_first_word prefix_text phrase =
    match split_after_period phrase with
    | Error () ->
        Error `MissingPeriod
    | Ok (phrase, suffix) ->
        match check_phrase phrase with
        | Ok () ->
            Ok { prefix = prefix_text; phrase; suffix }
        | Error `MissingText as e ->
            e
        | Error `NoneFound as e when not try_hard ->
            e
        | Error `NoneFound ->
            (* Note: even when trying hard, we make the simplifying
               assumption the given words allow us to continue with `suffix`
               and not from the second word in `phrase`. *)
            match try_from suffix, prefix with
            | Error _ as e, _ ->
                e
            | Ok phrase, `Same ->
                Ok { phrase with prefix = prefix_text @ phrase.prefix }
            | Ok phrase, `Rev ->
                Ok { phrase with prefix = phrase.prefix @ prefix_text }
  in
  if search_deep
  then try_from
  else try_from_first_word []

(** [find_preproc_phrase ~prefix state text] attempts to find a phrase in [text]
    that is relevant in preprocessing state [state].  Returned phrases have a
    [prefix] text that is reversed when [prefix = `Rev]. *)
let find_preproc_phrase ?prefix =
  (* NB: This is a somewhat hackish and manual encoding of a state machine, used
     to only allow a single REPLACE wihtin the SUBSTITUTION SECTION of the
     CONTROL DIVISION; if such a REPLACE is present, then it must be the only
     one in the compilation group.

     NOTE: for now the aforementiones division and section headers are detected
     only when they start at the very begining of the given text.  This seems to
     be ok as long as they are preceded with a period (.), since we perform the
     search on a sentence-by-sentence basis.

     CHECKME: the SUBSTITUTION SECTION may only be allowed after or before the
     DEFAULT SECTION. *)
  let find_phrase = find_phrase ?prefix
  and find_full_phrase = find_full_phrase ?prefix in
  let find_cntrl_div_header = find_full_phrase ["CONTROL"; "DIVISION"]
  and find_ident_div_header = find_full_phrase ["IDENTIFICATION"; "DIVISION"]
  and find_subst_sec_header = find_full_phrase ["SUBSTITUTION"; "SECTION"] in
  let try_replace ~next src =
    match find_phrase "REPLACE" src with
    | Ok repl -> Ok (Replace repl, next)
    | Error _ as e -> e
  in
  let try_identification_division_header ?(next = AllowReplace) src =
    match find_ident_div_header src with
    | Ok x -> Ok (Header (IdentificationDivision, x), next)
    | Error `NoneFound -> try_replace ~next src
    | Error _ as e -> e
  in
  let try_control_division_header src =
    match find_cntrl_div_header src with
    | Ok x -> Ok (Header (ControlDivision, x), AfterControlDivisionHeader)
    | Error `NoneFound -> try_identification_division_header src
    | Error _ as e -> e
  in
  let try_substitution_section_header src =
    match find_subst_sec_header src with
    | Ok x -> Ok (Header (SubstitutionSection, x), AfterSubstitSectionHeader)
    | Error `NoneFound -> try_identification_division_header src
    | Error _ as e -> e
  in
  fun state src ->
    (* Note COPY takes precedence over REPLACE, as per the ISO/IEC 2014
       standard, 7.2 Text manipulation. *)
    match find_phrase "COPY" src, state with
    | Ok copy, _ ->
        Ok (Copy copy, state)
    | Error `MissingPeriod as e, _ ->
        e
    | Error `NoneFound, AllowAll ->
        try_control_division_header src
    | Error `NoneFound, AllowReplace ->
        try_replace ~next:AllowReplace src
    | Error `NoneFound, ForbidReplace ->
        Error `NoneFound
    | Error `NoneFound, AfterControlDivisionHeader ->
        try_substitution_section_header src
    | Error `NoneFound, AfterSubstitSectionHeader ->
        try_identification_division_header ~next:ForbidReplace src
