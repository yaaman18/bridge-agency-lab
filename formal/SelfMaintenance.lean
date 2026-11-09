import ERIEC.DC

/-!
# D2 self-maintenance reading: the formal lemmas (statements first, then proofs)

Discussion D2 (`discussion/notes/D2.md`, claude-lab and codex-lab, 2026-11-07). The theme T is a rule of reading
("the run has, at event t, evidence of self-maintenance in this substrate's reading of M1"); it is not a judgment of M1
and does not touch bridge-protocol's definitions. These are the lemmas of T that are about rules, not measurements:
- LS1 (L1): hSelf gives the inclusion of the visible self in the greatest fixed point of the event's closure operator.
- LS2a / LS2b (L2): the decay rule of the circuit's confidence (`core/circuit.jl:258`, cap 4 `:8`) removes an
  unconfirmed contingency within 32 updates, and 32 is sharp.
- LS9 (L9): with a zero patch offer and no pending call, no contingency is confirmed (`core/circuit.jl:148–156`,
  `:220`, `:234–237`), abstracted (the abstraction map is written at LS9).
- LS1 is stated for the closure operator `Closure.Phi` of bridge-protocol (the specialization of the monotone `F`).
The correspondence to the Julia rule is by finite tables only ("agrees on the listed records"), as R-BODY-3.
`phenomenal_claim` is not touched.
-/

namespace BridgeLab.SelfMaintenance

open ERIEC

/-! ## LS1 (L1): hSelf ⇒ κ ⊆ ν Φ, and ν Φ is a fixed point of Φ -/

/-- LS1: if the self `κ` of an event is a post-fixed point of the event's closure operator (hSelf), it is included in
the greatest fixed point `ν Φ`, which is a fixed point. Only the inclusion is claimed: not that `κ` is a fixed point,
nor anything across events. -/
theorem ls1 {M C : Type*} (piRel : M → Set C) (rhoRel : C → Set M) (κ : Set C)
    (hSelf : κ ⊆ Closure.Phi piRel rhoRel κ) :
    κ ⊆ Closure.nu (Closure.Phi piRel rhoRel) ∧
      Closure.Phi piRel rhoRel (Closure.nu (Closure.Phi piRel rhoRel)) = Closure.nu (Closure.Phi piRel rhoRel) :=
  ⟨Closure.coinduction hSelf, Closure.nu_fixed (Closure.phi_mono piRel rhoRel)⟩

/-- LS1 for a DC certificate: its `hSelf` field gives the inclusion at the certified state. -/
theorem ls1_of_dc {M E C S : Type*} (d : DC M E C S) :
    d.kappa d.s ⊆ Closure.nu (Closure.Phi d.piRel d.rhoRel) :=
  Closure.coinduction d.hSelf

/-! ## LS2 (L2): the decay of an unconfirmed confidence

The abstract rule of `core/circuit.jl:258` for one contingency that is not confirmed: at the update of time `now`, if
`now % 8 = 0` the confidence drops by one (not below 0); otherwise it stays. The first update after the event `t` is
the update of time `t + 1` (the statement is fixed this way, codex D2 round 5, 8). -/

/-- One unconfirmed update at time `now`. -/
def decay (now q : Nat) : Nat := if now % 8 = 0 then q - 1 else q

/-- `n` unconfirmed updates, at times `t+1, …, t+n`, from confidence `q`. -/
def decayRun (t : Nat) : Nat → Nat → Nat
  | 0, q => q
  | n + 1, q => decay (t + n + 1) (decayRun t n q)

/-- Each update lowers the confidence by at most one, and never raises it. -/
theorem decayRun_le (t n q : Nat) : decayRun t n q ≤ q := by
  induction n with
  | zero => simp [decayRun]
  | succ n ih =>
    simp only [decayRun, decay]
    split <;> omega

/-- The number of multiples of 8 among `t+1, …, t+n`. -/
def ticks (t n : Nat) : Nat := (t + n) / 8 - t / 8

theorem ticks_succ (t n : Nat) :
    ticks t (n + 1) = ticks t n + (if (t + n + 1) % 8 = 0 then 1 else 0) := by
  simp only [ticks]
  split <;> omega

/-- After `n` unconfirmed updates the confidence is `q` minus the number of decay ticks, floored at 0. -/
theorem decayRun_eq (t n q : Nat) : decayRun t n q = q - ticks t n := by
  induction n with
  | zero => simp [decayRun, ticks]
  | succ n ih =>
    rw [decayRun, ih, ticks_succ]
    simp only [decay]
    split <;> omega

/-- 32 consecutive updates always contain exactly 4 decay ticks. -/
theorem ticks_32 (t : Nat) : ticks t 32 = 4 := by
  simp only [ticks]; omega

/-- LS2a: from a confidence at most 4 (the cap `P_SMAX`), 32 consecutive unconfirmed updates leave 0. -/
theorem ls2a (t q : Nat) (hq : q ≤ 4) : decayRun t 32 q = 0 := by
  rw [decayRun_eq, ticks_32]; omega

/-- LS2b: 32 is sharp: from confidence 4 at an event `t ≡ 0 (mod 8)` (confirmed at `t`, so no decay at `t`), after
31 unconfirmed updates the confidence is still 1 (ticks at `t+8, t+16, t+24` only). -/
theorem ls2b (t : Nat) (ht : t % 8 = 0) : decayRun t 31 4 = 1 := by
  rw [decayRun_eq]; simp only [ticks]; omega

