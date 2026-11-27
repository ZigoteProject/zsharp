(* Reuse tokens: a cell built in a token's memory is built over nothing that's still in the heap.

   Ownership.v's cells are numbered as they're made, and a number is never used again, so that
   file can't say what reuse in place could break: two cells in the same memory. Here every
   cell has an address as well. A new cell takes a fresh address, or its token's when the token
   has one; a drop that finds the last reference keeps the cell's address as the token. The
   machine doesn't check a token before it builds in it.

   Proved, for a program the judgment accepts: no two cells in the heap have the same address
   ([distinct]), so with [safe] every read finds the cell it was made for; and nothing in this
   machine reads, dups or drops a freed cell either ([asafe]).

   One frame: a token held across a call isn't covered (Calls.v has calls, without addresses).
   A drop that keeps a token drops every field; Z#'s also moves the fields a match still uses
   out of the cell, which isn't here. *)
From Stdlib Require Import List Arith Lia.
Import ListNotations.
From Proofs Require Import Ownership.

Record acfg := A { base : cfg; ad : loc -> nat; nxa : nat; tok : var -> option nat }.

(* the statements that make no cell and keep no token *)
Definition plain (k : list stmt) : Prop :=
  match k with
  | SField _ _ _ :: _ | SDup _ :: _ | SDrop _ :: _ | SRead _ :: _ | SIf _ _ :: _
  | SFree _ :: _ => True
  | _ => False
  end.

Inductive astep : acfg -> acfg -> Prop :=
| as_pend b b' d na tk : pend b <> [] -> step b b' -> astep (A b d na tk) (A b' d na tk)
| as_other b b' d na tk :
    pend b = [] -> plain (code b) -> step b b' -> astep (A b d na tk) (A b' d na tk)
| as_new H n e x ys k d na tk :
    astep (A (Cfg H n e [] (SNew x ys :: k)) d na tk)
          (A (Cfg (upd H n (Some (1, map e ys))) (S n) (upd e x n) [] k) (upd d n na) (S na) tk)
| as_newat_tok H n e x t ys k d na tk a :
    tk t = Some a ->
    astep (A (Cfg H n e [] (SNewAt x t ys :: k)) d na tk)
          (A (Cfg (upd H n (Some (1, map e ys))) (S n) (upd e x n) [] k) (upd d n a) na tk)
| as_newat_null H n e x t ys k d na tk :
    tk t = None ->
    astep (A (Cfg H n e [] (SNewAt x t ys :: k)) d na tk)
          (A (Cfg (upd H n (Some (1, map e ys))) (S n) (upd e x n) [] k) (upd d n na) (S na) tk)
| as_droptok_u H n e x t k fs d na tk :
    H (e x) = Some (1, fs) ->
    astep (A (Cfg H n e [] (SDropTok x t :: k)) d na tk)
          (A (Cfg (upd H (e x) None) n e fs k) d na (upd tk t (Some (d (e x)))))
| as_droptok_s H n e x t k c fs d na tk :
    H (e x) = Some (S (S c), fs) ->
    astep (A (Cfg H n e [] (SDropTok x t :: k)) d na tk)
          (A (Cfg (upd H (e x) (Some (S c, fs))) n e [] k) d na (upd tk t None)).

Inductive asteps : acfg -> acfg -> Prop :=
| asteps_refl a : asteps a a
| asteps_step a1 a2 a3 : asteps a1 a2 -> astep a2 a3 -> asteps a1 a3.

Definition ainit (p : list stmt) : acfg := A (init p) (fun _ => 0) 0 (fun _ => None).

(* it's Ownership.v's machine, with addresses beside it *)
Lemma astep_step a a' : astep a a' -> step (base a) (base a').
Proof. destruct 1; simpl; auto; econstructor; eauto. Qed.

Lemma asteps_steps a a' : asteps a a' -> steps (base a) (base a').
Proof. induction 1; [constructor|econstructor; eauto using astep_step]. Qed.

(* ---- what holds of the addresses *)

Record ainv (s : cstate) (a : acfg) : Prop := AInv {
  (* two cells in the heap are in different memory *)
  a_cell : forall i j, hp (base a) i <> None -> hp (base a) j <> None -> ad a i = ad a j -> i = j;
  (* a token not yet used holds no cell's memory, nor another such token's *)
  a_tok : forall t x i, ct s t = true -> tok a t = Some x -> hp (base a) i <> None -> ad a i <> x;
  a_toks : forall t t' x, ct s t = true -> ct s t' = true ->
                          tok a t = Some x -> tok a t' = Some x -> t = t';
  a_lim1 : forall i, hp (base a) i <> None -> ad a i < nxa a;
  a_lim2 : forall t x, ct s t = true -> tok a t = Some x -> x < nxa a
}.

Ltac upds :=
  repeat match goal with
  | H : context [upd _ ?a _ ?b] |- _ =>
    first [rewrite upd_eq in H | rewrite upd_neq in H by (assumption || congruence || lia)]
  | |- context [upd _ ?a _ ?b] =>
    first [rewrite upd_eq | rewrite upd_neq by (assumption || congruence || lia)]
  end.

(* fewer cells and fewer tokens keep it *)
Lemma ainv_mono s s' b b' d na tk :
  ainv s (A b d na tk) ->
  (forall i, hp b' i <> None -> hp b i <> None) ->
  (forall t, ct s' t = true -> ct s t = true) ->
  ainv s' (A b' d na tk).
Proof.
  intros [c1 c2 c3 c4 c5] Hh Ht. simpl in *. constructor; simpl; eauto.
Qed.

Lemma step_keep c c' :
  step c c' -> nxt c' = nxt c -> forall j, hp c' j <> None -> hp c j <> None.
Proof.
  destruct 1; simpl; intros Hn j Hi; try assumption; try lia;
    match type of Hi with
    | upd _ ?a _ j <> _ =>
      destruct (Nat.eq_dec j a) as [->|Hne];
        [congruence|rewrite upd_neq in Hi by assumption; assumption]
    end.
Qed.

Lemma step_nxt_pend c c' : step c c' -> pend c <> [] -> nxt c' = nxt c.
Proof. destruct 1; simpl; intros; congruence. Qed.

Lemma step_nxt_plain c c' : step c c' -> plain (code c) -> nxt c' = nxt c.
Proof. destruct 1; simpl; intros; try reflexivity; contradiction. Qed.

(* a cell made at number n, in memory nobody has *)
Lemma ainv_new s s' H n e e' p p' k k' v d na tk a0 :
  ainv s (A (Cfg H n e p k) d na tk) -> H n = None ->
  (forall t, ct s' t = true -> ct s t = true) ->
  (forall i, H i <> None -> d i <> a0) ->
  (forall t x, ct s' t = true -> tk t = Some x -> x <> a0) ->
  forall na', na <= na' -> a0 < na' ->
  ainv s' (A (Cfg (upd H n (Some v)) (S n) e' p' k') (upd d n a0) na' tk).
Proof.
  intros [c1 c2 c3 c4 c5] Hn Ht Hc Hk na' Hle Hlt. simpl in *. constructor; simpl.
  - intros i j Hi Hj Had.
    destruct (Nat.eq_dec i n) as [->|Hi'], (Nat.eq_dec j n) as [->|Hj']; upds; auto.
    + exfalso. apply (Hc j); auto.
    + exfalso. apply (Hc i); auto.
  - intros t x i Hct Htk Hi. destruct (Nat.eq_dec i n) as [->|Hi']; upds.
    + intros ->. eapply Hk; eauto.
    + eauto.
  - eauto.
  - intros i Hi. destruct (Nat.eq_dec i n) as [->|Hi']; upds; [assumption|].
    specialize (c4 i Hi). lia.
  - intros t x Hct Htk. specialize (c5 t x (Ht t Hct) Htk). lia.
Qed.

Theorem apres sg s vs a a' r :
  inv ext0 s vs (base a) -> chk sg s (code (base a)) r -> ainv s a -> astep a a' ->
  exists s' vs' r', inv ext0 s' vs' (base a') /\ chk sg s' (code (base a')) r' /\ le r' r /\
                    cbor s' = cbor s /\ ainv s' a'.
Proof.
  intros I Hk AI Hs. pose proof (astep_step _ _ Hs) as Hb.
  destruct (pres sg ext0 _ _ _ _ _ I Hk Hb) as (s' & vs' & r' & I' & Hk' & Hle & Hbor & _ & Hct).
  exists s', vs', r'. split; [assumption|split; [assumption|split; [assumption|split; [assumption|]]]].
  destruct Hs; simpl in *.
  - (* a pending drop *)
    apply (ainv_mono s s' b b' d na tk AI).
    + apply step_keep; [assumption|apply step_nxt_pend; assumption].
    + intros t. unfold ctnext in Hct. destruct (pend b); [congruence|]. rewrite Hct. auto.
  - (* a statement that makes no cell and keeps no token *)
    apply (ainv_mono s s' b b' d na tk AI).
    + apply step_keep; [assumption|apply step_nxt_plain; assumption].
    + intros t0. unfold ctnext in Hct. rewrite H in Hct. rewrite Hct.
      destruct (code b) as [|[] ?]; simpl in *; try contradiction; auto.
      unfold upd. destruct (Nat.eqb t0 t); [discriminate|auto].
  - (* a new cell, in fresh memory *)
    unfold ctnext in Hct. simpl in Hct.
    assert (H n = None) as Hn by (apply (i_bound _ _ _ _ I); simpl; lia).
    apply (ainv_new s s' H n e _ [] _ _ _ _ d na tk na AI Hn); try lia.
    + intros t. rewrite Hct. auto.
    + intros i Hi. pose proof (a_lim1 _ _ AI i Hi). simpl in *. lia.
    + intros t y Ht Htk. rewrite Hct in Ht. pose proof (a_lim2 _ _ AI t y Ht Htk). simpl in *. lia.
  - (* a new cell, in its token's memory *)
    unfold ctnext in Hct. simpl in Hct.
    assert (H n = None) as Hn by (apply (i_bound _ _ _ _ I); simpl; lia).
    assert (ct s t = true) as Hlive by (inversion Hk; assumption).
    apply (ainv_new s s' H n e _ [] _ _ _ _ d na tk a AI Hn); try lia.
    + intros t0. rewrite Hct. unfold upd. destruct (Nat.eqb t0 t); [discriminate|auto].
    + intros i Hi. exact (a_tok _ _ AI t a i Hlive H0 Hi).
    + intros t0 y Ht0 Htk ->. rewrite Hct in Ht0. unfold upd in Ht0.
      destruct (Nat.eqb_spec t0 t) as [Heq|Hne]; [discriminate|].
      apply Hne. exact (a_toks _ _ AI t0 t a Ht0 Hlive Htk H0).
    + exact (a_lim2 _ _ AI t a Hlive H0).
  - (* a new cell, its token empty *)
    unfold ctnext in Hct. simpl in Hct.
    assert (H n = None) as Hn by (apply (i_bound _ _ _ _ I); simpl; lia).
    apply (ainv_new s s' H n e _ [] _ _ _ _ d na tk na AI Hn); try lia.
    + intros t0. rewrite Hct. unfold upd. destruct (Nat.eqb t0 t); [discriminate|auto].
    + intros i Hi. pose proof (a_lim1 _ _ AI i Hi). simpl in *. lia.
    + intros t0 y Ht0 Htk. rewrite Hct in Ht0. unfold upd in Ht0.
      destruct (Nat.eqb_spec t0 t) as [Heq|Hne]; [discriminate|].
      pose proof (a_lim2 _ _ AI t0 y Ht0 Htk). simpl in *. lia.
  - (* the last reference dropped: the cell's memory is the token *)
    unfold ctnext in Hct. simpl in Hct.
    destruct AI as [c1 c2 c3 c4 c5]. simpl in *.
    assert (H (e x) <> None) as Hx by congruence.
    assert (forall i, upd H (e x) None i <> None -> i <> e x /\ H i <> None) as Hp.
    { intros i Hi. destruct (Nat.eq_dec i (e x)) as [->|Hne]; upds; [congruence|auto]. }
    constructor; simpl.
    + intros i j Hi Hj. apply Hp in Hi. apply Hp in Hj. apply c1; tauto.
    + intros t0 y i Ht0 Htk Hi. apply Hp in Hi. destruct Hi as [Hi1 Hi2]. rewrite Hct in Ht0.
      destruct (Nat.eq_dec t0 t) as [->|Hne]; upds.
      * injection Htk as <-. intros Had. apply Hi1. apply c1; assumption.
      * eauto.
    + intros t0 t1 y Ht0 Ht1 Htk0 Htk1. rewrite Hct in Ht0, Ht1.
      destruct (Nat.eq_dec t0 t) as [->|Hne0], (Nat.eq_dec t1 t) as [->|Hne1]; upds; auto.
      * injection Htk0 as <-. exfalso. exact (c2 t1 _ (e x) Ht1 Htk1 Hx eq_refl).
      * injection Htk1 as <-. exfalso. exact (c2 t0 _ (e x) Ht0 Htk0 Hx eq_refl).
      * eauto.
    + intros i Hi. apply Hp in Hi. apply c4. tauto.
    + intros t0 y Ht0 Htk. rewrite Hct in Ht0.
      destruct (Nat.eq_dec t0 t) as [->|Hne]; upds; [injection Htk as <-; auto|eauto].
  - (* a reference dropped, others left: the token is empty *)
    unfold ctnext in Hct. simpl in Hct.
    destruct AI as [c1 c2 c3 c4 c5]. simpl in *.
    assert (forall i, upd H (e x) (Some (S c, fs)) i <> None -> H i <> None) as Hp.
    { intros i Hi. destruct (Nat.eq_dec i (e x)) as [->|Hne]; upds; [congruence|auto]. }
    constructor; simpl.
    + intros i j Hi Hj. apply c1; auto.
    + intros t0 y i Ht0 Htk Hi. rewrite Hct in Ht0.
      destruct (Nat.eq_dec t0 t) as [->|Hne]; upds; [discriminate|eauto].
    + intros t0 t1 y Ht0 Ht1 Htk0 Htk1. rewrite Hct in Ht0, Ht1.
      destruct (Nat.eq_dec t0 t) as [->|Hne0]; upds; [discriminate|].
      destruct (Nat.eq_dec t1 t) as [->|Hne1]; upds; [discriminate|eauto].
    + intros i Hi. auto.
    + intros t0 y Ht0 Htk. rewrite Hct in Ht0.
      destruct (Nat.eq_dec t0 t) as [->|Hne]; upds; [discriminate|eauto].
Qed.

Lemma areach sg p r a :
  chk sg s0 p r -> final r -> asteps (ainit p) a ->
  exists s vs r', inv ext0 s vs (base a) /\ chk sg s (code (base a)) r' /\ ainv s a.
Proof.
  intros Hc Hf Hs. remember (ainit p) as a0 eqn:E0.
  induction Hs as [a|a1 a2 a3 Hs IH Hst]; subst.
  - exists s0, [], r. split; [|split; [assumption|]].
    + constructor; unfold tot, hsum, ext0; simpl; intros; try discriminate; try lia; try reflexivity.
      constructor.
    + constructor; simpl; intros; try discriminate; try congruence.
  - destruct (IH eq_refl) as (s & vs & r' & I & Hk & AI).
    destruct (apres sg _ _ _ _ _ I Hk AI Hst) as (s' & vs' & r'' & I' & Hk' & _ & _ & AI').
    exists s', vs', r''. auto.
Qed.

(* no two cells in the heap are in the same memory *)
Theorem distinct sg p r a :
  chk sg s0 p r -> final r -> asteps (ainit p) a ->
  forall i j, hp (base a) i <> None -> hp (base a) j <> None -> ad a i = ad a j -> i = j.
Proof.
  intros Hc Hf Hs. destruct (areach _ _ _ _ Hc Hf Hs) as (s & vs & r' & _ & _ & AI).
  exact (a_cell _ _ AI).
Qed.

(* and this machine, as Ownership.v's, never touches a freed cell *)
Theorem asafe sg p r a :
  chk sg s0 p r -> final r -> asteps (ainit p) a -> ~ faults (base a).
Proof.
  intros Hc Hf Hs. exact (safe sg p r _ Hc Hf (asteps_steps _ _ Hs)).
Qed.

Print Assumptions distinct.
Print Assumptions asafe.
