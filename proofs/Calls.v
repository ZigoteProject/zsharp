(* Calls: a function's body is checked alone, against the parameters it borrows, and a program
   of checked functions never touches a freed cell and leaves none.

   A function is its parameters, its body and the variable it returns. A call takes a reference
   from each argument the callee owns, and lends the arguments it borrows, which must be alive
   once the others are taken (Ownership.v's [chk_call] and [cargs]). The callee's body is
   checked from [entry]: one reference of its own for each parameter it owns, and its borrowed
   parameters alive for as long as it runs. It must end holding one reference, its result's.

   The machine has a stack: a call suspends the caller's frame and starts the callee's with its
   parameters at the arguments' cells; a frame that ends gives its result to the caller.

   Proved, when every function is checked against the table the calls are checked against
   ([fwf]): [msafe], no read, dup or drop of a freed cell in any frame, and [mno_leak], an
   empty heap when the program ends.

   What a callee borrows stays in the heap because its caller's frame, which doesn't run
   meanwhile, keeps it alive: by a reference of its own, by a cell it holds, or by what its
   own caller lends it ([SI_lent]). Any table is sound, so borrow inference needs no proof.

   Cells here have no addresses: a token held across a call is Tokens.v's subject, for one
   frame. *)
From Stdlib Require Import List Arith Lia.
Import ListNotations.
From Proofs Require Import Ownership.

Ltac cases :=
  repeat match goal with
  | |- context [Nat.eqb ?a ?b] => destruct (Nat.eqb_spec a b)
  | H : context [Nat.eqb ?a ?b] |- _ => destruct (Nat.eqb_spec a b)
  end.

(* ---- functions *)

Record fdef := F { fps : list var; fbody : list stmt; fret : var }.

(* a parameter the callee owns, and one it borrows *)
Definition own1 (s : cstate) (p : var) : cstate := bound (setn s p 1) p.
Definition bor1 (s : cstate) (p : var) : cstate :=
  CS (cn s) (cvia s) (upd (cb s) p true) (ct s) (upd (cbor s) p true).

(* what a body starts with *)
Fixpoint entry (ps : list var) (bs : list bool) : cstate :=
  match ps, bs with
  | p :: ps', b :: bs' => if b then bor1 (entry ps' bs') p else own1 (entry ps' bs') p
  | _, _ => s0
  end.

(* what it ends with: its result, and nothing else *)
Definition fend (ret : var) (r : cstate) : Prop :=
  cn r ret = 1 /\ (forall v, v <> ret -> cn r v = 0) /\ (forall v, ct r v = false).

(* the callee's variables: each parameter at its argument's cell *)
Fixpoint bindp (e : var -> loc) (ps args : list var) : var -> loc :=
  match ps, args with
  | p :: ps', a :: args' => upd (bindp e ps' args') p (e a)
  | _, _ => fun _ => 0
  end.

(* the references the owned arguments give to l *)
Fixpoint ownocc (e : var -> loc) (args : list var) (bs : list bool) (l : loc) : nat :=
  match args, bs with
  | a :: args', false :: bs' => (if Nat.eqb (e a) l then 1 else 0) + ownocc e args' bs' l
  | _ :: args', true :: bs' => ownocc e args' bs' l
  | _, _ => 0
  end.

Lemma entry_dom ps bs v :
  ~ In v ps ->
  cn (entry ps bs) v = 0 /\ cbor (entry ps bs) v = false /\ cb (entry ps bs) v = false.
Proof.
  revert bs. induction ps as [|p ps IH]; intros bs Hn; [destruct bs; simpl; auto|].
  destruct bs as [|b bs]; [simpl; auto|].
  assert (v <> p) as Hne by (intros ->; apply Hn; simpl; auto).
  destruct (IH bs) as (A & B & C); [simpl in Hn; tauto|].
  destruct b; simpl; rewrite ?upd_neq by assumption; auto.
Qed.

Lemma entry_wf ps bs v :
  (cn (entry ps bs) v > 0 -> cb (entry ps bs) v = true) /\
  (cbor (entry ps bs) v = true -> cb (entry ps bs) v = true).
Proof.
  revert bs. induction ps as [|p ps IH]; intros bs.
  - destruct bs; simpl; split; intros; (lia || discriminate).
  - destruct bs as [|b bs]; [simpl; split; intros; (lia || discriminate)|].
    destruct (IH bs) as [A B].
    destruct b; simpl; unfold upd; cases; auto.
Qed.

Lemma entry_via ps bs v : cvia (entry ps bs) v = None.
Proof.
  revert bs. induction ps as [|p ps IH]; intros bs; [destruct bs; reflexivity|].
  destruct bs as [|b bs]; [reflexivity|]. destruct b; simpl; apply IH.
Qed.

Lemma vcount_ext e e' cnf cnf' vs l :
  (forall v, In v vs -> e v = e' v /\ cnf v = cnf' v) -> vcount e cnf vs l = vcount e' cnf' vs l.
Proof.
  induction vs as [|v vs IH]; simpl; intros Hx; [reflexivity|].
  destruct (Hx v) as [-> ->]; [auto|]. rewrite IH; auto.
Qed.

Lemma vcount_single e cnf vs x l :
  NoDup vs -> In x vs -> cnf x = 1 -> (forall v, v <> x -> cnf v = 0) ->
  vcount e cnf vs l = if Nat.eqb (e x) l then 1 else 0.
Proof.
  induction vs as [|v vs IH]; simpl; intros Hnd Hin H1 H0; [tauto|].
  inversion Hnd; subst. destruct Hin as [->|Hin].
  - rewrite H1. rewrite (vcount_ext e e cnf (fun _ => 0) vs l).
    + rewrite vcount_zero by reflexivity. lia.
    + intros v Hv. split; [reflexivity|]. apply H0. intros ->. contradiction.
  - rewrite IH by assumption. rewrite (H0 v) by (intros ->; contradiction).
    destruct (Nat.eqb (e v) l); reflexivity.
Qed.

Lemma entry_count e l ps :
  forall args bs, NoDup ps -> length ps = length args -> length args = length bs ->
  vcount (bindp e ps args) (cn (entry ps bs)) ps l = ownocc e args bs l.
Proof.
  induction ps as [|p ps IH]; intros [|a args] [|b bs] Hnd L1 L2; simpl in *;
    try discriminate; try reflexivity.
  inversion Hnd; subst. rewrite upd_eq.
  assert (vcount (upd (bindp e ps args) p (e a))
                 (cn (if b then bor1 (entry ps bs) p else own1 (entry ps bs) p)) ps l
          = ownocc e args bs l) as ->.
  { rewrite <- (IH args bs) by (auto; lia). apply vcount_ext. intros v Hv.
    assert (v <> p) by (intros ->; contradiction).
    split; [apply upd_neq; assumption|].
    destruct b; simpl; [reflexivity|apply upd_neq; assumption]. }
  destruct b; simpl.
  - destruct (entry_dom ps bs p H1) as (-> & _). destruct (Nat.eqb (e a) l); reflexivity.
  - rewrite upd_eq. reflexivity.
Qed.

Lemma cargs_len s args bs s' : cargs s args bs s' -> length args = length bs.
Proof. induction 1; simpl; auto. Qed.

Lemma cargs_count e vs s args bs s' :
  cargs s args bs s' -> NoDup vs -> (forall v, cn s v > 0 -> In v vs) ->
  forall l, vcount e (cn s') vs l + ownocc e args bs l = vcount e (cn s) vs l.
Proof.
  induction 1 as [s|s a rest bs s' Ha Hc IH|s a rest bs s' Hc IH Ha]; intros Hnd Hall l; simpl.
  - lia.
  - assert (In a vs) as Hin by auto.
    assert (forall v, cn (setn s a (cn s a - 1)) v > 0 -> In v vs) as Hall'.
    { intros v. simpl. unfold upd. cases; subst; auto. }
    specialize (IH Hnd Hall' l). simpl in IH.
    pose proof (vcount_setn e (cn s) vs a (cn s a - 1) l Hnd Hin) as E.
    cases; lia.
  - apply IH; assumption.
Qed.

(* what the callee borrows is an argument alive in the caller *)
Lemma cargs_alive e s args bs s' :
  cargs s args bs s' -> forall ps, NoDup ps -> length ps = length args ->
  forall p, cbor (entry ps bs) p = true -> exists a, alive s' a /\ e a = bindp e ps args p.
Proof.
  induction 1 as [s|s a rest bs s' Ha Hc IH|s a rest bs s' Hc IH Ha];
    intros [|p0 ps] Hnd Hl p Hp; simpl in *; try discriminate.
  - inversion Hnd; subst.
    destruct (in_dec Nat.eq_dec p ps) as [Hin|Hnin].
    + destruct (IH ps H2 ltac:(lia) p Hp) as (a' & Ha' & E). exists a'. split; [assumption|].
      rewrite upd_neq by (intros ->; contradiction). assumption.
    + destruct (entry_dom ps bs p Hnin) as (_ & B & _). congruence.
  - inversion Hnd; subst. destruct (Nat.eq_dec p p0) as [->|Hne].
    + exists a. split; [assumption|]. rewrite upd_eq. reflexivity.
    + rewrite upd_neq in Hp by assumption.
      destruct (IH ps H2 ltac:(lia) p Hp) as (a' & Ha' & E). exists a'. split; [assumption|].
      rewrite upd_neq by assumption. assumption.
Qed.

(* ---- the machine *)

(* a caller waiting: its variables, the rest of its code, the variable its call's result is,
   and the variable the callee returns *)
Record frame := Fr { fenv : var -> loc; fcode : list stmt; fres : var; fretc : var }.
Record mcfg := M { top : cfg; stk : list frame }.

Section Calls.

Variable sg : nat -> option (list bool).
Variable funs : nat -> option fdef.

Inductive mstep : mcfg -> mcfg -> Prop :=
| ms_step c c' st : step c c' -> mstep (M c st) (M c' st)
| ms_call H n e x f args k st fd :
    funs f = Some fd ->
    mstep (M (Cfg H n e [] (SCall x f args :: k)) st)
          (M (Cfg H n (bindp e (fps fd) args) [] (fbody fd)) (Fr e k x (fret fd) :: st))
| ms_ret H n e fe fk fx ret st :
    mstep (M (Cfg H n e [] []) (Fr fe fk fx ret :: st))
          (M (Cfg H n (upd fe fx (e ret)) [] fk) st).

Inductive msteps : mcfg -> mcfg -> Prop :=
| msteps_refl m : msteps m m
| msteps_step m1 m2 m3 : msteps m1 m2 -> mstep m2 m3 -> msteps m1 m3.

(* every function is checked against the table its calls are checked against *)
Definition fwf : Prop :=
  forall f fd, funs f = Some fd ->
  exists bs r, sg f = Some bs /\ length (fps fd) = length bs /\ NoDup (fps fd) /\
               chk sg (entry (fps fd) bs) (fbody fd) r /\ fend (fret fd) r.

(* what the frame on top must end with *)
Definition endc (st : list frame) : cstate -> Prop :=
  match st with [] => final | fr :: _ => fend (fretc fr) end.

Lemma endc_le st r r' : le r' r -> endc st r -> endc st r'.
Proof.
  intros (A & _ & _ & D & _). destruct st; simpl.
  - intros [F1 F2]. split; intros v; [rewrite A; apply F1|rewrite D; apply F2].
  - intros (F1 & F2 & F3). repeat split; [rewrite A; assumption| |].
    + intros v Hv. rewrite A. auto.
    + intros v. rewrite D. auto.
Qed.

(* ---- what holds of a waiting frame *)

Record FI (s : cstate) (vs : list var) (e : var -> loc) (H : heap) (n : loc) : Prop := FIc {
  f_nd : NoDup vs;
  f_vs : forall v, cn s v > 0 -> In v vs;
  f_wf1 : forall v, cn s v > 0 -> cb s v = true;
  f_wf2 : forall v u, cvia s v = Some u -> cb s v = true /\ cb s u = true;
  f_wf3 : forall v, cbor s v = true -> cb s v = true;
  f_via : forall v u k fs, cvia s v = Some u -> H (e u) = Some (k, fs) -> In (e v) fs;
  f_viab : forall v u, cvia s v = Some u -> e u < n
}.

Lemma inv_FI ext s vs c : inv ext s vs c -> FI s vs (env c) (hp c) (nxt c).
Proof. intros [? ? ? ? ? ? ? ? ? ? ? ?]. constructor; assumption. Qed.

(* the heap may go on: a cell that's there later, and was numbered before, was there the same *)
Lemma FI_heap s vs e H n H' n' :
  FI s vs e H n -> n <= n' ->
  (forall l k fs, H' l = Some (k, fs) -> l < n -> exists k', H l = Some (k', fs)) ->
  FI s vs e H' n'.
Proof.
  intros [a1 a2 a3 a4 a5 a6 a7] Hle Hh. constructor; auto.
  - intros v u k fs Hv Hu. destruct (Hh _ _ _ Hu (a7 v u Hv)) as [k' Hk']. eauto.
  - intros v u Hv. specialize (a7 v u Hv). lia.
Qed.

(* the checker's side of a waiting frame: its state once the arguments were taken *)
Record gframe := G { gs1 : cstate; gvs : list var }.

(* the stack, from the frame that runs (s, e) down *)
Fixpoint SI (H : heap) (n : loc) (s : cstate) (e : var -> loc)
            (st : list frame) (gs : list gframe) : Prop :=
  match st, gs with
  | [], [] => forall v, cbor s v = false
  | fr :: st', g :: gs' =>
      (* what the frame above was lent is alive in this one *)
      (forall p, cbor s p = true -> exists a, alive (gs1 g) a /\ fenv fr a = e p) /\
      FI (gs1 g) (gvs g) (fenv fr) H n /\
      cb (gs1 g) (fres fr) = false /\
      (* and with the result bound, its code is checked to its end *)
      (exists r, chk sg (bound (setn (gs1 g) (fres fr) 1) (fres fr)) (fcode fr) r /\ endc st' r) /\
      SI H n (gs1 g) (fenv fr) st' gs'
  | _, _ => False
  end.

(* the references the waiting frames hold *)
Fixpoint extof (st : list frame) (gs : list gframe) (l : loc) : nat :=
  match st, gs with
  | fr :: st', g :: gs' => vcount (fenv fr) (cn (gs1 g)) (gvs g) l + extof st' gs' l
  | _, _ => 0
  end.

Lemma SI_top H n s e s' e' st gs :
  SI H n s e st gs -> cbor s' = cbor s -> (forall p, cbor s p = true -> e' p = e p) ->
  SI H n s' e' st gs.
Proof.
  destruct st as [|fr st], gs as [|g gs]; simpl; try tauto.
  - intros A B _ v. rewrite B. apply A.
  - intros (A & R) B C. split; [|exact R]. intros p Hp. rewrite B in Hp.
    destruct (A p Hp) as (a & Ha & E). exists a. split; [assumption|]. rewrite C; assumption.
Qed.

Lemma SI_heap H n H' n' :
  n <= n' ->
  (forall l k fs, H' l = Some (k, fs) -> l < n -> exists k', H l = Some (k', fs)) ->
  forall st gs s e, SI H n s e st gs -> SI H' n' s e st gs.
Proof.
  intros Hle Hh. induction st as [|fr st IH]; intros [|g gs] s e; simpl; try tauto.
  intros (A & Fi & B & C & R).
  split; [exact A|]. split; [eapply FI_heap; eauto|]. split; [exact B|]. split; [exact C|].
  apply IH. exact R.
Qed.

(* what is lent is in the heap: the lender is alive by a reference of its own, by a cell it
   holds, or by what it was lent itself *)
Lemma SI_lent H n :
  (forall l, hsum H l n > 0 -> H l <> None) ->
  forall st gs s e, SI H n s e st gs -> (forall l, extof st gs l > 0 -> H l <> None) ->
  forall v, cbor s v = true -> H (e v) <> None.
Proof.
  intros HH. induction st as [|fr st IH]; intros [|g gs] s e HS HX v Hv; simpl in *;
    try contradiction.
  - rewrite HS in Hv. discriminate.
  - destruct HS as (A & [a1 a2 a3 a4 a5 a6 a7] & _ & _ & R).
    destruct (A v Hv) as (a & Ha & <-).
    assert (forall x, alive (gs1 g) x -> H (fenv fr x) <> None) as AL.
    { induction 1 as [x Hx|x y Hxy Hy IHy|x Hx].
      - apply HX. pose proof (vcount_pos (fenv fr) (cn (gs1 g)) (gvs g) x (a2 x Hx) Hx). lia.
      - destruct (H (fenv fr y)) as [[k fs]|] eqn:E; [|congruence].
        apply HH. eapply hsum_in; [exact (a7 x y Hxy)|exact E|exact (a6 x y k fs Hxy E)].
      - apply (IH gs (gs1 g) (fenv fr) R); [intros l Hl; apply HX; lia|assumption]. }
    apply AL. assumption.
Qed.

(* ---- the whole machine's invariant *)

Definition GI (m : mcfg) (s : cstate) (vs : list var) (gs : list gframe) : Prop :=
  inv (extof (stk m) gs) s vs (top m) /\
  (exists r, chk sg s (code (top m)) r /\ endc (stk m) r) /\
  SI (hp (top m)) (nxt (top m)) s (env (top m)) (stk m) gs.

(* a call: the callee's frame, the caller's references counted among the waiting frames' *)
Lemma call_inv ext ext' s vs H n e k args bs s1 ps body :
  inv ext s vs (Cfg H n e [] k) -> cargs s args bs s1 ->
  NoDup ps -> length ps = length bs ->
  (forall l, ext' l = vcount e (cn s1) vs l + ext l) ->
  inv ext' (entry ps bs) ps (Cfg H n (bindp e ps args) [] body).
Proof.
  intros I Ha Hnd Hl Hext.
  pose proof (cargs_len _ _ _ _ Ha) as Hl2.
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  assert (forall l, vcount (bindp e ps args) (cn (entry ps bs)) ps l + vcount e (cn s1) vs l
                    = vcount e (cn s) vs l) as V.
  { intros l. rewrite entry_count by (auto; lia).
    pose proof (cargs_count e vs _ _ _ _ Ha nd vsx l). lia. }
  constructor; unfold tot; simpl; auto.
  - intros v Hv. destruct (in_dec Nat.eq_dec v ps) as [|Hn]; [assumption|].
    destruct (entry_dom ps bs v Hn) as (Z & _). lia.
  - intros v. apply entry_wf.
  - intros v u. rewrite entry_via. discriminate.
  - intros v. apply entry_wf.
  - intros l k0 fs0 E. apply cnt in E. rewrite Hext. specialize (V l). lia.
  - intros l. rewrite Hext. specialize (V l). intros Ht. apply dom. lia.
  - intros v u k0 fs0. rewrite entry_via. discriminate.
  - intros v u. rewrite entry_via. discriminate.
Qed.

Lemma cargs_FI ext s vs c args bs s1 :
  inv ext s vs c -> cargs s args bs s1 -> FI s1 vs (env c) (hp c) (nxt c).
Proof.
  intros I Ha. pose proof (cargs_same _ _ _ _ Ha) as (Sv & Sb & _ & Sr).
  pose proof (cargs_le _ _ _ _ Ha) as Le.
  destruct (inv_FI _ _ _ _ I) as [a1 a2 a3 a4 a5 a6 a7].
  constructor; auto.
  - intros v Hv. apply a2. specialize (Le v). lia.
  - intros v Hv. rewrite Sb. apply a3. specialize (Le v). lia.
  - intros v u. rewrite Sv, Sb. apply a4.
  - intros v. rewrite Sr, Sb. apply a5.
  - intros v u k fs. rewrite Sv. apply a6.
  - intros v u. rewrite Sv. apply a7.
Qed.

(* a return: the result's reference is the caller's, in the variable the call bound *)
Lemma ret_inv ext ext' s vs H n e k s1 vsg fe fx ret k' :
  inv ext s vs (Cfg H n e [] k) -> fend ret s ->
  FI s1 vsg fe H n -> cb s1 fx = false ->
  (forall l, ext l = vcount fe (cn s1) vsg l + ext' l) ->
  exists vs2, inv ext' (bound (setn s1 fx 1) fx) vs2 (Cfg H n (upd fe fx (e ret)) [] k').
Proof.
  intros I (R1 & R0 & _) [a1 a2 a3 a4 a5 a6 a7] Hf Hext.
  destruct I as [nd vsx wf1 wf2 wf3 bnd pos cnt dom old via viab]. unfold tot in *. simpl in *.
  assert (forall l, vcount e (cn s) vs l = if Nat.eqb (e ret) l then 1 else 0) as VS.
  { intros l. apply vcount_single; auto. apply vsx. lia. }
  assert (cn s1 fx = 0) as Z1.
  { destruct (cn s1 fx) eqn:E; [reflexivity|]. rewrite a3 in Hf by lia. discriminate. }
  destruct (vs_add (cn s1) vsg fx a1 a2) as (vs2 & nd2 & Hx2 & Hsub & VC).
  assert (forall l, vcount (upd fe fx (e ret)) (upd (cn s1) fx 1) vs2 l
                    = vcount fe (cn s1) vsg l + (if Nat.eqb (e ret) l then 1 else 0)) as V.
  { intros l. pose proof (vcount_setn (upd fe fx (e ret)) (cn s1) vs2 fx 1 l nd2 Hx2) as E.
    rewrite upd_eq, Z1 in E. rewrite (vcount_env fe (cn s1)) in E by assumption.
    rewrite VC in E. cases; lia. }
  exists vs2. constructor; unfold tot; simpl; auto.
  - intros v. destruct (Nat.eq_dec v fx) as [->|Hne]; [auto|].
    rewrite upd_neq by assumption. auto.
  - intros v. destruct (Nat.eq_dec v fx) as [->|Hne]; [intros _; apply upd_eq|].
    rewrite !upd_neq by assumption. apply a3.
  - intros v u Hv. destruct (a4 v u Hv). split; unfold upd; cases; auto.
  - intros v Hv. apply a5 in Hv. unfold upd. cases; auto.
  - intros l k0 fs0 E. apply cnt in E. rewrite V. rewrite VS, Hext in E. lia.
  - intros l. rewrite V. intros Ht. apply dom. rewrite VS, Hext. lia.
  - intros v u k0 fs0 Hv. destruct (a4 v u Hv) as [A B].
    assert (v <> fx) by congruence. assert (u <> fx) by congruence.
    rewrite !upd_neq by assumption. apply a6. assumption.
  - intros v u Hv. destruct (a4 v u Hv) as [A B].
    assert (u <> fx) by congruence. rewrite upd_neq by assumption. eapply a7; eauto.
Qed.

Hypothesis Hfwf : fwf.

Theorem mpres m m' s vs gs :
  GI m s vs gs -> mstep m m' -> exists s' vs' gs', GI m' s' vs' gs'.
Proof.
  intros (I & (r & Hk & He) & HS) Hst. destruct Hst; simpl in *.
  - (* a step of the frame on top *)
    destruct (pres sg _ _ _ _ _ _ I Hk H) as (s' & vs' & r' & I' & Hk' & Hle & Hb & He' & _).
    exists s', vs', gs. split; [exact I'|split].
    + exists r'. split; [assumption|eapply endc_le; eauto].
    + destruct (step_heap _ _ H) as [Hn Hh].
      apply (SI_top _ _ s (env c)); [eapply SI_heap; eauto|assumption|].
      intros p Hp. apply He'. apply (i_wf3 _ _ _ _ I). assumption.
  - (* a call *)
    inversion Hk; subst.
    destruct (Hfwf f fd H0) as (bs' & rf & Hsg & Hlen & Hnd & Hbody & Hfe).
    assert (bs' = bs) as -> by congruence.
    match goal with Ha : cargs s args bs ?s1 |- _ =>
      pose proof (cargs_same _ _ _ _ Ha) as (Sv & Sb & _ & Sr);
      exists (entry (fps fd) bs), (fps fd), (G s1 vs :: gs); split; [|split]
    end.
    + eapply call_inv; eauto.
    + exists rf. split; assumption.
    + simpl. split; [|split; [|split; [|split]]].
      * intros p Hp.
        match goal with Ha : cargs s args bs _ |- _ =>
          destruct (cargs_alive e _ _ _ _ Ha (fps fd) Hnd ltac:(rewrite Hlen; symmetry; eapply cargs_len; eauto) p Hp)
            as (a & Ha1 & Ha2) end.
        exists a. auto.
      * eapply (cargs_FI _ _ _ (Cfg H n e [] (SCall x f args :: k))); eauto.
      * rewrite Sb. assumption.
      * exists r. split; assumption.
      * eapply SI_top; eauto.
  - (* a return *)
    inversion Hk; subst. destruct gs as [|[s1 vsg] gs]; [contradiction|]. simpl in *.
    destruct HS as (A & Fi & Hfx & (r2 & Hk2 & He2) & R).
    destruct (ret_inv _ (extof st gs) _ _ _ _ _ _ _ _ _ fx ret fk I He Fi Hfx) as [vs2 I2];
      [reflexivity|].
    exists (bound (setn s1 fx 1) fx), vs2, gs. split; [exact I2|split].
    + exists r2. split; assumption.
    + apply (SI_top _ _ s1 fe); [assumption|reflexivity|].
      intros p Hp. apply upd_neq. intros ->. rewrite (f_wf3 _ _ _ _ _ Fi fx Hp) in Hfx. discriminate.
Qed.

Definition minit (p : list stmt) : mcfg := M (init p) [].

Lemma mreach p r m :
  chk sg s0 p r -> final r -> msteps (minit p) m -> exists s vs gs, GI m s vs gs.
Proof.
  intros Hc Hf Hs. remember (minit p) as m0 eqn:E0.
  induction Hs as [m|m1 m2 m3 Hs IH Hst]; subst.
  - exists s0, [], []. split; [|split].
    + constructor; unfold tot, hsum; simpl; intros; try discriminate; try lia; try reflexivity.
      constructor.
    + exists r. split; assumption.
    + simpl. reflexivity.
  - destruct (IH eq_refl) as (s & vs & gs & HG). eapply mpres; eauto.
Qed.

(* no frame of a checked program touches a cell that was freed *)
Theorem msafe p r m :
  chk sg s0 p r -> final r -> msteps (minit p) m -> ~ faults (top m).
Proof.
  intros Hc Hf Hs. destruct (mreach _ _ _ Hc Hf Hs) as (s & vs & gs & I & (r' & Hk & _) & HS).
  eapply inv_safe; [exact I| |exact Hk].
  intros v Hv. eapply SI_lent; [|exact HS| |exact Hv].
  - intros l Hl. apply (i_dom _ _ _ _ I). unfold tot. lia.
  - intros l Hl. apply (i_dom _ _ _ _ I). unfold tot. lia.
Qed.

(* and when it ends, no frame waiting and every drop done, the heap is empty *)
Theorem mno_leak p r m :
  chk sg s0 p r -> final r -> msteps (minit p) m ->
  stk m = [] -> code (top m) = [] -> pend (top m) = [] -> forall l, hp (top m) l = None.
Proof.
  intros Hc Hf Hs Hstk Hcode Hpend.
  destruct (mreach _ _ _ Hc Hf Hs) as (s & vs & gs & I & (r' & Hk & He) & HS).
  rewrite Hstk in *. rewrite Hcode in Hk. inversion Hk; subst.
  destruct gs; [|simpl in HS; contradiction]. simpl in He. destruct He as [F1 _].
  eapply inv_empty; [exact I|reflexivity|exact F1|exact Hpend].
Qed.

End Calls.

(* ---- the hypotheses can be met: a function that borrows its parameter and returns a
   reference to it, and a program that calls it and then drops both *)

Definition sgx (f : nat) : option (list bool) := match f with 0 => Some [true] | _ => None end.
Definition funsx (f : nat) : option fdef :=
  match f with 0 => Some (F [0] [SDup 0] 0) | _ => None end.
Definition mainx : list stmt := [SNew 0 []; SCall 1 0 [0]; SDrop 0; SDrop 1].

Example fwf_x : fwf sgx funsx.
Proof.
  intros f fd Hf. destruct f; [|discriminate]. injection Hf as <-. simpl.
  eexists [true], _. split; [reflexivity|split; [reflexivity|split; [|split]]].
  - repeat constructor. simpl. tauto.
  - eapply chk_dup; [apply alive_bor; simpl; apply upd_eq|apply chk_nil].
  - unfold fend. simpl. split; [reflexivity|split; [|reflexivity]].
    intros v Hv. unfold upd. simpl. destruct v as [|v]; [congruence|reflexivity].
Qed.

Example main_x : exists r, chk sgx s0 mainx r /\ final r.
Proof.
  eexists. split.
  - eapply chk_new; [reflexivity|simpl; tauto|apply takes_nil|].
    eapply chk_call; [reflexivity|reflexivity| |].
    + apply cargs_bor; [apply cargs_nil|apply alive_own; simpl; unfold upd; simpl; lia].
    + eapply chk_drop; [simpl; unfold upd; simpl; lia|].
      eapply chk_drop; [simpl; unfold upd; simpl; lia|apply chk_nil].
  - split; intros v; simpl; [|reflexivity]. unfold upd. simpl.
    destruct v as [|[|v]]; reflexivity.
Qed.

Example safe_x m : msteps funsx (minit mainx) m -> ~ faults (top m).
Proof.
  destruct main_x as (r & Hc & Hf). exact (msafe sgx funsx fwf_x mainx r m Hc Hf).
Qed.

Print Assumptions msafe.
Print Assumptions mno_leak.
