(*
 * Copyright 2018, Data61
 * Commonwealth Scientific and Industrial Research Organisation (CSIRO)
 * ABN 41 687 119 230.
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(DATA61_BSD)
 *)

theory Read_Table
imports
  "Cogent.Cogent"
  Specialised_Lemma_Utils
begin

(*
 * Read Cogent-C type mapping (".table" file) generated by cogent compiler.
 * The format is:
 *   Cogent_type :=: C_type
 * e.g.
 *   TRecord [(TPrim (Num U32), False)] Unboxed :=: t1
 * We parse each pair by reading Cogent_type as an Isabelle term.
 * C_type is a C identifier so parsing it is trivial.
 *)
ML \<open>
datatype tok = Sep of char | Str of string
(* a version of String.tokens which keep the separator *)
fun tokens_keep_sep p s : tok list=
     (* tokens and fields are very similar except that tokens does not return
           empty strings for adjacent delimiters whereas fields does.  *)
            let
            val length = size s
            fun tok' i l = (* i is the character to examine.  l is the start of a token *)
                if i = length
                then (* Finished the input.  Return any partially completed string. *)
                    (
                    if l = i then [] else [substring (s, l, i-l) |> Str]
                    )
                else if p (String.sub(s, i)) (* TODO: We don't need sub to do the range check here *)
                then (* It's a delimiter.  If we have more than one character in the
                        string we create a string otherwise we just continue. *)
                    (
                    if l = i then  (String.sub(s, i) |> Sep) :: tok' (i+1) (i+1)
                    else (substring (s, l, i-l) |> Str) :: (String.sub(s, i) |> Sep)
                            :: tok' (i+1) (i+1)
                    )
                else (* Token: Keep accumulating characters. *) tok' (i+1) l
            in
            tok' 0 0
            end

fun split_words (s : string) : tok list =
  tokens_keep_sep (fn #"_" =>false | c => not (Char.isAlphaNum c)) s 
  |> List.filter (fn Sep #" " => false | _ => true) \<close>

ML \<open>split_words " t1_C [ set/get set2/get2 ]"\<close>

ML \<open>
fun read_table (file_name:string) thy =
  let
    val path_to_c = (Resources.master_directory thy |> File.platform_path) ^ "/" ^ file_name;
    val path_to_table = (unsuffix ".c" path_to_c) ^ ".table";
    val input_file = TextIO.openIn path_to_table;

    val lines = split_lines (TextIO.inputAll input_file);
    val pos_lines = (1 upto length lines) ~~ lines;
    fun report pos = path_to_table ^ ":" ^ string_of_int pos ^ ": ";
    fun report_getset pos = report pos ^ "expected: C_type [ getter1/setter1, .. ]"

    val tymap = pos_lines
                |> filter (fn (_, l) => not (String.isPrefix "--" l) andalso
                                        not (String.isPrefix " " l) andalso
                                        not (String.size l = 0))
                |> map (fn (pos, l) =>
                    case split_on " :=: " l of
                        [cogentT, cT] => (pos, cogentT, cT)
                      | _ => error (report pos ^ "expected \" :=: \""))
                : (int * string * string) list;
    fun consume_getsetter _ (Str getter :: Sep #"/" :: Str setter (* :: Sep #":" :: Str ty *) :: l)  =
       ({(*ty = ty, *) getter = getter, setter = setter} : {getter : string, setter : string} , l)
     | consume_getsetter pos _ = 
       error(report_getset pos)
   fun read_fieldinfo _ [Sep #"]"] = [] : {getter : string, setter : string} list  
    | read_fieldinfo pos l =
       case consume_getsetter pos l of
            (info, [Sep #"]"]) => [info]
          | (info, (Sep #"," :: l)) => info :: read_fieldinfo pos l
          | _ =>  error(report_getset pos)
 

    fun cT_to_C_name_fieldinfos pos cT : string *  {getter : string, setter : string} list option = 
        case split_words cT of
            [] => error(report pos ^ "expected: C type")
           | [Str C_name] => (C_name, NONE)
           | Str C_name :: Sep #"[" :: l => (C_name, SOME (read_fieldinfo pos l))
           | _ => error(report_getset pos)


    val ctxt = Proof_Context.init_global thy
    val tymap = tymap
                |> map (fn (pos, cogentT, cT) => let
                    fun err () = error (report pos ^ "failed to parse Cogent type:" ^ cogentT)
                    val cogentT = Syntax.read_term ctxt cogentT
                                handle ERROR _ => err ()
                    val _ = if type_of cogentT = @{typ Cogent.type} then () else err ()
                    val (cT , infos) = cT_to_C_name_fieldinfos pos cT
                    in (pos, cogentT, cT, infos) end)
                : (int * term * string * {getter : string, setter : string} list option) list; 

    fun build_layout_info pos (SOME infos) names =
         (ListPair.mapEq (fn ({getter, setter}, name) => {getter = getter, setter = setter, name = name})
          (infos, names) |> CustomLayout
         handle ListPair.UnequalLengths => error (report pos ^ "The number of custom getters/setters differs from the number of fields"))
      | build_layout_info _ NONE _ = DefaultLayout

    fun decode_sigil names pos   ((Const (@{const_name Boxed}, _)) $ (Const (@{const_name Writable}, _)) $ _) l = 
         Boxed(Writable, build_layout_info pos l names)
      | decode_sigil names pos   ((Const (@{const_name Boxed}, _)) $ (Const (@{const_name ReadOnly}, _)) $ _) l = 
         Boxed(ReadOnly, build_layout_info pos l names)
      | decode_sigil _ _   (Const (@{const_name Unboxed},  _)) _ = Unboxed
      | decode_sigil _ pos t _ = raise TERM (report pos ^ "bad sigil", [t]);
   
    fun decode_field_names (l : term) =
      HOLogic.dest_list l |>
       List.map (HOLogic.dest_prod) |>
       List.map fst |> List.map HOLogic.dest_string

    fun decode_type (_, Const (@{const_name TCon}, _) $ _ $ _ $ _, cT, _) =
            UAbstract cT
      | decode_type (pos, Const (@{const_name TRecord}, _) $ l $ sigil, cT, getsets) =
            URecord (cT, (decode_sigil  (decode_field_names l) pos sigil getsets)) 
      | decode_type (_, Const (@{const_name TSum}, _) $ variants, cT, _) =
            USum (cT, variants)
      | decode_type (_, Const (@{const_name TProduct}, _) $ _ $ _, cT, _) =
            UProduct cT
      | decode_type (pos, t, _, _) =
            raise TERM (report pos ^ "unrecognised type", [t]);

    val uvals = map decode_type tymap |> rm_redundancy
   in
    uvals
   end : uval list;
\<close>
end
