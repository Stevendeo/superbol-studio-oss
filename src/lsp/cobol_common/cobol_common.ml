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

module Basics = Basics
module Srcloc = Srcloc
module Copybook = Copybook
module Diagnostics = Diagnostics
module Visitor = Visitor
module Behaviors = Behaviors
module Tokenizing = Tokenizing

exception FatalError of string
let fatal fmt = Pretty.string_to (fun s -> raise @@ FatalError s) fmt

let status_ref = ref 0
let exit ?(status= 0) () =
  exit (max status !status_ref)

(* Register a printer for some common exceptions. *)
let () =
  Printexc.register_printer begin function
    | Failure m
    | Sys_error m
    | Stdlib.Arg.Bad m -> Some m
    | _ -> None
  end

(* --- *)

module Types = struct

  (** Transitional (to be removed) *)
  type 'a res = ('a * Diagnostics.Set.t, Diagnostics.Set.t) result

  include Diagnostics.TYPES
  include Srcloc.TYPES

end
include Types

(* TODO: move the ['a result] type related functions somewhere else *)
let join_all l =
  List.fold_left
    (fun res elt ->
       match res, elt with
       | Result.Error e, _ | _, Result.Error e -> Error e
       | Ok res, Ok e -> Ok (e::res))
    (Ok [])
    l
  |> Result.map List.rev

let join_any l =
  List.filter_map
    (fun elt ->
       match elt with
       | Ok elt ->
           Some elt
       | Error _ ->
           None)
    l
  |> List.rev

let catch_diagnostics ?(ppf = Fmt.stderr) f x =
  let module D = Diagnostics.InitStateful () in
  match f (module D: Diagnostics.STATEFUL) x with
  | Ok (v, diags) ->
      Ok (v, Diagnostics.Set.union diags @@ D.inspect ~reset:true)
  | Error diags ->
      Error (Diagnostics.Set.union diags @@ D.inspect ~reset:true)
  | exception Msgs.LocalizedError (s, loc, _) ->              (* TODO: addenda *)
      D.error ~loc "%t" s;
      Error (D.inspect ~reset:true)
  | exception Msgs.Error msg ->
      D.error "%t" msg;
      Error (D.inspect ~reset:true)
  (* | exception (Failure msg | Sys_error msg) -> *)
  (*     D.error "%s" msg; *)
  (*     Error (D.inspect ~reset:true) *)
  (* | exception Diagnostics.Fatal.Sink diags -> *)
  (*     Error (Diagnostics.Set.union diags @@ D.inspect ~reset:true) *)
  | exception (FatalError _ as e) ->
      Pretty.print ppf "%a%!" Diagnostics.Set.pp (D.inspect ~reset:false);
      raise e

let with_stateful_diagnostics ~f x =
  let module D = Diagnostics.InitStateful () in
  let result = f (module D: Diagnostics.STATEFUL) x in
  { result; diags = D.inspect ~reset:true }

(** [show_diagnostics ~ppf diagnostics] prints the given set of diagnostics
    using the formatter [ppf] (that defaults to [stderr]), and sets an internal
    status flags to register whether [diagnostics] includes an error.  This flag
    is used to determine the status code upon program termination.  *)
let show_diagnostics ?(ppf = Fmt.stderr) diags =
  Pretty.print ppf "%a%!" Diagnostics.Set.pp diags;
  if Diagnostics.Set.has_errors diags then status_ref := !status_ref lor 1

let catch_n_show_diagnostics ~cont ?(ppf = Fmt.stderr) f x =
  match catch_diagnostics ~ppf f x with
  | Ok (_, diags) | Error diags as res ->
      show_diagnostics ~ppf diags;
      if Result.is_error res then status_ref := !status_ref lor 1;
      cont res

(* --- *)

let do_one ~cont f ?epf a =
  catch_n_show_diagnostics ?ppf:epf ~cont f a

let do_unit f =
  do_one begin fun diags a ->
    f diags a;
    Ok ((), Diagnostics.Set.none)
  end ~cont:(fun _ -> ())

let do_any f =
  do_one begin fun diags a ->
    Ok (f diags a, Diagnostics.Set.none)
  end ~cont:(Result.fold ~ok:fst ~error:(fun _ -> Stdlib.exit 1))

(* --- *)

(* let tmp_files = ref [] *)
(* let remove_temporary_files = ref true *)

(* let add_temporary_file file = tmp_files := file :: !tmp_files *)
(* let keep_temporary_files () = remove_temporary_files := false *)

(* ;; *)

(* at_exit begin fun () -> *)
(*   if !remove_temporary_files then *)
(*     List.iter (fun file -> Sys.remove file) !tmp_files *)
(* end *)
