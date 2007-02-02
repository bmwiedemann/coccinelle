open Common open Commonop

module F = Control_flow_c

(*****************************************************************************)
(* The functor argument  *) 
(*****************************************************************************)

module XTRANS = struct

  (* ------------------------------------------------------------------------*)
  (* Combinators history *) 
  (* ------------------------------------------------------------------------*)
  (*
   * version0: 
   *  type ('a, 'b) transformer = 
   *    'a -> 'b -> Lib_engine.metavars_binding -> 'b
   *  exception NoMatch 
   * 
   * version1:
   *   type ('a, 'b) transformer = 
   *    'a -> 'b -> Lib_engine.metavars_binding -> 'b option
   * use an exception monad 
   *)

  (* ------------------------------------------------------------------------*)
  (* Standard type and operators  *) 
  (* ------------------------------------------------------------------------*)

  type tin = Lib_engine.metavars_binding
  type 'x tout = 'x option

  type ('a, 'b) matcher = 'a -> 'b  -> tin -> ('a * 'b) tout

  let (>>=) m f = fun tin -> 
     match m tin with
     | None -> None
     | Some (a,b) -> f a b tin

  let return = fun x -> fun tin -> 
    Some x

  (* can have fail in transform now that the process is deterministic ? *)
  let fail = fun tin -> 
    None

  let (>||>) m1 m2 = fun tin -> 
    match m1 tin with
    | None -> m2 tin
    | Some x -> Some x (* stop as soon as have found something *)


  (* ------------------------------------------------------------------------*)
  (* Exp  *) 
  (* ------------------------------------------------------------------------*)
  let cocciExp = fun expf expa node -> fun binding -> 

    let bigf = { 
      Visitor_c.default_visitor_c_s with 
      Visitor_c.kexpr_s = (fun (k, bigf) expb ->
	match expf expa expb binding with
	| None -> (* failed *) k expb
	| Some (x, expb) -> expb);
    }
    in
    Some (expa, Visitor_c.vk_node_s bigf node)


  (* ------------------------------------------------------------------------*)
  (* Tokens *) 
  (* ------------------------------------------------------------------------*)
   let check_pos mck pos = 
     match mck with
     | Ast_cocci.PLUS -> raise Impossible
     | Ast_cocci.CONTEXT (Some (i1,i2),_) 
     | Ast_cocci.MINUS   (Some (i1,i2),_) -> 
         pos <= i2 && pos >= i1
     | _ -> failwith "wierd: dont have position info for the mcodekind"      


  let tag_with_mck mck ib = fun binding -> 

    let (s2, cocciinforef) = ib in
    let (oldmcode, _oldenv) = !cocciinforef in

    let mck =
      if !Flag_parsing_cocci.sgrep_mode
      then Sgrep_julia.process_sgrep s2 mck
      else mck 
    in

    match (oldmcode,mck) with
    | (Ast_cocci.CONTEXT(_,Ast_cocci.NOTHING), _)
    | (_, Ast_cocci.CONTEXT(_,Ast_cocci.NOTHING)) ->

        if !Flag_engine.use_ref 
        then begin
          cocciinforef := (mck, binding);
          ((s2, cocciinforef) )
        end
        else 
          let newcocciinfo = ref (mck, binding) in
          ((s2, newcocciinfo))

    | _ -> 
      Printf.printf "SP mcode "; flush stdout;
      Pretty_print_cocci.print_mcodekind oldmcode;
      Format.print_newline();
      Printf.printf "C code mcode "; flush stdout;
      Pretty_print_cocci.print_mcodekind mck;
      Format.print_newline();
      failwith
	(Common.sprintf "already tagged token:\n%s"
	   (Common.error_message s2.file (s2.str, s2.charpos)))



  let tokenf ia ib = fun binding -> 
    let (s1, i, mck) = ia in
    let pos = Ast_c.get_pos_of_info ib in
    if check_pos mck pos 
    then return (ia, tag_with_mck mck ib binding) binding
    else fail binding


  (* ------------------------------------------------------------------------*)
  (* Distribute mcode *) 
  (* ------------------------------------------------------------------------*)

  (* When in the SP we attach something to a metavariable, or delete it, as in
   * - S
   * + foo();
   * we have to minusize all the token that compose S in the C code, and 
   * attach the 'foo();'  to the right token, the one at the very right. 
   *)

  type 'a distributer = 
      (Ast_c.info -> Ast_c.info) *  (* what to do on left *)
      (Ast_c.info -> Ast_c.info) *  (* what to do on middle *)
      (Ast_c.info -> Ast_c.info) *  (* what to do on right *)
      (Ast_c.info -> Ast_c.info) -> (* what to do on both *)
      'a -> 'a

  let distribute_mck mcodekind distributef expr binding =
    match mcodekind with
    | Ast_cocci.MINUS (pos,any_xxs) -> 
        distributef (
          (fun ib -> tag_with_mck (Ast_cocci.MINUS (pos,any_xxs)) ib binding),
          (fun ib -> tag_with_mck (Ast_cocci.MINUS (pos,[])) ib binding),
          (fun ib -> tag_with_mck (Ast_cocci.MINUS (pos,[])) ib binding),
          (fun ib -> tag_with_mck (Ast_cocci.MINUS (pos,any_xxs)) ib binding)
        ) expr
    | Ast_cocci.CONTEXT (pos,any_befaft) -> 
        (match any_befaft with
        | Ast_cocci.NOTHING -> expr
            
        | Ast_cocci.BEFORE xxs -> 
            distributef (
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.BEFORE xxs)) ib binding),
              (fun x -> x), 
              (fun x -> x), 
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.BEFORE xxs)) ib binding)
            ) expr
        | Ast_cocci.AFTER xxs ->  
            distributef (
              (fun x -> x), 
              (fun x -> x), 
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.AFTER xxs)) ib binding),
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.AFTER xxs)) ib binding)
            ) expr

        | Ast_cocci.BEFOREAFTER (xxs, yys) -> 
            distributef (
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.BEFORE xxs)) ib binding),
              (fun x -> x), 
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.AFTER yys)) ib binding),
              (fun ib -> tag_with_mck 
                (Ast_cocci.CONTEXT (pos,Ast_cocci.BEFOREAFTER (xxs,yys)))
                ib binding)
            ) expr

        )
    | Ast_cocci.PLUS -> raise Impossible


  (* use new strategy, collect ii, sort, recollect and tag *)

  let mk_bigf (maxpos, minpos) (lop,mop,rop,bop) = 
    let bigf = { 
      Visitor_c.default_visitor_c_s with
        Visitor_c.kinfo_s = (fun (k,bigf) i -> 
          let pos = Ast_c.get_pos_of_info i in
          match () with
          | _ when pos =|= maxpos && pos =|= minpos -> bop i
          | _ when pos =|= maxpos -> rop i
          | _ when pos =|= minpos -> lop i
          | _ -> mop i
        )
    } in
    bigf

  let distribute_mck_expr (maxpos, minpos) = fun (lop,mop,rop,bop) ->
  fun x ->
    Visitor_c.vk_expr_s (mk_bigf (maxpos, minpos) (lop,mop,rop,bop)) x


  let distrf_e ia x   = fun binding -> 
    let (s1, i, mck) = ia in
    let (max, min) = Lib_parsing_c.max_min_by_pos (Lib_parsing_c.ii_of_expr x)
    in
    
    if check_pos mck max && check_pos mck min 
    then 
      return (
        ia, 
        distribute_mck mck (distribute_mck_expr (max,min))  x binding
      ) binding
    else fail binding

  (* ------------------------------------------------------------------------*)
  (* Environment *) 
  (* ------------------------------------------------------------------------*)
  let envf keep _inherited (s, value) = fun env -> 
    if keep 
    then (
      try Some (s, List.assoc s env)
      with Not_found -> 
        pr2 ("Don't find value for metavariable " ^ s ^ " in the environment");
        None
    )
    else 
      Some (s, value)

