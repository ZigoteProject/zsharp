(* The ownership check's judgment, and its soundness (docs/reports/ownership-check.md).

   A calculus of the forms that touch counts: a cell built from variables (which gives it their
   references), a field read (borrowed from the cell's holder), dup, drop, a read that takes
   nothing, and a branch. The judgment [chk] is the walk of Core.Check.owned: n references of
   its own for each variable, the variable each is alive through, a drop for every reference on
   every path. The machine has a heap of counted cells, and a drop that frees a cell drops its
   fields.

   Proved: a checked program never reads, dups or drops a cell that was freed ([safe]), and when
   it ends the heap is empty ([no_leak]).

   Also here, for the proofs that build on this one: the statements and rules of reuse tokens
   (a drop that keeps a unique cell's memory as a token, a cell built in a token, a token
   freed) and of calls, and [ext], the references that frames waiting on a call hold, which the
   counts of this file's one frame are added to. In this file a token's statements are the
   plain ones (a drop, a new cell), and a call doesn't step.

   Checked by: proofs/check.sh *)
From Stdlib Require Import List Arith Lia.
Import ListNotations.

Definition var := nat.
Definition loc := nat.

Definition upd {A : Type} (f : nat -> A) (x : nat) (a : A) : nat -> A :=
  fun y => if Nat.eqb y x then a else f y.

Lemma upd_eq A (f : nat -> A) x a : upd f x a x = a.
Proof. unfold upd. now rewrite Nat.eqb_refl. Qed.

Lemma upd_neq A (f : nat -> A) x a y : y <> x -> upd f x a y = f y.
Proof. unfold upd. intros. destruct (Nat.eqb_spec y x); congruence. Qed.

(* ---- programs *)

Unset Elimination Schemes.
Inductive stmt :=
| SNew (x : var) (ys : list var)   (* let x = C(ys): the cell takes a reference from each y *)
| SField (x y : var) (i : nat)     (* let x = y.i: y's, until a dup *)
| SDup (x : var)
| SDrop (x : var)
| SRead (x : var)                  (* a read that takes nothing *)
| SIf (a b : list stmt)
| SDropTok (x t : var)             (* drop x; t is its cell's memory if that was the last reference *)
| SNewAt (x t : var) (ys : list var)  (* let x = C(ys), built in t's memory when t has one *)
| SFree (t : var)                  (* a token given back unused *)
| SCall (x : var) (f : nat) (args : list var).
Set Elimination Schemes.

(* ---- the judgment *)

(* cn: references of its own; cvia: the variable it's alive through; cb: bound already;
   ct: a token not yet used; cbor: a parameter the caller lends *)
Record cstate := CS {
  cn : var -> nat; cvia : var -> option var; cb : var -> bool;
  ct : var -> bool; cbor : var -> bool }.

Inductive alive (s : cstate) : var -> Prop :=
| alive_own x : cn s x > 0 -> alive s x
| alive_via x y : cvia s x = Some y -> alive s y -> alive s x
| alive_bor x : cbor s x = true -> alive s x.

Definition setn (s : cstate) x k := CS (upd (cn s) x k) (cvia s) (cb s) (ct s) (cbor s).
Definition setvia (s : cstate) x y := CS (cn s) (upd (cvia s) x (Some y)) (cb s) (ct s) (cbor s).
Definition bound (s : cstate) x := CS (cn s) (cvia s) (upd (cb s) x true) (ct s) (cbor s).
Definition sett (s : cstate) t b := CS (cn s) (cvia s) (cb s) (upd (ct s) t b) (cbor s).

Inductive takes : cstate -> list var -> cstate -> Prop :=
| takes_nil s : takes s [] s
| takes_cons s y ys s' :
    cn s y > 0 -> takes (setn s y (cn s y - 1)) ys s' -> takes s (y :: ys) s'.

(* after a branch a path may forget what it borrowed, never a reference *)
Definition le (s t : cstate) : Prop :=
  (forall v, cn s v = cn t v) /\
  (forall v u, cvia t v = Some u -> cvia s v = Some u) /\
  (forall v, cb s v = true -> cb t v = true) /\
  (forall v, ct s v = ct t v) /\
  (forall v, cbor s v = cbor t v).

(* a call's arguments: a parameter the callee owns takes a reference, one it borrows needs the
   argument alive once the others are taken *)
Inductive cargs : cstate -> list var -> list bool -> cstate -> Prop :=
| cargs_nil s : cargs s [] [] s
| cargs_own s a rest bs s' :
    cn s a > 0 -> cargs (setn s a (cn s a - 1)) rest bs s' -> cargs s (a :: rest) (false :: bs) s'
| cargs_bor s a rest bs s' :
    cargs s rest bs s' -> alive s' a -> cargs s (a :: rest) (true :: bs) s'.

Section Core.

(* the parameters each function borrows *)
Variable sg : nat -> option (list bool).
(* the references to each cell that the frames waiting on a call hold *)
Variable ext : loc -> nat.

Inductive chk : cstate -> list stmt -> cstate -> Prop :=
| chk_nil s : chk s [] s
| chk_new s x ys s1 k r :
    cb s x = false -> ~ In x ys -> takes s ys s1 ->
    chk (bound (setn s1 x 1) x) k r -> chk s (SNew x ys :: k) r
| chk_field s x y i k r :
    cb s x = false -> alive s y ->
    chk (bound (setvia s x y) x) k r -> chk s (SField x y i :: k) r
| chk_dup s x k r :
    alive s x -> chk (setn s x (cn s x + 1)) k r -> chk s (SDup x :: k) r
| chk_drop s x k r :
    cn s x > 0 -> chk (setn s x (cn s x - 1)) k r -> chk s (SDrop x :: k) r
| chk_read s x k r :
    alive s x -> chk s k r -> chk s (SRead x :: k) r
| chk_if s a b sa sb s1 k r :
    chk s a sa -> chk s b sb -> le sa s1 -> le sb s1 ->
    chk s1 k r -> chk s (SIf a b :: k) r
| chk_droptok s x t k r :
    cn s x > 0 -> ct s t = false ->
    chk (sett (setn s x (cn s x - 1)) t true) k r -> chk s (SDropTok x t :: k) r
| chk_newat s x t ys s1 k r :
    cb s x = false -> ct s t = true -> ~ In x ys -> takes s ys s1 ->
    chk (sett (bound (setn s1 x 1) x) t false) k r -> chk s (SNewAt x t ys :: k) r
| chk_free s t k r :
    ct s t = true -> chk (sett s t false) k r -> chk s (SFree t :: k) r
| chk_call s x f args bs s1 k r :
    sg f = Some bs -> cb s x = false -> cargs s args bs s1 ->
    chk (bound (setn s1 x 1) x) k r -> chk s (SCall x f args :: k) r.

Definition final (s : cstate) : Prop := (forall v, cn s v = 0) /\ (forall v, ct s v = false).

(* ---- the machine *)

Definition cell := (nat * list loc)%type.
Definition heap := loc -> option cell.

Record cfg := Cfg { hp : heap; nxt : loc; env : var -> loc; pend : list loc; code : list stmt }.

Inductive step : cfg -> cfg -> Prop :=
| st_free H n e l p k fs :
    H l = Some (1, fs) ->
    step (Cfg H n e (l :: p) k) (Cfg (upd H l None) n e (fs ++ p) k)
| st_dec H n e l p k c fs :
    H l = Some (S (S c), fs) ->
    step (Cfg H n e (l :: p) k) (Cfg (upd H l (Some (S c, fs))) n e p k)
| st_new H n e x ys k :
    step (Cfg H n e [] (SNew x ys :: k))
         (Cfg (upd H n (Some (1, map e ys))) (S n) (upd e x n) [] k)
| st_field H n e x y i k c fs l :
    H (e y) = Some (c, fs) -> nth_error fs i = Some l ->
    step (Cfg H n e [] (SField x y i :: k)) (Cfg H n (upd e x l) [] k)
| st_dup H n e x k c fs :
    H (e x) = Some (c, fs) ->
    step (Cfg H n e [] (SDup x :: k)) (Cfg (upd H (e x) (Some (S c, fs))) n e [] k)
| st_drop H n e x k :
    step (Cfg H n e [] (SDrop x :: k)) (Cfg H n e [e x] k)
| st_read H n e x k c fs :
    H (e x) = Some (c, fs) ->
    step (Cfg H n e [] (SRead x :: k)) (Cfg H n e [] k)
| st_ifa H n e a b k : step (Cfg H n e [] (SIf a b :: k)) (Cfg H n e [] (a ++ k))
| st_ifb H n e a b k : step (Cfg H n e [] (SIf a b :: k)) (Cfg H n e [] (b ++ k))
| st_droptok_u H n e x t k fs :
    H (e x) = Some (1, fs) ->
    step (Cfg H n e [] (SDropTok x t :: k)) (Cfg (upd H (e x) None) n e fs k)
| st_droptok_s H n e x t k c fs :
    H (e x) = Some (S (S c), fs) ->
    step (Cfg H n e [] (SDropTok x t :: k)) (Cfg (upd H (e x) (Some (S c, fs))) n e [] k)
| st_newat H n e x t ys k :
    step (Cfg H n e [] (SNewAt x t ys :: k))
         (Cfg (upd H n (Some (1, map e ys))) (S n) (upd e x n) [] k)
| st_freetok H n e t k : step (Cfg H n e [] (SFree t :: k)) (Cfg H n e [] k).

Inductive steps : cfg -> cfg -> Prop :=
| steps_refl c : steps c c
| steps_step c1 c2 c3 : steps c1 c2 -> step c2 c3 -> steps c1 c3.

(* the next action touches a cell that isn't in the heap *)
Definition faults (c : cfg) : Prop :=
  match pend c, code c with
  | l :: _, _ => hp c l = None
  | [], SField _ y _ :: _ => hp c (env c y) = None
  | [], SDup y :: _ => hp c (env c y) = None
  | [], SRead y :: _ => hp c (env c y) = None
  | [], SDropTok y _ :: _ => hp c (env c y) = None
  | _, _ => False
  end.

Definition init (p : list stmt) : cfg := Cfg (fun _ => None) 0 (fun _ => 0) [] p.
Definition s0 : cstate :=
  CS (fun _ => 0) (fun _ => None) (fun _ => false) (fun _ => false) (fun _ => false).

(* ---- counting *)

Definition occ (l : loc) (xs : list loc) : nat := count_occ Nat.eq_dec xs l.

(* the references the variables of vs hold to l *)
Fixpoint vcount (e : var -> loc) (cnf : var -> nat) (vs : list var) (l : loc) : nat :=
  match vs with
  | [] => 0
  | v :: vs' => (if Nat.eqb (e v) l then cnf v else 0) + vcount e cnf vs' l
  end.

(* the references the cells below n hold to l *)
Definition fcount (H : heap) (l i : loc) : nat :=
  match H i with Some (_, fs) => occ l fs | None => 0 end.

Fixpoint hsum (H : heap) (l : loc) (n : nat) : nat :=
  match n with 0 => 0 | S m => fcount H l m + hsum H l m end.

Lemma occ_app l xs ys : occ l (xs ++ ys) = occ l xs + occ l ys.
Proof. unfold occ. apply count_occ_app. Qed.

Lemma occ_in l xs : In l xs <-> occ l xs > 0.
Proof. unfold occ. apply count_occ_In. Qed.

Lemma vcount_notin e cnf vs x k l :
  ~ In x vs -> vcount e (upd cnf x k) vs l = vcount e cnf vs l.
Proof.
  induction vs as [|v vs IH]; simpl; intros Hn; [reflexivity|].
  rewrite IH by tauto. rewrite upd_neq by (intros ->; tauto). reflexivity.
Qed.

Lemma vcount_setn e cnf vs x k l :
  NoDup vs -> In x vs ->
  vcount e (upd cnf x k) vs l + (if Nat.eqb (e x) l then cnf x else 0)
  = vcount e cnf vs l + (if Nat.eqb (e x) l then k else 0).
Proof.
  induction vs as [|v vs IH]; simpl; intros Hnd Hin; [tauto|].
  inversion Hnd; subst. destruct Hin as [->|Hin].
  - rewrite upd_eq. rewrite vcount_notin by assumption. destruct (Nat.eqb (e x) l); lia.
  - rewrite upd_neq by (intros ->; tauto). specialize (IH H2 Hin). lia.
Qed.

Lemma vcount_env e cnf vs x l0 l :
  cnf x = 0 -> vcount (upd e x l0) cnf vs l = vcount e cnf vs l.
Proof.
  intros Hz. induction vs as [|v vs IH]; simpl; [reflexivity|]. rewrite IH.
  destruct (Nat.eq_dec v x) as [->|Hne].
  - rewrite Hz. destruct (Nat.eqb (upd e x l0 x) l), (Nat.eqb (e x) l); reflexivity.
  - rewrite upd_neq by assumption. reflexivity.
Qed.

Lemma vcount_pos e cnf vs v : In v vs -> cnf v > 0 -> vcount e cnf vs (e v) > 0.
Proof.
  induction vs as [|w vs IH]; simpl; intros Hin Hp; [tauto|].
  destruct Hin as [->|Hin].
  - rewrite Nat.eqb_refl. lia.
  - specialize (IH Hin Hp). lia.
Qed.

Lemma vcount_zero e cnf vs l : (forall v, cnf v = 0) -> vcount e cnf vs l = 0.
Proof.
  intros Hz. induction vs as [|v vs IH]; simpl; [reflexivity|].
  rewrite IH, Hz. destruct (Nat.eqb (e v) l); reflexivity.
Qed.

(* a variable can join the list: one with no reference counts for nothing *)
Lemma vs_add cnf vs x :
  NoDup vs -> (forall v, cnf v > 0 -> In v vs) ->
  exists vs', NoDup vs' /\ In x vs' /\ (forall v, In v vs -> In v vs') /\
              forall e l, vcount e cnf vs' l = vcount e cnf vs l.
Proof.
  intros Hnd Hall. destruct (in_dec Nat.eq_dec x vs) as [Hin|Hnin].
  - exists vs. auto.
  - exists (x :: vs). repeat split.
    + constructor; assumption.
    + simpl; auto.
    + simpl; auto.
    + intros e l. simpl. assert (cnf x = 0) as ->.
      { destruct (cnf x) eqn:E; [reflexivity|]. exfalso. apply Hnin, Hall. lia. }
      destruct (Nat.eqb (e x) l); reflexivity.
Qed.

Lemma hsum_ext H H' l n :
  (forall i, i < n -> fcount H' l i = fcount H l i) -> hsum H' l n = hsum H l n.
Proof.
  induction n as [|n IH]; simpl; intros Hx; [reflexivity|].
  rewrite Hx by lia. rewrite IH; [reflexivity|]. intros; apply Hx; lia.
Qed.

Lemma hsum_upd H H' l n i0 :
  i0 < n -> (forall i, i <> i0 -> fcount H' l i = fcount H l i) ->
  hsum H' l n + fcount H l i0 = hsum H l n + fcount H' l i0.
Proof.
  induction n as [|n IH]; simpl; intros Hlt Hx; [lia|].
  destruct (Nat.eq_dec i0 n) as [->|Hne].
  - rewrite (hsum_ext H H' l n); [lia|]. intros; apply Hx; lia.
  - rewrite Hx by lia. assert (i0 < n) as Hlt' by lia. specialize (IH Hlt' Hx). lia.
Qed.

Lemma hsum_pos H l n : hsum H l n > 0 -> exists i, i < n /\ fcount H l i > 0.
Proof.
  induction n as [|n IH]; simpl; intros Hp; [lia|].
  destruct (fcount H l n) eqn:E.
  - destruct IH as [i [Hi Hf]]; [lia|]. exists i. split; [lia|assumption].
  - exists n. split; lia.
Qed.

Lemma hsum_in H l n i c fs : i < n -> H i = Some (c, fs) -> In l fs -> hsum H l n > 0.
Proof.
  induction n as [|n IH]; simpl; intros Hlt Hi Hin; [lia|].
  destruct (Nat.eq_dec i n) as [->|Hne].
  - unfold fcount at 1. rewrite Hi. apply occ_in in Hin. lia.
  - assert (hsum H l n > 0) by (apply IH; [lia|assumption|assumption]). lia.
Qed.

Lemma occ_cons l' l p : occ l' (l :: p) = (if Nat.eqb l l' then 1 else 0) + occ l' p.
Proof.
  unfold occ. simpl. destruct (Nat.eq_dec l l'), (Nat.eqb_spec l l'); try congruence; lia.
Qed.

Ltac cases :=
  repeat match goal with
  | |- context [Nat.eqb ?a ?b] => destruct (Nat.eqb_spec a b)
  | H : context [Nat.eqb ?a ?b] |- _ => destruct (Nat.eqb_spec a b)
  end.

(* ---- the judgment's own lemmas *)

Lemma takes_same s ys s' :
  takes s ys s' -> cvia s' = cvia s /\ cb s' = cb s /\ ct s' = ct s /\ cbor s' = cbor s.
Proof. induction 1; simpl in *; auto. Qed.

Lemma cargs_same s args bs s' :
  cargs s args bs s' -> cvia s' = cvia s /\ cb s' = cb s /\ ct s' = ct s /\ cbor s' = cbor s.
Proof. induction 1; simpl in *; auto. Qed.

Lemma cargs_le s args bs s' : cargs s args bs s' -> forall v, cn s' v <= cn s v.
Proof.
  induction 1 as [s|s a rest bs s' Ha Hc IH|s a rest bs s' Hc IH Ha]; intros v; [lia| |apply IH].
  specialize (IH v). simpl in IH. unfold upd in IH. cases; subst; lia.
Qed.

Lemma takes_le s ys s' : takes s ys s' -> forall v, cn s' v <= cn s v.
Proof.
  induction 1 as [s|s y ys s' Hy Ht IH]; intros v; [lia|].
  specialize (IH v). simpl in IH. unfold upd in IH. cases; subst; lia.
Qed.

Lemma takes_count e vs s ys s' :
  takes s ys s' -> NoDup vs -> (forall v, cn s v > 0 -> In v vs) ->
  forall l, vcount e (cn s') vs l + occ l (map e ys) = vcount e (cn s) vs l.
Proof.
  induction 1 as [s|s y ys s' Hy Ht IH]; intros Hnd Hall l.
  - unfold occ; simpl; lia.
  - assert (In y vs) as Hin by auto.
    assert (forall v, cn (setn s y (cn s y - 1)) v > 0 -> In v vs) as Hall'.
    { intros v. simpl. unfold upd. cases; subst; auto. }
    specialize (IH Hnd Hall' l). simpl in IH.
    pose proof (vcount_setn e (cn s) vs y (cn s y - 1) l Hnd Hin) as E.
    simpl map. rewrite occ_cons. cases; lia.
Qed.

Lemma le_refl s : le s s.
Proof. unfold le; auto. Qed.

Lemma le_trans s t u : le s t -> le t u -> le s u.
Proof.
  unfold le. intros (A & B & C & D & E) (A' & B' & C' & D' & E'). repeat split; intros.
  - rewrite A. apply A'.
  - auto.
  - auto.
  - rewrite D. apply D'.
  - rewrite E. apply E'.
Qed.

Lemma le_setn s t x k : le s t -> le (setn s x k) (setn t x k).
Proof.
  unfold le. intros (A & B & C & D & E). simpl. repeat split; auto.
  intros v. unfold upd. cases; auto.
Qed.

Lemma le_setvia s t x y : le s t -> le (setvia s x y) (setvia t x y).
Proof.
  unfold le. intros (A & B & C & D & E). simpl. repeat split; auto.
  intros v u. unfold upd. cases; auto.
Qed.

Lemma le_bound s t x : le s t -> le (bound s x) (bound t x).
Proof.
  unfold le. intros (A & B & C & D & E). simpl. repeat split; auto.
  intros v. unfold upd. cases; auto.
Qed.

Lemma le_sett s t x b : le s t -> le (sett s x b) (sett t x b).
Proof.
  unfold le. intros (A & B & C & D & E). simpl. repeat split; auto.
  intros v. unfold upd. cases; auto.
Qed.

Lemma alive_le s t x : le s t -> alive t x -> alive s x.
Proof.
  intros (A & B & C & D & E). induction 1.
  - apply alive_own. rewrite A. assumption.
  - eapply alive_via; eauto.
  - apply alive_bor. rewrite E. assumption.
Qed.

Lemma cargs_mono t args bs t' :
  cargs t args bs t' -> forall s, le s t -> exists s', cargs s args bs s' /\ le s' t'.
Proof.
  induction 1 as [t|t a rest bs t' Ha Hc IH|t a rest bs t' Hc IH Ha]; intros s Hle.
  - exists s. split; [constructor|assumption].
  - pose proof Hle as (A & _).
    destruct (IH (setn s a (cn s a - 1))) as (s' & Hc' & Hle').
    { rewrite (A a). apply le_setn. assumption. }
    exists s'. split; [|assumption]. constructor; [rewrite A; assumption|assumption].
  - destruct (IH s Hle) as (s' & Hc' & Hle').
    exists s'. split; [|assumption]. constructor; [assumption|eapply alive_le; eauto].
Qed.

Lemma takes_mono t ys t' : takes t ys t' -> forall s, le s t -> exists s', takes s ys s' /\ le s' t'.
Proof.
  induction 1 as [t|t y ys t' Hy Ht IH]; intros s Hle.
  - exists s. split; [constructor|assumption].
  - pose proof Hle as (A & _).
    destruct (IH (setn s y (cn s y - 1))) as (s' & Ht' & Hle').
    { rewrite (A y). apply le_setn. assumption. }
    exists s'. split; [|assumption]. constructor; [rewrite A; assumption|assumption].
Qed.

Lemma chk_mono t k r : chk t k r -> forall s, le s t -> exists r', chk s k r' /\ le r' r.
Proof.
  induction 1; intros s' Hle; pose proof Hle as (A & B & C & D & Eb).
  - exists s'. split; [constructor|assumption].
  - destruct (takes_mono _ _ _ H1 _ Hle) as (s1' & Ht & Hle1).
    destruct (IHchk (bound (setn s1' x 1) x)) as (r' & Hc & Hr).
    { apply le_bound, le_setn. assumption. }
    exists r'. split; [|assumption]. econstructor; eauto.
    destruct (cb s' x) eqn:E; [|reflexivity]. apply C in E. congruence.
  - destruct (IHchk (bound (setvia s' x y) x)) as (r' & Hc & Hr).
    { apply le_bound, le_setvia. assumption. }
    exists r'. split; [|assumption]. econstructor; eauto.
    + destruct (cb s' x) eqn:E; [|reflexivity]. apply C in E. congruence.
    + eapply alive_le; eauto.
  - destruct (IHchk (setn s' x (cn s' x + 1))) as (r' & Hc & Hr).
    { rewrite (A x). apply le_setn. assumption. }
    exists r'. split; [|assumption]. constructor; [eapply alive_le; eauto|assumption].
  - destruct (IHchk (setn s' x (cn s' x - 1))) as (r' & Hc & Hr).
    { rewrite (A x). apply le_setn. assumption. }
    exists r'. split; [|assumption]. constructor; [rewrite A; assumption|assumption].
  - destruct (IHchk s' Hle) as (r' & Hc & Hr).
    exists r'. split; [|assumption]. constructor; [eapply alive_le; eauto|assumption].
  - destruct (IHchk1 s' Hle) as (sa' & Hca & Hla).
    destruct (IHchk2 s' Hle) as (sb' & Hcb & Hlb).
    exists r. split; [|apply le_refl].
    apply (chk_if s' a b sa' sb' s1 k r); auto; eapply le_trans; eauto.
  - destruct (IHchk (sett (setn s' x (cn s' x - 1)) t true)) as (r' & Hc & Hr).
    { rewrite (A x). apply le_sett, le_setn. assumption. }
    exists r'. split; [|assumption].
    constructor; [rewrite A; assumption|rewrite D; assumption|assumption].
  - match goal with Ht : takes _ _ _ |- _ =>
      destruct (takes_mono _ _ _ Ht _ Hle) as (s1' & Ht' & Hle1) end.
    destruct (IHchk (sett (bound (setn s1' x 1) x) t false)) as (r' & Hc & Hr).
    { apply le_sett, le_bound, le_setn. assumption. }
    exists r'. split; [|assumption]. apply (chk_newat s' x t ys s1' k r'); auto.
    + destruct (cb s' x) eqn:E'; [|reflexivity]. apply C in E'. congruence.
    + rewrite D. assumption.
  - destruct (IHchk (sett s' t false)) as (r' & Hc & Hr).
    { apply le_sett. assumption. }
    exists r'. split; [|assumption]. constructor; [rewrite D; assumption|assumption].
  - match goal with Ha : cargs _ _ _ _ |- _ =>
      destruct (cargs_mono _ _ _ _ Ha _ Hle) as (s1' & Ha' & Hle1) end.
    destruct (IHchk (bound (setn s1' x 1) x)) as (r' & Hc & Hr).
    { apply le_bound, le_setn. assumption. }
    exists r'. split; [|assumption]. apply (chk_call s' x f args bs s1' k r'); auto.
    destruct (cb s' x) eqn:E'; [|reflexivity]. apply C in E'. congruence.
Qed.

Lemma chk_app s a s1 : chk s a s1 -> forall k r, chk s1 k r -> chk s (a ++ k) r.
Proof.
  induction 1; intros k' r' Hk; simpl; eauto using chk.
Qed.

(* ---- what holds of the machine while the judgment holds of its code *)

Definition tot (s : cstate) (vs : list var) (c : cfg) (l : loc) : nat :=
  occ l (pend c) + vcount (env c) (cn s) vs l + ext l + hsum (hp c) l (nxt c).

Record inv (s : cstate) (vs : list var) (c : cfg) : Prop := Inv {
  i_nd : NoDup vs;
  i_vs : forall v, cn s v > 0 -> In v vs;
  i_wf1 : forall v, cn s v > 0 -> cb s v = true;
  i_wf2 : forall v u, cvia s v = Some u -> cb s v = true /\ cb s u = true;
  i_wf3 : forall v, cbor s v = true -> cb s v = true;
  (* cells are numbered as they're made *)
  i_bound : forall l, nxt c <= l -> hp c l = None;
  i_pos : forall l k fs, hp c l = Some (k, fs) -> k > 0;
  (* a cell's count is the references to it: the pending drops', the variables', the cells' *)
  i_cnt : forall l k fs, hp c l = Some (k, fs) -> k = tot s vs c l;
  (* and what has a reference to it is in the heap *)
  i_dom : forall l, tot s vs c l > 0 -> hp c l <> None;
  i_old : forall l k fs l', hp c l = Some (k, fs) -> In l' fs -> l' < l;
  (* a borrowed variable is a field of its holder's cell, while that's in the heap *)
  i_via : forall v u k fs, cvia s v = Some u -> hp c (env c u) = Some (k, fs) -> In (env c v) fs;
  i_viab : forall v u, cvia s v = Some u -> env c u < nxt c
}.

Lemma lt_nxt s vs c l : inv s vs c -> hp c l <> None -> l < nxt c.
Proof.
  intros I Hn. destruct (Nat.lt_ge_cases l (nxt c)); [assumption|].
  exfalso. apply Hn. apply (i_bound _ _ _ I). assumption.
Qed.

(* what the caller lends is in the heap: the caller's to keep true (Calls.v) *)
Definition lent_ok (s : cstate) (c : cfg) : Prop :=
  forall v, cbor s v = true -> hp c (env c v) <> None.

Lemma alive_dom s vs c v : inv s vs c -> lent_ok s c -> alive s v -> hp c (env c v) <> None.
Proof.
  intros I L. induction 1 as [x Hx|x y Hv Hy IH|x Hx]; [| |apply L; assumption].
  - apply (i_dom _ _ _ I). unfold tot.
    pose proof (vcount_pos (env c) (cn s) vs x (i_vs _ _ _ I x Hx) Hx). lia.
  - destruct (hp c (env c y)) as [[k fs]|] eqn:E; [|congruence].
    pose proof (i_via _ _ _ I x y k fs Hv E) as Hin.
    apply (i_dom _ _ _ I). unfold tot.
    pose proof (hsum_in (hp c) (env c x) (nxt c) (env c y) k fs (i_viab _ _ _ I x y Hv) E Hin). lia.
Qed.

Lemma alive_cb s vs c v : inv s vs c -> alive s v -> cb s v = true.
Proof.
  intros I. destruct 1.
  - apply (i_wf1 _ _ _ I). assumption.
  - apply (i_wf2 _ _ _ I) in H. tauto.
  - apply (i_wf3 _ _ _ I). assumption.
Qed.

Lemma tot_none s vs c l : inv s vs c -> hp c l = None -> tot s vs c l = 0.
Proof.
  intros I Hn. destruct (tot s vs c l) eqn:E; [reflexivity|].
  exfalso. apply (i_dom _ _ _ I l); [lia|assumption].
Qed.

Lemma occ_nil l : occ l [] = 0.
Proof. reflexivity. Qed.

Lemma hsum_S H l n : hsum H l (S n) = fcount H l n + hsum H l n.
Proof. reflexivity. Qed.

Arguments occ : simpl never.
Arguments hsum : simpl never.
Arguments upd : simpl never.

(* ---- each step keeps it *)

Lemma pres_free s vs H n e l p k fs :
  inv s vs (Cfg H n e (l :: p) k) -> H l = Some (1, fs) ->
  inv s vs (Cfg (upd H l None) n e (fs ++ p) k).
Proof.
  intros I Hl.
  assert (l < n) as Hlt by (apply (lt_nxt _ _ _ _ I); simpl; congruence).
  assert (forall l', hsum (upd H l None) l' n + occ l' fs = hsum H l' n) as F.
  { intros l'.
    assert (fcount H l' l = occ l' fs) as E1 by (unfold fcount; rewrite Hl; reflexivity).
    assert (fcount (upd H l None) l' l = 0) as E2 by (unfold fcount; rewrite upd_eq; reflexivity).
    assert (forall i, i <> l -> fcount (upd H l None) l' i = fcount H l' i) as E3
      by (intros i Hi; unfold fcount; rewrite upd_neq by assumption; reflexivity).
    pose proof (hsum_upd H (upd H l None) l' n l Hlt E3). lia. }
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  pose proof (cnt l 1 fs Hl) as C1. rewrite occ_cons, Nat.eqb_refl in C1.
  constructor; unfold tot; simpl; auto.
  - intros l0 Hl0. destruct (Nat.eq_dec l0 l) as [->|Hne];
      [apply upd_eq|rewrite upd_neq by assumption; auto].
  - intros l0 k0 fs0. destruct (Nat.eq_dec l0 l) as [->|Hne];
      [rewrite upd_eq; discriminate|rewrite upd_neq by assumption; apply pos].
  - intros l0 k0 fs0. destruct (Nat.eq_dec l0 l) as [->|Hne]; [rewrite upd_eq; discriminate|].
    rewrite upd_neq by assumption. intros E. apply cnt in E.
    rewrite occ_cons in E. rewrite occ_app. specialize (F l0). cases; [congruence|lia].
  - intros l0. rewrite occ_app. specialize (F l0). specialize (dom l0). rewrite occ_cons in dom.
    destruct (Nat.eq_dec l0 l) as [->|Hne].
    + rewrite Nat.eqb_refl in dom. lia.
    + rewrite upd_neq by assumption. intros Ht. apply dom. lia.
  - intros l0 k0 fs0 l'. destruct (Nat.eq_dec l0 l) as [->|Hne];
      [rewrite upd_eq; discriminate|rewrite upd_neq by assumption; apply old].
  - intros v u k0 fs0 Hv. destruct (Nat.eq_dec (e u) l) as [E|Hne];
      [rewrite E, upd_eq; discriminate|rewrite upd_neq by assumption; apply via; assumption].
Qed.

Lemma hsum_recount H n l c fs c' :
  H l = Some (c, fs) -> forall l', hsum (upd H l (Some (c', fs))) l' n = hsum H l' n.
Proof.
  intros Hl l'. apply hsum_ext. intros i _. unfold fcount.
  destruct (Nat.eq_dec i l) as [->|Hne]; [rewrite upd_eq, Hl|rewrite upd_neq by assumption]; reflexivity.
Qed.

Lemma pres_dec s vs H n e l p k c fs :
  inv s vs (Cfg H n e (l :: p) k) -> H l = Some (S (S c), fs) ->
  inv s vs (Cfg (upd H l (Some (S c, fs))) n e p k).
Proof.
  intros I Hl.
  pose proof (hsum_recount H n l _ fs (S c) Hl) as F.
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  pose proof (cnt l _ fs Hl) as C1. rewrite occ_cons, Nat.eqb_refl in C1.
  constructor; unfold tot; simpl; auto.
  - intros l0 Hl0. destruct (Nat.eq_dec l0 l) as [->|Hne].
    + rewrite (bnd l Hl0) in Hl. discriminate.
    + rewrite upd_neq by assumption. auto.
  - intros l0 k0 fs0. destruct (Nat.eq_dec l0 l) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. lia.
    + rewrite upd_neq by assumption. apply pos.
  - intros l0 k0 fs0. rewrite F. destruct (Nat.eq_dec l0 l) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. lia.
    + rewrite upd_neq by assumption. intros E. apply cnt in E. rewrite occ_cons in E.
      cases; [congruence|lia].
  - intros l0. rewrite F. intros Ht. destruct (Nat.eq_dec l0 l) as [->|Hne].
    + rewrite upd_eq. discriminate.
    + rewrite upd_neq by assumption. apply dom. rewrite occ_cons. lia.
  - intros l0 k0 fs0 l'. destruct (Nat.eq_dec l0 l) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. exact (old l _ fs l' Hl).
    + rewrite upd_neq by assumption. apply old.
  - intros v u k0 fs0 Hv. destruct (Nat.eq_dec (e u) l) as [E|Hne].
    + rewrite E, upd_eq. intros [= <- <-]. apply (via v u (S (S c)) fs Hv). rewrite E. assumption.
    + rewrite upd_neq by assumption. apply via. assumption.
Qed.

Lemma pres_new s vs H n e x ys k s1 :
  inv s vs (Cfg H n e [] (SNew x ys :: k)) -> cb s x = false -> takes s ys s1 ->
  exists vs', inv (bound (setn s1 x 1) x) vs'
                  (Cfg (upd H n (Some (1, map e ys))) (S n) (upd e x n) [] k).
Proof.
  intros I Hf Ht.
  pose proof (takes_same _ _ _ Ht) as (Sv & Sb & St & Sr).
  pose proof (takes_le _ _ _ Ht) as Tle.
  assert (H n = None) as Hn by (apply (i_bound _ _ _ I); simpl; lia).
  pose proof (tot_none _ _ _ n I Hn) as T0.
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  assert (cn s x = 0) as Zx.
  { destruct (cn s x) eqn:E; [reflexivity|]. rewrite wf1 in Hf by lia. discriminate. }
  assert (cn s1 x = 0) as Z1 by (specialize (Tle x); lia).
  pose proof (takes_count e vs _ _ _ Ht nd vsx) as TC.
  destruct (vs_add (cn s1) vs x nd) as (vs' & nd' & Hx' & Hsub & VC).
  { intros v Hv. apply vsx. specialize (Tle v). lia. }
  assert (forall l, vcount (upd e x n) (upd (cn s1) x 1) vs' l
                    = vcount e (cn s1) vs l + (if Nat.eqb n l then 1 else 0)) as V.
  { intros l. pose proof (vcount_setn (upd e x n) (cn s1) vs' x 1 l nd' Hx') as E.
    rewrite upd_eq, Z1 in E. rewrite (vcount_env e (cn s1)) in E by assumption. rewrite VC in E.
    cases; lia. }
  assert (forall l, hsum (upd H n (Some (1, map e ys))) l (S n) = occ l (map e ys) + hsum H l n) as HS.
  { intros l. rewrite hsum_S. unfold fcount. rewrite upd_eq. f_equal.
    apply hsum_ext. intros i Hi. unfold fcount. rewrite upd_neq by lia. reflexivity. }
  exists vs'. constructor; unfold tot; simpl; auto.
  - intros v. destruct (Nat.eq_dec v x) as [->|Hne]; [auto|].
    rewrite upd_neq by assumption. intros Hv. apply Hsub, vsx. specialize (Tle v). lia.
  - intros v. destruct (Nat.eq_dec v x) as [->|Hne]; [intros _; apply upd_eq|].
    rewrite !upd_neq by assumption. intros Hv. rewrite Sb. apply wf1. specialize (Tle v). lia.
  - intros v u. rewrite Sv. intros Hv. destruct (wf2 v u Hv) as [A B]. rewrite Sb.
    split; unfold upd; cases; auto.
  - intros v. rewrite Sr, Sb. intros Hv. apply wf3 in Hv. unfold upd. cases; auto.
  - intros l Hl. rewrite upd_neq by lia. apply bnd. lia.
  - intros l k0 fs0. destruct (Nat.eq_dec l n) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. lia.
    + rewrite upd_neq by assumption. apply pos.
  - intros l k0 fs0. rewrite V, HS. specialize (TC l). destruct (Nat.eq_dec l n) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. rewrite Nat.eqb_refl. lia.
    + rewrite upd_neq by assumption. intros E. apply cnt in E. cases; [congruence|lia].
  - intros l. rewrite V, HS. specialize (TC l). destruct (Nat.eq_dec l n) as [->|Hne].
    + rewrite upd_eq. discriminate.
    + rewrite upd_neq by assumption. intros Ht'. apply dom. cases; [congruence|lia].
  - intros l k0 fs0 l'. destruct (Nat.eq_dec l n) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-] Hin. apply occ_in in Hin. specialize (TC l').
      destruct (Nat.lt_ge_cases l' n) as [|Hge]; [assumption|]. exfalso.
      apply (dom l'); [lia|apply bnd; assumption].
    + rewrite upd_neq by assumption. apply old.
  - intros v u k0 fs0. rewrite Sv. intros Hv. destruct (wf2 v u Hv) as [A B].
    assert (v <> x) by congruence. assert (u <> x) by congruence.
    rewrite (upd_neq _ e x n u) by assumption. rewrite (upd_neq _ e x n v) by assumption.
    pose proof (viab v u Hv). rewrite upd_neq by lia. apply via. assumption.
  - intros v u. rewrite Sv. intros Hv. destruct (wf2 v u Hv) as [A B].
    assert (u <> x) by congruence. rewrite upd_neq by assumption.
    pose proof (viab v u Hv). lia.
Qed.

Lemma pres_field s vs H n e x y i k c fs l :
  inv s vs (Cfg H n e [] (SField x y i :: k)) -> cb s x = false -> alive s y ->
  H (e y) = Some (c, fs) -> nth_error fs i = Some l ->
  inv (bound (setvia s x y) x) vs (Cfg H n (upd e x l) [] k).
Proof.
  intros I Hf Ha Hy Hi.
  pose proof (alive_cb _ _ _ _ I Ha) as By.
  assert (e y < n) as Ylt by (apply (lt_nxt _ _ _ _ I); simpl; congruence).
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  assert (cn s x = 0) as Zx.
  { destruct (cn s x) eqn:E; [reflexivity|]. rewrite wf1 in Hf by lia. discriminate. }
  assert (y <> x) by congruence.
  constructor; unfold tot; simpl; auto.
  - intros v Hv. unfold upd. cases; auto.
  - intros v u. destruct (Nat.eq_dec v x) as [->|Hne].
    + rewrite upd_eq. intros [= <-]. split; [apply upd_eq|rewrite upd_neq by assumption; assumption].
    + rewrite upd_neq by assumption. intros Hv. destruct (wf2 v u Hv).
      split; unfold upd; cases; auto.
  - intros v Hv. apply wf3 in Hv. unfold upd. cases; auto.
  - intros l0 k0 fs0. rewrite vcount_env by assumption. apply cnt.
  - intros l0. rewrite vcount_env by assumption. apply dom.
  - intros v u k0 fs0. destruct (Nat.eq_dec v x) as [->|Hne].
    + rewrite upd_eq. intros [= <-]. rewrite (upd_neq _ e x l y) by assumption. rewrite Hy.
      intros [= <- <-]. rewrite upd_eq. eapply nth_error_In; eauto.
    + rewrite (upd_neq _ (cvia s)) by assumption. intros Hv. destruct (wf2 v u Hv).
      assert (u <> x) by congruence.
      rewrite (upd_neq _ e x l u) by assumption. rewrite (upd_neq _ e x l v) by assumption.
      apply via. assumption.
  - intros v u. destruct (Nat.eq_dec v x) as [->|Hne].
    + rewrite upd_eq. intros [= <-]. rewrite upd_neq by assumption. assumption.
    + rewrite (upd_neq _ (cvia s)) by assumption. intros Hv. destruct (wf2 v u Hv).
      assert (u <> x) by congruence. rewrite upd_neq by assumption. eapply viab; eauto.
Qed.

Lemma pres_dup s vs H n e x k c fs :
  inv s vs (Cfg H n e [] (SDup x :: k)) -> alive s x -> H (e x) = Some (c, fs) ->
  exists vs', inv (setn s x (cn s x + 1)) vs' (Cfg (upd H (e x) (Some (S c, fs))) n e [] k).
Proof.
  intros I Ha Hx.
  pose proof (alive_cb _ _ _ _ I Ha) as Bx.
  pose proof (hsum_recount H n (e x) _ fs (S c) Hx) as F.
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  destruct (vs_add (cn s) vs x nd vsx) as (vs' & nd' & Hx' & Hsub & VC).
  assert (forall l, vcount e (upd (cn s) x (cn s x + 1)) vs' l
                    = vcount e (cn s) vs l + (if Nat.eqb (e x) l then 1 else 0)) as V.
  { intros l. pose proof (vcount_setn e (cn s) vs' x (cn s x + 1) l nd' Hx') as E.
    rewrite VC in E. cases; lia. }
  pose proof (cnt _ _ _ Hx) as C1.
  exists vs'. constructor; unfold tot; simpl; auto.
  - intros v. destruct (Nat.eq_dec v x) as [->|Hne]; [auto|]. rewrite upd_neq by assumption. auto.
  - intros v. destruct (Nat.eq_dec v x) as [->|Hne]; [auto|]. rewrite upd_neq by assumption. apply wf1.
  - intros l Hl. destruct (Nat.eq_dec l (e x)) as [->|Hne].
    + rewrite (bnd _ Hl) in Hx. discriminate.
    + rewrite upd_neq by assumption. auto.
  - intros l k0 fs0. destruct (Nat.eq_dec l (e x)) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. lia.
    + rewrite upd_neq by assumption. apply pos.
  - intros l k0 fs0. rewrite V, F. destruct (Nat.eq_dec l (e x)) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. rewrite Nat.eqb_refl. lia.
    + rewrite upd_neq by assumption. intros E. apply cnt in E. cases; [congruence|lia].
  - intros l. rewrite V, F. destruct (Nat.eq_dec l (e x)) as [->|Hne].
    + rewrite upd_eq. discriminate.
    + rewrite upd_neq by assumption. intros Ht. apply dom. cases; [congruence|lia].
  - intros l k0 fs0 l'. destruct (Nat.eq_dec l (e x)) as [->|Hne].
    + rewrite upd_eq. intros [= <- <-]. exact (old _ _ fs l' Hx).
    + rewrite upd_neq by assumption. apply old.
  - intros v u k0 fs0 Hv. destruct (Nat.eq_dec (e u) (e x)) as [E|Hne].
    + rewrite E, upd_eq. intros [= <- <-]. apply (via v u c fs Hv). rewrite E. assumption.
    + rewrite upd_neq by assumption. apply via. assumption.
Qed.

Lemma pres_drop s vs H n e x k :
  inv s vs (Cfg H n e [] (SDrop x :: k)) -> cn s x > 0 ->
  inv (setn s x (cn s x - 1)) vs (Cfg H n e [e x] k).
Proof.
  intros I Hx.
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  assert (In x vs) as Hin by auto.
  assert (forall l, occ l [e x] + vcount e (upd (cn s) x (cn s x - 1)) vs l = vcount e (cn s) vs l) as V.
  { intros l. pose proof (vcount_setn e (cn s) vs x (cn s x - 1) l nd Hin).
    rewrite occ_cons, occ_nil. cases; lia. }
  constructor; unfold tot; simpl; auto.
  - intros v. unfold upd. cases; subst; intros; apply vsx; lia.
  - intros v. unfold upd. cases; subst; intros; apply wf1; lia.
  - intros l k0 fs0 E. apply cnt in E. specialize (V l). lia.
  - intros l Ht. apply dom. specialize (V l). lia.
Qed.

Lemma inv_code s vs H n e p k k' : inv s vs (Cfg H n e p k) -> inv s vs (Cfg H n e p k').
Proof. intros [? ? ? ? ? ? ? ? ? ? ? ?]. unfold tot in *. simpl in *. constructor; auto. Qed.

Lemma inv_sett s vs c t b : inv s vs c -> inv (sett s t b) vs c.
Proof. intros [? ? ? ? ? ? ? ? ? ? ? ?]. unfold tot in *. simpl in *. constructor; auto. Qed.

(* a drop that keeps the cell's memory is a drop, then the cell's free or its count's step *)
Lemma pres_droptok_u s vs H n e x t k fs :
  inv s vs (Cfg H n e [] (SDropTok x t :: k)) -> cn s x > 0 -> H (e x) = Some (1, fs) ->
  inv (sett (setn s x (cn s x - 1)) t true) vs (Cfg (upd H (e x) None) n e fs k).
Proof.
  intros I Hx Hl. apply inv_sett.
  pose proof (pres_drop s vs H n e x k (inv_code _ _ _ _ _ _ _ _ I) Hx) as I1.
  pose proof (pres_free _ _ _ _ _ _ _ k _ I1 Hl) as I2.
  rewrite app_nil_r in I2. exact I2.
Qed.

Lemma pres_droptok_s s vs H n e x t k c fs :
  inv s vs (Cfg H n e [] (SDropTok x t :: k)) -> cn s x > 0 -> H (e x) = Some (S (S c), fs) ->
  inv (sett (setn s x (cn s x - 1)) t true) vs (Cfg (upd H (e x) (Some (S c, fs))) n e [] k).
Proof.
  intros I Hx Hl. apply inv_sett.
  pose proof (pres_drop s vs H n e x k (inv_code _ _ _ _ _ _ _ _ I) Hx) as I1.
  exact (pres_dec _ _ _ _ _ _ _ k _ _ I1 Hl).
Qed.

Ltac same := split; [reflexivity|intros v Hv; split; [assumption|reflexivity]].

(* a step keeps it; and it rebinds no variable, nor changes what the caller lends *)
Theorem pres s vs c c' r :
  inv s vs c -> chk s (code c) r -> step c c' ->
  exists s' vs' r', inv s' vs' c' /\ chk s' (code c') r' /\ le r' r /\
    cbor s' = cbor s /\ (forall v, cb s v = true -> cb s' v = true /\ env c' v = env c v).
Proof.
  intros I Hc Hs. destruct Hs; simpl in *.
  - exists s, vs, r. split; [eapply pres_free; eauto|split; [assumption|split; [apply le_refl|same]]].
  - exists s, vs, r. split; [eapply pres_dec; eauto|split; [assumption|split; [apply le_refl|same]]].
  - inversion Hc; subst.
    match goal with Ht : takes s ys _, Hf : cb s x = false |- _ =>
      destruct (pres_new _ _ _ _ _ _ _ k _ I Hf Ht) as [vs' I'];
      pose proof (takes_same _ _ _ Ht) as (_ & Sb & _ & Sr) end.
    eexists _, vs', r. split; [eassumption|split; [eassumption|split; [apply le_refl|]]].
    split; [exact Sr|]. intros v Hv. simpl. rewrite Sb. assert (v <> x) by congruence.
    rewrite !upd_neq by assumption. auto.
  - inversion Hc; subst. eexists _, vs, r.
    split; [eapply pres_field; eauto|split; [eassumption|split; [apply le_refl|]]].
    split; [reflexivity|]. intros v Hv. simpl. assert (v <> x) by congruence.
    rewrite !upd_neq by assumption. auto.
  - inversion Hc; subst.
    match goal with Ha : alive s x, Hx : _ (e x) = Some _ |- _ =>
      destruct (pres_dup _ _ _ _ _ _ k _ _ I Ha Hx) as [vs' I'] end.
    eexists _, vs', r. split; [eassumption|split; [eassumption|split; [apply le_refl|same]]].
  - inversion Hc; subst. eexists _, vs, r.
    split; [eapply pres_drop; eauto|split; [eassumption|split; [apply le_refl|same]]].
  - inversion Hc; subst. exists s, vs, r.
    split; [eapply inv_code; eauto|split; [assumption|split; [apply le_refl|same]]].
  - inversion Hc; subst.
    match goal with Ha : chk s a ?sa, La : le ?sa ?s1, Hk : chk ?s1 k r |- _ =>
      destruct (chk_mono _ _ _ Hk _ La) as (r' & Hk' & Hr);
      exists s, vs, r'; split; [eapply inv_code; eauto|split; [eapply chk_app; eauto|split; [assumption|same]]]
    end.
  - inversion Hc; subst.
    match goal with Hb : chk s b ?sb, Lb : le ?sb ?s1, Hk : chk ?s1 k r |- _ =>
      destruct (chk_mono _ _ _ Hk _ Lb) as (r' & Hk' & Hr);
      exists s, vs, r'; split; [eapply inv_code; eauto|split; [eapply chk_app; eauto|split; [assumption|same]]]
    end.
  - inversion Hc; subst. eexists _, vs, r.
    split; [eapply pres_droptok_u; eauto|split; [eassumption|split; [apply le_refl|same]]].
  - inversion Hc; subst. eexists _, vs, r.
    split; [eapply pres_droptok_s; eauto|split; [eassumption|split; [apply le_refl|same]]].
  - inversion Hc; subst.
    match goal with Ht : takes s ys _, Hf : cb s x = false |- _ =>
      destruct (pres_new _ _ _ _ _ _ _ k _ (inv_code _ _ _ _ _ _ _ (SNew x ys :: k) I) Hf Ht) as [vs' I'];
      pose proof (takes_same _ _ _ Ht) as (_ & Sb & _ & Sr) end.
    eexists _, vs', r.
    split; [apply inv_sett; eassumption|split; [eassumption|split; [apply le_refl|]]].
    split; [exact Sr|]. intros v Hv. simpl. rewrite Sb. assert (v <> x) by congruence.
    rewrite !upd_neq by assumption. auto.
  - inversion Hc; subst. eexists _, vs, r.
    split; [apply inv_sett; eapply inv_code; eauto|split; [eassumption|split; [apply le_refl|same]]].
Qed.

(* what a step does to the heap: a cell that's there after it, and was numbered before it, was
   there with the same fields *)
Lemma step_heap c c' :
  step c c' ->
  nxt c <= nxt c' /\
  forall l k fs, hp c' l = Some (k, fs) -> l < nxt c -> exists k', hp c l = Some (k', fs).
Proof.
  destruct 1; simpl; (split; [lia|]); intros l0 k0 fs0 Hl Hlt; try (eexists; eassumption);
    match type of Hl with
    | upd _ ?a _ l0 = _ =>
      destruct (Nat.eq_dec l0 a) as [->|Hne];
        [rewrite upd_eq in Hl; try discriminate; try (injection Hl as <- <-); try lia; eauto
        |rewrite upd_neq in Hl by assumption; eauto]
    end.
Qed.

(* ---- the judgment accepts something: a cell in a cell, its field read and kept past it *)

Example accepted :
  exists r, chk s0 [SNew 0 []; SNew 1 [0]; SField 2 1 0; SDup 2; SDrop 1;
                    SIf [SRead 2; SDrop 2] [SDrop 2]] r /\ final r.
Proof.
  eexists. split.
  - eapply chk_new; [reflexivity|simpl; tauto|apply takes_nil|].
    eapply chk_new; [reflexivity|simpl; intuition discriminate|
                     apply takes_cons; [simpl; unfold upd; simpl; lia|apply takes_nil]|].
    eapply chk_field; [reflexivity|apply alive_own; simpl; unfold upd; simpl; lia|].
    eapply chk_dup; [eapply alive_via; [reflexivity|apply alive_own; simpl; unfold upd; simpl; lia]|].
    eapply chk_drop; [simpl; unfold upd; simpl; lia|].
    eapply chk_if.
    + eapply chk_read; [apply alive_own; simpl; unfold upd; simpl; lia|].
      eapply chk_drop; [simpl; unfold upd; simpl; lia|apply chk_nil].
    + eapply chk_drop; [simpl; unfold upd; simpl; lia|apply chk_nil].
    + apply le_refl.
    + apply le_refl.
    + apply chk_nil.
  - split; intros v; simpl; [|reflexivity]. unfold upd. simpl.
    destruct v as [|[|[|v]]]; reflexivity.
Qed.

End Core.

#[global] Arguments occ : simpl never.
#[global] Arguments hsum : simpl never.
#[global] Arguments upd : simpl never.

(* ---- the theorems, for a program of one frame: nothing waits on a call *)

Definition ext0 : loc -> nat := fun _ => 0.

Lemma reach sg p r c :
  chk sg s0 p r -> final r -> steps (init p) c ->
  exists s vs r', inv ext0 s vs c /\ chk sg s (code c) r' /\ final r' /\ forall v, cbor s v = false.
Proof.
  intros Hc Hf Hs. remember (init p) as c0 eqn:E0.
  induction Hs as [c|c1 c2 c3 Hs IH Hst]; subst.
  - exists s0, [], r. split; [|split; [assumption|split; [assumption|reflexivity]]].
    constructor; unfold tot, hsum, ext0; simpl; intros; try discriminate; try lia; try reflexivity.
    constructor.
  - destruct (IH eq_refl) as (s & vs & r' & I & Hk & Hfr & Hb).
    destruct (pres sg ext0 _ _ _ _ _ I Hk Hst) as (s' & vs' & r'' & I' & Hk' & Hle & Hb' & _).
    exists s', vs', r''. split; [assumption|split; [assumption|split]].
    + destruct Hle as (A & _ & _ & D & _). destruct Hfr as [F1 F2].
      split; intros v; [rewrite A; apply F1|rewrite D; apply F2].
    + intros v. rewrite Hb'. apply Hb.
Qed.

(* a checked program never touches a cell that was freed *)
Theorem safe sg p r c : chk sg s0 p r -> final r -> steps (init p) c -> ~ faults c.
Proof.
  intros Hc Hf Hs. destruct (reach _ _ _ _ Hc Hf Hs) as (s & vs & r' & I & Hk & _ & Hb).
  assert (lent_ok s c) as L by (intros v Hv; rewrite Hb in Hv; discriminate).
  unfold faults. destruct c as [H n e pd cd]. simpl in *. destruct pd as [|l pd].
  - destruct cd as [|st cd]; [auto|].
    destruct st; auto; inversion Hk; subst;
      match goal with
      | Ha : alive s _ |- _ => exact (alive_dom sg _ _ _ _ _ I L Ha)
      | Hx : cn s _ > 0 |- _ => exact (alive_dom sg _ _ _ _ _ I L (alive_own _ _ Hx))
      end.
  - apply (i_dom _ _ _ _ I l). unfold tot. simpl. rewrite occ_cons, Nat.eqb_refl. lia.
Qed.

(* and when it ends, with every drop done, nothing is left in the heap *)
Theorem no_leak sg p r c :
  chk sg s0 p r -> final r -> steps (init p) c ->
  code c = [] -> pend c = [] -> forall l, hp c l = None.
Proof.
  intros Hc Hf Hs Hcode Hpend.
  destruct (reach _ _ _ _ Hc Hf Hs) as (s & vs & r' & I & Hk & Hfr & _).
  rewrite Hcode in Hk. inversion Hk; subst. destruct Hfr as [F1 _].
  assert (forall k l, nxt c <= l + k -> hp c l = None) as G.
  { induction k as [|k IH]; intros l Hl.
    - apply (i_bound _ _ _ _ I). lia.
    - destruct (hp c l) as [[m fs]|] eqn:E; [|reflexivity]. exfalso.
      pose proof (i_cnt _ _ _ _ I l m fs E) as C. pose proof (i_pos _ _ _ _ I l m fs E) as P.
      unfold tot, ext0 in C. rewrite Hpend in C. rewrite vcount_zero in C by exact F1.
      assert (occ l [] = 0) as O by reflexivity.
      assert (hsum (hp c) l (nxt c) > 0) as Hp by lia.
      destruct (hsum_pos _ _ _ Hp) as (i & Hi & Hfc). unfold fcount in Hfc.
      destruct (hp c i) as [[m' fs']|] eqn:Ei; [|lia].
      apply occ_in in Hfc. pose proof (i_old _ _ _ _ I i m' fs' l Ei Hfc) as Lt.
      rewrite IH in Ei by lia. discriminate. }
  intros l. apply (G (nxt c) l). lia.
Qed.

Print Assumptions safe.
Print Assumptions no_leak.
