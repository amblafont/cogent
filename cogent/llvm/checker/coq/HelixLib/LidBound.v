(* Taken from Helix's LLVMGen.LidBound *)

(** * Local identifiers and freshness frames

  Specialization of [VariableBinding] to local identifiers.
*)

Require Import HelixLib.Correctness_Prelude.
Require Import HelixLib.VariableBinding.
Require Import HelixLib.IdLemmas.
Require Import HelixLib.StateCounters.
Set Implicit Arguments.
Set Strict Implicit.

Section LidBound.  
  (* Says that a given local id would have been generated by an earlier IRState *)
  Definition lid_bound (s : IRState) (lid: local_id) : Prop
    := state_bound local_count incLocalNamed s lid.

  Definition lid_bound_between (s1 s2 : IRState) (lid : local_id) : Prop
    := state_bound_between local_count incLocalNamed s1 s2 lid.

  Lemma incLocalNamed_count_gen_injective :
    count_gen_injective local_count incLocalNamed.
  Admitted.

  Lemma lid_bound_fresh :
    ∀ (s1 s2 : IRState) (id1 id2 : local_id),
      lid_bound s1 id1 →
      lid_bound_between s1 s2 id2 → id1 ≢ id2.
  Admitted.

  Lemma incLocalNamed_count_gen_mono :
    count_gen_mono local_count incLocalNamed.
  Admitted.

  Lemma lid_bound_incLocalNamed :
    forall name s1 s2 id,
      is_correct_prefix name ->
      incLocalNamed name s1 ≡ inr (s2, id) ->
      lid_bound s2 id.
  Admitted.

  Lemma not_lid_bound_incLocalNamed :
    forall name s1 s2 id,
      is_correct_prefix name ->
      incLocalNamed name s1 ≡ inr (s2, id) ->
      ~ lid_bound s1 id.
  Admitted.

  Lemma lid_bound_between_incLocalNamed :
    forall name s1 s2 id,
      is_correct_prefix name ->
      incLocalNamed name s1 ≡ inr (s2, id) ->
      lid_bound_between s1 s2 id.
  Admitted.

  Lemma not_lid_bound_incLocal :
    forall s1 s2 id,
      incLocal s1 ≡ inr (s2, id) ->
      ~ lid_bound s1 id.
  Admitted.

  Lemma lid_bound_between_incLocal :
    forall s1 s2 id,
      incLocal s1 ≡ inr (s2, id) ->
      lid_bound_between s1 s2 id.
  Admitted.

  Lemma lid_bound_incBlockNamed_mono :
    forall name s1 s2 bid bid',
      lid_bound s1 bid ->
      incBlockNamed name s1 ≡ inr (s2, bid') ->
      lid_bound s2 bid.
  Admitted.

  (* TODO: typeclasses for these mono lemmas to make automation easier? *)
  Lemma lid_bound_incVoid_mono :
    forall s1 s2 bid bid',
      lid_bound s1 bid ->
      incVoid s1 ≡ inr (s2, bid') ->
      lid_bound s2 bid.
  Admitted.

  Lemma lid_bound_incLocal_mono :
    forall s1 s2 bid bid',
      lid_bound s1 bid ->
      incLocal s1 ≡ inr (s2, bid') ->
      lid_bound s2 bid.
  Admitted.

  Lemma incLocalNamed_lid_bound :
    forall s1 s2 id name,
      is_correct_prefix name ->
      incLocalNamed name s1 ≡ inr (s2, id) ->
      lid_bound s2 id.
  Admitted.

  Lemma incLocal_lid_bound :
    forall s1 s2 id,
      incLocal s1 ≡ inr (s2, id) ->
      lid_bound s2 id.
  Admitted.

  Lemma lid_bound_earlier :
    forall (s1 s2 s3 : IRState) (id1 id2 : local_id),
      lid_bound s1 id1 ->
      lid_bound_between s2 s3 id2 ->
      s1 <<= s2 ->
      id1 ≢ id2.
  Admitted.

  Lemma lid_bound_before :
    forall s1 s2 x,
      lid_bound s1 x ->
      s1 <<= s2 ->
      lid_bound s2 x.
  Admitted.

  Lemma lid_bound_count :
    forall s1 s2 pref,
      is_correct_prefix pref ->
      (local_count s2 < local_count s1)%nat ->
      lid_bound s1 (Name (pref @@ string_of_nat (local_count s2))).
  Admitted.

  Lemma lid_bound_between_count :
    forall s1 s2 s pref,
      is_correct_prefix pref ->
      (local_count s1 <= local_count s)%nat ->
      (local_count s < local_count s2)%nat ->
      lid_bound_between s1 s2 (Name (pref @@ string_of_nat (local_count s))).
  Admitted.

  Lemma lid_bound_before_bound_between :
    forall s1 s2 id,
      lid_bound s1 id ->
      s1 <<= s2 ->
      exists s0,
        lid_bound_between s0 s2 id.
  Admitted.

  Lemma lid_bound_count_incLocalNamed :
    forall (s1 s2 s3 : IRState) (pref : string) (id : raw_id),
      is_correct_prefix pref ->
      (local_count s2 < local_count s1)%nat ->
      incLocalNamed pref s2 ≡ inr (s3, id) ->
      lid_bound s1 id.
  Admitted.

  Lemma lid_bound_count_incLocal :
    forall (s1 s2 s3 : IRState) (id : raw_id),
      (local_count s2 < local_count s1)%nat ->
      incLocal s2 ≡ inr (s3, id) ->
      lid_bound s1 id.
  Admitted.

End LidBound.

Ltac solve_lid_bound :=
  solve
    [ eauto
    | eapply incLocal_lid_bound; cbn; eauto
    | eapply incLocalNamed_lid_bound; [solve_prefix | cbn; eauto]
    | eapply lid_bound_count; [solve_prefix | solve_local_count]
    | eapply lid_bound_before; [solve [eauto] | solve_local_count]
    ].