end



(*****************************************************************************)
(* Entry point  *) 
(*****************************************************************************)
module TRANS  = Cocci_vs_c_3.COCCI_VS_C (XTRANS)

let (transform2: Lib_engine.transformation_info -> F.cflow -> F.cflow) = 
 fun xs cflow -> 
  (* find the node, transform, update the node,  and iter for all elements *)

   xs +> List.fold_left (fun acc (nodei, binding, rule_elem) -> 
      (* subtil: not cflow#nodes but acc#nodes *)
      let node  = acc#nodes#assoc nodei in 

      if !Flag_engine.show_misc 
      then pr2 "transform one node";

      let node' = TRANS.rule_elem_node rule_elem node binding in

      match node' with
      | None -> raise Impossible
      | Some (_sp, node') -> 

          (* assert that have done something. But with metaruleElem sometimes 
             dont modify fake nodes. So special case before on Fake nodes. *)
          (match F.unwrap node with
          | F.Enter | F.Exit | F.ErrorExit
          | F.EndStatement _ | F.CaseNode _        
          | F.Fake
          | F.TrueNode | F.FalseNode | F.AfterNode | F.FallThroughNode 
              -> ()
          | _ -> () (* assert (not (node =*= node')); *)
          );
          
          acc#replace_node (nodei, node')
     ) cflow

let transform a b = 
  Common.profile_code "Transformation2.transform(proto)?" 
    (fun () -> transform2 a b)

