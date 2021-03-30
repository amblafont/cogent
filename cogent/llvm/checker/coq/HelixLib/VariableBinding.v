(* Taken from Helix's LLVMGen.VariableBinding.v *)

(** * Identifiers and freshness frames

  Each code generation creates a "freshness frame": the interval (for each
  kind of variable) between the initial [IRState] and the resulting one after
  generation of the code.

  We will need to reason about which frame different variables belong to.
  This file provide some generic tools to this end that will be used to 
  derive more specific facts in respectively [LidBound] and [BidBound]. 

  Important definition:
  - [state_bound s id] : the variable [id] is "below" [s], i.e. [s] will never be
    able to generate [s] from now on.
  - [state_bound_between s1 s2 id] : the variable [id] has been generated by a state
    situated in the frame [s1;s2].

  Note: in the proof of the Helix compiler, only [state_bound_between] is used.
  Indeed, [state_bound] is too coarse an invariant to support reasoning about the
  sequence due to the subcomponent being compiled in the reversed order they are
  generated.

*)

Require Import CoLoR.Util.Nat.NatUtil.

Require Import HelixLib.Correctness_Prelude.
Require Import HelixLib.IdLemmas.

Import ListNotations.

Set Implicit Arguments.
Set Strict Implicit.

(** Reasoning about when identifiers are bound in certain states *)
Section StateBound.
  Variable count :  IRState -> nat.
  Variable gen : string -> cerr raw_id.

  (* TODO: Injective is sort of a lie... Is there a better thing to call this? *)
  Definition count_gen_injective : Prop
    := forall s1 s1' s2 s2' name1 name2 id1 id2,
      inr (s1', id1) ≡ gen name1 s1 ->
      inr (s2', id2) ≡ gen name2 s2 ->
      count s1 ≢ count s2 ->
      is_correct_prefix name1 ->
      is_correct_prefix name2 ->
      id1 ≢ id2.

  Definition count_gen_mono : Prop
    := forall s1 s2 name id,
      inr (s2, id) ≡ gen name s1 ->
      (count s2 > count s1)%nat.

  Variable INJ : count_gen_injective.
  Variable MONO : count_gen_mono.

  (* Says whether or not a variable has been generated by an earlier IRState,

    I.e., this holds when `id` can be generated using `gen` from a
    state with an earlier counter. The intuition is that `id` ends
    with a number that is *lower* than the count for the current
    state.
  *)
  Definition state_bound (s : IRState) (id : raw_id) : Prop
    := exists name s' s'',
      is_correct_prefix name /\
      (count s' < count s)%nat /\
      inr (s'', id) ≡ gen name s'.

  Definition state_bound_between (s1 s2 : IRState) (id : raw_id) : Prop
    := exists name s' s'',
      is_correct_prefix name /\
      (count s' < count s2)%nat /\
      count s' ≥ count s1 /\
      inr (s'', id) ≡ gen name s'.

  Lemma state_bound_fresh :
    forall (s1 s2 : IRState) (id id' : raw_id),
      state_bound s1 id ->
      state_bound_between s1 s2 id' ->
      id ≢ id'.
  Admitted.

  Lemma state_bound_fresh' :
    forall (s1 s2 s3 : IRState) (id id' : raw_id),
      state_bound s1 id ->
      (count s1 <= count s2)%nat ->
      state_bound_between s2 s3 id' ->
      id ≢ id'.
  Admitted.

  Lemma state_bound_bound_between :
    forall (s1 s2 : IRState) (bid : block_id),
      state_bound s2 bid ->
      ~(state_bound s1 bid) ->
      state_bound_between s1 s2 bid.
  Admitted.

  Lemma state_bound_before_not_bound_between :
    forall (s s1 s2 : IRState) (bid : block_id),
      state_bound s bid ->
      (count s <= count s1)%nat ->
      ~ (state_bound_between s1 s2 bid).
  Admitted.

  Lemma state_bound_mono :
    forall s1 s2 bid,
      state_bound s1 bid ->
      (count s1 <= count s2)%nat ->
      state_bound s2 bid.
  Admitted.

  Lemma state_bound_between_shrink :
    forall s1 s2 s1' s2' id,
      state_bound_between s1 s2 id ->
      (count s1' <= count s1)%nat ->
      (count s2' >= count s2)%nat ->
      state_bound_between s1' s2' id.
  Admitted.

  Lemma all_state_bound_between_shrink :
    forall s1 s2 s1' s2' ids,
      Forall (state_bound_between s1 s2) ids ->
      (count s1' <= count s1)%nat ->
      (count s2' >= count s2)%nat ->
      Forall (state_bound_between s1' s2') ids.
  Admitted.
  
  Lemma state_bound_between_separate :
    forall s1 s2 s3 s4 id id',
      state_bound_between s1 s2 id ->
      state_bound_between s3 s4 id' ->
      (count s2 <= count s3)%nat ->
      id ≢ id'.
  Admitted.

  Lemma state_bound_between_id_separate :
    forall s1 s2 s3 s4 id,
      state_bound_between s1 s2 id ->
      state_bound_between s3 s4 id ->
      (count s2 <= count s3)%nat ->
      False.
  Admitted.

  Lemma not_state_bound_between_split :
    forall (s1 s2 s3 : IRState) id,
      ~ state_bound_between s1 s2 id ->
      ~ state_bound_between s2 s3 id ->
      ~ state_bound_between s1 s3 id.
  Admitted.

  Lemma gen_not_state_bound :
    forall name s1 s2 id,
      is_correct_prefix name ->
      gen name s1 ≡ inr (s2, id) ->
      ~(state_bound s1 id).
  Admitted.

Lemma gen_state_bound :
    forall name s1 s2 id,
      is_correct_prefix name ->
      gen name s1 ≡ inr (s2, id) ->
      state_bound s2 id.
  Admitted.

  Lemma gen_state_bound_between :
    forall name s1 s2 id,
      is_correct_prefix name ->
      gen name s1 ≡ inr (s2, id) ->
      state_bound_between s1 s2 id.
  Admitted.

  Lemma not_id_bound_gen_mono :
    forall name s1 s2 s' id,
      gen name s1 ≡ inr (s2, id) ->
      (count s' <= count s1)%nat ->
      is_correct_prefix name ->
      ~ (state_bound s' id).
  Admitted.

  Lemma state_bound_between_disjoint_neq :
    forall x y s1 s2 s3 s4,
      state_bound_between s1 s2 x ->
      state_bound_between s3 s4 y ->
      (count s2 <= count s3)%nat ->
      x ≢ y.
  Admitted.

  Lemma state_bound_between_list_disjoint :
    forall l1 l2 s1 s2 s3 s4,
      Forall (state_bound_between s1 s2) l1 ->
      Forall (state_bound_between s3 s4) l2 ->
      (count s2 <= count s3)%nat ->
      Coqlib.list_disjoint l1 l2.
  Admitted.

  Lemma state_bound_between_disjoint_norepet :
    forall l1 l2 s1 s2 s3 s4,
      Coqlib.list_norepet l1 ->
      Coqlib.list_norepet l2 ->
      Forall (state_bound_between s1 s2) l1 ->
      Forall (state_bound_between s3 s4) l2 ->
      (count s2 <= count s3)%nat ->
      Coqlib.list_norepet (l1 ++ l2).
  Admitted.

  Lemma state_bound_before_bound_between :
    forall s1 s2 id,
      state_bound s1 id ->
      count s1 <= count s2 ->
      exists s0,
        state_bound_between s0 s2 id.
  Admitted.

End StateBound.