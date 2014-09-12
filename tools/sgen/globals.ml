(* Global variables and hardcoded standard stuff goes here.
 * Also some general purpose functions for strings and sanity checks. *)

(* ------------------------------------------------------------------------- *)
(* GLOBAL VARIABLES AND GETTERS *)
(* read-only after initialisation *)

(* Default names for generated positions *)
let pos_name = ref "j"
let get_pos_name() = !pos_name

(* Default rule names for unnamed rules. Accessed through generate_rule. *)
let rule_name = ref "rule"
let rule_counter = ref 0

(* Default error message for org and report mode *)
let error_message = ref "found a match here ..."
let get_default_message() = !error_message

let get_context_name ~context_mode str =
  if context_mode then str else str ^ "_context"
let get_disj_name str = str ^ "_disj"

(* Page width limit for generated script (not always upheld ...) *)
let char_limit = ref 80

let init ~rule_name:r ~pos_name:p ~error_msg:e ~char_limit:cl =
  rule_counter := 0;
  pos_name := p;
  rule_name := r;
  error_message := e;
  char_limit := cl


(* ------------------------------------------------------------------------- *)
(* HARDCODED (PHTOOEY) *)

(* list of things you can't call your rules, because it will mess with sgen *)
let keywords =
  ["patch"; "context"; "org"; "report"; "description"; "limitations";
   "keywords"; "comments"; "options"; "confidence"; "authors";
   "d";"k";"c";"m";"o";"l";"a"]

(* default virtual rule names *)
let get_virtuals context_mode =
  if context_mode then ["context"; "org"; "report"]
  else ["patch"; "context"; "org"; "report"]


(* ------------------------------------------------------------------------- *)
(* NIFTY STRING FUNCTIONS *)

(* split a string into a list of strings with at most limit characters each,
 * delimitering by space. *)
let split limit s =
  let get_rev_indices str lim =
    let len = String.length s in
    let rec get_rev acc start =
      if (len - start <= lim) then (start, len) :: acc
      else
        let space_index =
          try String.rindex_from str (start + lim) ' '
          with Not_found -> start + lim in
        get_rev ((start, space_index) :: acc) (space_index + 1) in
    get_rev [] 0 in
  let indices = get_rev_indices s (limit-1) in
  List.rev_map (fun (st,en) -> String.sub s st (en-st)) indices

(* split string into strings of at most limit length
 * append prefix to each new string *)
let pre_split ?(prefix = "") s =
  let limit = (!char_limit - String.length prefix) in
  let splitted = split limit s in
  String.concat "\n" (List.map (fun x -> prefix ^ x) splitted)

(* same as pre_split, but with a string option *)
let pre_split_opt ?(prefix = "") = function
  | Some s -> pre_split ~prefix s
  | None -> ""

let starts_with_digit x = Str.string_match (Str.regexp "^[0-9]") x 0

(* change extension of filename *)
let new_extension ~new_ext str =
  let extless =
    try String.sub str 0 (String.index str '.')
    with Not_found -> str in
  extless ^ "." ^ new_ext


(* ------------------------------------------------------------------------- *)
(* SANITY CHECKS AND RULE HELPERS *)

(* check if virtual rule names are valid and return the standard ones *)
let key_virtuals v context_mode =
  let keyvirtuals = get_virtuals context_mode in
  let check x = if List.mem x keyvirtuals then
    failwith ("Error: patch, context, org, and report are reserved virtual " ^
    "rules.") in
  List.iter check v; keyvirtuals

(* check if a rulename is valid *)
let check_rule ~strict x =
  if x = "" then failwith
    "Error: Rulename cannot be empty!";
  if strict && String.contains x ' ' then failwith
    ("Error: Rulenames cannot contain spaces: \"" ^ x ^ "\".");
  if starts_with_digit x then failwith
    ("Error: Rules that start with digits are not allowed: \"" ^ x ^ "\".");
  let gen_rule = !rule_name in
  let regexp = Str.regexp ((Str.quote gen_rule) ^ "[0-9]+$") in
  if Str.string_match regexp x 0 then failwith
    ("Error: The default generated rule name is \""^ gen_rule ^"<number>\".\n"^
     "The name \"" ^ x ^ "\" is invalid, since it may overlap with a " ^
     "generated rule name.");
  if List.mem x keywords then failwith
    ("Error: A rule can't be called \""^ x ^"\"! That's a keyword in sgen ...")

(* for rules with no name; get the line they are starting on *)
let extract_line str =
  if Str.string_match (Str.regexp "^\\(rule starting on line \\)") str 0
  then
    let i = Str.match_end() in
    let num = String.sub str i ((String.length str) - i) in
    int_of_string num
  else failwith ("Was not a nameless rule: " ^ str)

(* Only generates rulename if input name is invalid as rulename *)
let generate_rule nm =
  try check_rule ~strict:true nm; None
  with Failure _ ->
    let new_name = !rule_name ^ (string_of_int !rule_counter) in
    rule_counter := !rule_counter + 1; Some new_name


(* ------------------------------------------------------------------------- *)
(* MISC *)

let get_current_year() =
  let time = Unix.gmtime (Unix.time()) in time.Unix.tm_year + 1900
