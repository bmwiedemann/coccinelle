open Common

(* full_engine takes (coccifile, isofile) and cfiles in parameters and
 * returns a list associating to the input cfiles, and maybe header
 * files that was also required to be modified, the files containing the
 * result (in general files in /tmp).
 * pre_engine does the compilation of the SmPL code and runs any initially
 * scripts
 * post_engine runs any finally scripts
 *
 * This function uses memoisation internally, which is useful when
 * using -dir to not redo twice the same work. So take care!
 *)
type cocci_info
val pre_engine : (filename * filename) -> cocci_info
val full_engine :
  cocci_info -> filename list -> (filename * filename option) list
val post_engine : cocci_info -> unit

(* because of the #include "toto.c" and also because we may associate the
 * same C file to multiple drivers because they share code, we can
 * modify multiple times the same file when use -dir. This check
 * remove duplicates and check that the modification are consistent
 * among the different drivers.
 *)
val check_duplicate_modif :
 (filename * filename option) list -> (filename * filename option) list

(* provides memoization *)
val sp_of_file :
  filename (* coccifile *)  -> filename option (* isofile *) ->
  Ast_cocci.metavar list list * Ast_cocci.rule list *
      Ast_cocci.meta_name list list list *
      Ast_cocci.meta_name list list list *
      (Ast_cocci.meta_name list list list (*used after list*) *
	 (*fresh used after list*)
	 Ast_cocci.meta_name list list list *
	 (*fresh used after list seeds*)
	 Ast_cocci.meta_name list list list) *
      Ast_cocci.meta_name list list list *
      (string list option (*grep tokens*) *
	 string list option (*glimpse tokens*) *
	 Get_constants2.combine option)

val normalize_path : string -> string
