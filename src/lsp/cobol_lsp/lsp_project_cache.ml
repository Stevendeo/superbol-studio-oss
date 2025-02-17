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

open Lsp_imports
open Ez_file.V1
open Ez_file.V1.EzFile.OP

module DIAGS = Cobol_common.Diagnostics

module TYPES = struct
  type config =
    {
      cache_relative_filename: string;
      cache_verbose: bool;
    }
end
include TYPES

(** Internal module used to hold a persistent representation of the set of
    opened document pertaining to a given project. *)
module CACHED_DOCS =
  Set.Make (struct
    open Lsp_document.TYPES
    type t = cached
    let compare { doc_cache_filename = f1; _ } { doc_cache_filename = f2; _ } =
      String.compare f1 f2
  end)

type cached_project_record =
  {
    cached_project: Lsp_project.cached;
    cached_docs: CACHED_DOCS.t;
  }

(* Code: *)

let cache_filename ~config ~rootdir =
  Lsp_project.string_of_rootdir rootdir // config.cache_relative_filename

let version_tag_length = 40            (* use full commit hash when available *)
let version_tag =
  let str = Option.value Version.commit_hash ~default:Version.version in
  if String.length str >= version_tag_length
  then String.sub str 0 version_tag_length
  else str ^ String.make (version_tag_length - String.length str) '_'

let write_project_cache cached_project_record oc =
  output_string oc version_tag;
  Marshal.to_channel oc (cached_project_record: cached_project_record)
    [Closures]                           (* Still required for Cobol_config.t *)

(** (Internal) Raises {!Failure} whenever the given input channel does not
    contain a usable project cache structure. *)
let read_project_cache ic =
  let version_tag' = really_input_string ic version_tag_length in
  if version_tag' <> version_tag
  then Fmt.failwith "Bad version tag: got %s, expected %s\
                    " version_tag' version_tag;
  (Marshal.from_channel ic: cached_project_record)

(** (Internal) May raise {!Failure} or {!Sys_error}. *)
let save_project_cache ~config
    (Lsp_project.{ rootdir; _ } as project) cached_docs =
  let cached_project_record =
    {
      cached_project = Lsp_project.to_cache project;
      cached_docs;
    }
  in
  let cache_file = cache_filename ~config ~rootdir in
  EzFile.(make_dir ~p:true (dirname cache_file));
  (* NB: don't really care if we rewrite the same cache again *)
  (* if Lsp_utils.is_file cache_file *)
  (* then (* read, write if commit hash or document changed *) *)
  (* else *)
  Lsp_utils.write_to cache_file (write_project_cache cached_project_record);
  Lsp_io.pretty_notification "Wrote cache at: %s" cache_file ~type_:Info

let save ~config docs =
  (* Pivot all active projects: associate projects with all their documents, and
     ignore any project that has none. *)
  URIMap.fold begin fun _ (Lsp_document.{ project; _ } as doc) ->
    Lsp_project.MAP.update project begin function
      | None -> Some (CACHED_DOCS.singleton (Lsp_document.to_cache doc))
      | Some s -> Some (CACHED_DOCS.add (Lsp_document.to_cache doc) s)
    end
  end docs Lsp_project.MAP.empty |>
  Lsp_project.MAP.iter (save_project_cache ~config)

(** (Internal) *)
let load_project ~rootdir ~layout ~config { cached_project; cached_docs; _ } =
  let project = Lsp_project.of_cache ~rootdir ~layout cached_project in
  let add_doc doc docs = URIMap.add (Lsp_document.uri doc) doc docs in
  CACHED_DOCS.fold begin fun cached_doc docs ->
    try
      let doc = Lsp_document.of_cache ~project cached_doc in
      if config.cache_verbose then
        Lsp_io.pretty_notification "Successfully read cache for %s"
          (Lsp.Uri.to_string @@ Lsp_document.uri doc) ~log:true ~type_:Info;
      add_doc doc docs
    with
    | Failure msg | Sys_error msg ->
        if config.cache_verbose then
          Lsp_io.pretty_notification "Failed to read cache for %s: %s"
            cached_doc.doc_cache_filename msg ~log:true ~type_:Info;
        docs
    | e ->
        Lsp_io.pretty_notification "Failed to read cache for %s: %a"
          cached_doc.doc_cache_filename Fmt.exn e ~log:true ~type_:Warning;
        docs
  end cached_docs URIMap.empty

let load ~rootdir ~layout ~config =
  let fallback = URIMap.empty in
  let cache_file = cache_filename ~config ~rootdir in
  try
    let cached_project = Lsp_utils.read_from cache_file read_project_cache in
    let project = load_project ~rootdir ~layout ~config cached_project in
    Lsp_io.pretty_notification "Successfully read cache for %s"
      (Lsp_project.string_of_rootdir rootdir) ~log:true ~type_:Info;
    project
  with
  | Failure msg | Sys_error msg ->
      if config.cache_verbose then
        Lsp_io.pretty_notification "Failed to read cache file %s: %s"
          cache_file msg ~log:true ~type_:Info;
      fallback
  | e ->
      Lsp_io.pretty_notification "Failed to read cache file %s: %a"
        cache_file Fmt.exn e ~log:true ~type_:Warning;
      fallback