/-- LS2a for the Julia rule (codex D2 round 8, 4): besides the decay, the rule may only lower an unconfirmed confidence
(`weaken`, `core/circuit.jl:209`, `:228`); so any sequence that each step stays at or below the decay of the previous value
reaches 0 within 32 updates. The sharpness (LS2b) is claimed for the abstract rule only. -/
theorem decay_mono (now : Nat) {a b : Nat} (h : a ≤ b) : decay now a ≤ decay now b := by
  simp only [decay]; split <;> omega

theorem decayRun_mono (t n : Nat) {a b : Nat} (h : a ≤ b) : decayRun t n a ≤ decayRun t n b := by
  induction n with
  | zero => simpa [decayRun] using h
  | succ n ih => exact decay_mono _ ih

theorem ls2a_le (t : Nat) (f : Nat → Nat) (h0 : f 0 ≤ 4) (hstep : ∀ n, f (n + 1) ≤ decay (t + n + 1) (f n)) :
    f 32 = 0 := by
  have key : ∀ n, f n ≤ decayRun t n (f 0) := by
    intro n
    induction n with
    | zero => simp [decayRun]
    | succ n ih => exact le_trans (hstep n) (decay_mono _ ih)
  have h1 := key 32
  have h2 : decayRun t 32 (f 0) = 0 := ls2a t (f 0) h0
  omega

/-! ## LS9 (L9): no patch offer and no pending call ⇒ nothing is confirmed

Abstraction map to `core/circuit.jl` (codex D2 round 8, 6–8): `offersZero` reads "the patch offer vector is [0.0, 0.0]"
(`:151`; under the intervention X no patch motor acts, `:148`, so it holds); `gate` reads the gate of `:154`
(`d[1] + d[2] > 0` and every acting patch motor answered); `allocate` gives only to positive offers (`:86–91`), so a zero
offer vector gives no gate; the patch confirmation needs the gate (`:156`). `pendingBefore` is the pending call list
before the answers of the step are handled (`:220`); a call confirmation needs it non-empty. A positive allocation from
a zero offer, or a confirmation under X, refutes this map. -/

/-- One step's confirmation inputs, abstracted. -/
structure Step (K : Type) where
  offersZero : Prop
  gate : Prop
  gate_needs_offer : gate → ¬ offersZero
  patchConfirmed : K → Prop
  patch_needs_gate : ∀ k, patchConfirmed k → gate
  pendingBefore : List Nat
  callConfirmed : K → Prop
  call_needs_pending : ∀ k, callConfirmed k → pendingBefore ≠ []

/-- LS9: with a zero patch offer (as under X) and nothing pending before the answers (BODY's circuit has no calling
motor: the pending list starts empty and nothing is ever added, `:234–237`, checked on the Julia side), no contingency
is confirmed. -/
theorem ls9 {K : Type} (st : Step K) (hX : st.offersZero) (hP : st.pendingBefore = []) (k : K) :
    ¬ st.patchConfirmed k ∧ ¬ st.callConfirmed k :=
  ⟨fun h => st.gate_needs_offer (st.patch_needs_gate k h) hX, fun h => st.call_needs_pending k h hP⟩


/-! ## LSH2 (H2, RB, `discussion/notes/RB-redo.md` §2, 2026-11-09): κ_patch under X, and why κ itself does not empty

With α (`core/circuit.jl:287–289`) an unconfirmed edge decays unless its target motor has patch 4 (m0) and q0 > 0.
`decayA` is that rule on one edge; `exemptA patch q0` is the exemption flag. LSH2: an edge into a patch 1 or 2 motor
(patch ≠ 4) that is never confirmed (each update at most the decay of the previous value; under X no patch motor acts,
LS9) and starts at q ≤ 4 has q = 0 after 32 updates (stated for any non-exempt edge: κ_prec = the κ edges with
exemptA = false, the precarious ones, which can be lost), as LS2a. LSH2k: an exempt edge (patch 4, q0 > 0) is never
decreased by `decayA`, so the innate c → m0 and rb → m0 edges keep κ non-empty (the reason L2's κ cannot be used as
is in RB). The abstraction map (decayA ↔ the decay line, a patch motor's edge is not confirmed under X) is checked on
the Julia side; a confirmation or a q increase of a κ_patch edge under X refutes it. -/

def exemptA (patch q0 : Nat) : Bool := patch == 4 && decide (0 < q0)
def decayA (exempt : Bool) (now q : Nat) : Nat := if exempt then q else decay now q

theorem lsH2 (t patch q0 : Nat) (hx : exemptA patch q0 = false) (f : Nat → Nat) (h0 : f 0 ≤ 4)
    (hstep : ∀ n, f (n + 1) ≤ decayA (exemptA patch q0) (t + n + 1) (f n)) : f 32 = 0 :=
  ls2a_le t f h0 (fun n => by simpa [decayA, hx] using hstep n)

/-- Every edge into a patch 1, 2 motor is not exempt (so κ_prec contains all κ edges into patch motors and the core loops). -/
theorem exemptA_patch (patch q0 : Nat) (hp : patch ≠ 4) : exemptA patch q0 = false := by simp [exemptA, hp]

theorem lsH2k (now q q0 : Nat) (hq0 : 0 < q0) : decayA (exemptA 4 q0) now q = q := by
  simp [decayA, exemptA, hq0]

end BridgeLab.SelfMaintenance
#print axioms BridgeLab.SelfMaintenance.lsH2
#print axioms BridgeLab.SelfMaintenance.lsH2k
#print axioms BridgeLab.SelfMaintenance.exemptA_patch
