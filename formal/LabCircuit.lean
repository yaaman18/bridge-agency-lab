import ERIEC.DC
import ERIEC.Value
import ERIEC.MetaSelection
import ERIEC.TemporalDC
import Agency

/-!
# The circuit of bridge-agency-lab against DC, M4 and Agency (statements first)

User decision 2026-10-31: start the correspondence between the canonical Julia rules (`core/circuit.jl`)
and the Lean predicates of bridge-protocol by writing the Lean statements first. This file states the
correspondence. Choices D1–D6 (`formal/README.md`) were decided by the user on 2026-10-31 as recommended (item 65 of
the README); every statement here is proved (no `sorry`). Nothing in `~/bridge-protocol` is changed: this file is checked against its build
(`formal/check.sh`).

Shape of the correspondence (proposal, `formal/README.md`):
* An occurrence is one step of the circuit (`TemporalDC`: the circuit's own steps are its clock), and the
  evidence for it is a `Window`: what `core/circuit.jl` records over the last `L` steps that end there
  (`L = smax * decay = 32`, the longest a confidence survives without confirmation; a constant of the
  circuit itself, not chosen from outside).
* DC components at the occurrence: actions `M` = motors, environment `E` = receptor features, constituents
  `C` = contingencies (edges), one state (`S = Unit`, the occurrence itself).
* The elementary form `ElemDC` is what Julia computes (finite quantifiers over units and edges);
  `elemDC_iff_fields` says it is exactly the four DC fields for the relations built here.
* M4a holds by the type of the circuit's trace (no external set-point channel). M4b needs the circuit's
  seeking diagram `D`, which is a decision (D5): the plain reachability diagram makes death terminal.
* Agency's trials (`ValueNeeded`, `SelfProducing`, `SelfRepairing`) are read from finite tables measured
  in Julia; `*_iff_check` say the Boolean checks are exactly the predicates.

Read-only throughout: the window and the tables are observations; nothing is written back into the circuit
(M4a, the noninterference of `MetaSelection.SigmaPure`). `phenomenal_claim` is not touched.
-/

namespace BridgeLab

open ERIEC

/-! ## The circuit's wiring (`core/circuit.jl`, `newborn`) -/

/-- Unit kinds of `core/circuit.jl` ('R', 'C', 'M'). -/
inductive Kind
  | receptor
  | core
  | motor
  deriving DecidableEq

/-- Units and directed contingencies (edges) of a circuit. -/
structure Net where
  nU : Nat
  nK : Nat
  kind : Fin nU → Kind
  src : Fin nK → Fin nU
  dst : Fin nK → Fin nU

namespace Net

variable (N : Net)

abbrev isMotor (u : Fin N.nU) : Prop := N.kind u = .motor
abbrev isReceptor (u : Fin N.nU) : Prop := N.kind u = .receptor


/-- D3: a contingency of the self, as opposed to a sensorimotor one: its source is not a receptor (core
loops and core-to-motor drives). -/
abbrev selfEdge (k : Fin N.nK) : Prop := ¬ N.isReceptor (N.src k)

/-- The boundary: contingencies that reach the world through a motor. -/
def boundary : Set (Fin N.nK) := {k | N.isMotor (N.dst k)}

end Net

/-! ## The evidence for one occurrence -/

/-- What `core/circuit.jl` records for an occurrence `x` and the window of `L` steps ending at `x`. -/
structure Window (N : Net) where
  /-- confidence `q ≥ 1` at `x` -/
  kept : Fin N.nK → Bool
  /-- the receptor is on at `x` -/
  on : Fin N.nU → Bool
  /-- within the window, edge `k` was confirmed at a step where motor `m` acted and was answered
  (for the call motor: answered within `W` steps, the deferred confirmation of `circuit.jl`) -/
  reproduced : Fin N.nU → Fin N.nK → Bool
  /-- D4: acts of motor `m` change the feature read by receptor `e` (the world's structure: declared
  from the world's rules or measured by intervention; the circuit is not told it) -/
  affects : Fin N.nU → Fin N.nU → Bool
  /-- within the window, edge `k` was confirmed at a step where receptor `e` drove the answered act
  (used for the structural value of the coupling `e`, `Value.viabilityContribution`) -/
  reproducedVia : Fin N.nU → Fin N.nK → Bool

namespace Window

variable {N : Net} (w : Window N)

/-! ### DC components (types `M = E = Fin N.nU`, `C = Fin N.nK`, `S = Unit`) -/

/-- κ: the self's contingencies kept at the occurrence (D3). -/
def kappa : Unit → Set (Fin N.nK) := fun _ => {k | w.kept k = true ∧ N.selfEdge k}

/-- ρ: a kept contingency enables the motor it drives, directly or through one kept contingency from
the unit it drives. -/
def rhoRel : Fin N.nK → Set (Fin N.nU) := fun k =>
  {m | N.isMotor m ∧ (N.dst k = m ∨ ∃ k', w.kept k' = true ∧ N.src k' = N.dst k ∧ N.dst k' = m)}

/-- π: an answered act of motor `m` re-produces the contingencies confirmed with it in the window. -/
def piRel : Fin N.nU → Set (Fin N.nK) := fun m => {k | N.isMotor m ∧ w.reproduced m k = true}

/-- σ: receptor `e` drives motor `m` through a kept contingency. -/
def sigmaRel : Fin N.nU → Set (Fin N.nU) := fun e =>
  {m | N.isMotor m ∧ N.isReceptor e ∧ ∃ k, w.kept k = true ∧ N.src k = e ∧ N.dst k = m}

/-- α: acts of motor `m` reach the feature of receptor `e` (D4). -/
def alphaRel : Fin N.nU → Set (Fin N.nU) := fun m => {e | N.isMotor m ∧ N.isReceptor e ∧ w.affects m e = true}

/-- A receptor is coupled when some act reaches its feature (D4: noise and clock receptors are not). -/
def coupled (e : Fin N.nU) : Prop := ∃ m, N.isMotor m ∧ w.affects m e = true

/-- ε: the coupled receptors that are on at the occurrence. -/
def epsilon : Unit → Set (Fin N.nU) := fun _ => {e | N.isReceptor e ∧ w.on e = true ∧ w.coupled e}

/-! ### The elementary form (what Julia computes) -/

/-- hSelf, elementary: every kept self contingency is re-produced by an answered act of a motor that
some kept self contingency enables. -/
def ElemSelf : Prop :=
  ∀ k, w.kept k = true → N.selfEdge k →
    ∃ k' m, w.kept k' = true ∧ N.selfEdge k' ∧ N.isMotor m ∧
      (N.dst k' = m ∨ ∃ k'', w.kept k'' = true ∧ N.src k'' = N.dst k' ∧ N.dst k'' = m) ∧
      w.reproduced m k = true

/-- hSMC, elementary: every coupled receptor that is on is reached by the act of a motor that some
coupled receptor that is on drives through a kept contingency. -/
def ElemSMC : Prop :=
  ∀ e, N.isReceptor e → w.on e = true → (∃ m, N.isMotor m ∧ w.affects m e = true) →
    ∃ e' m, N.isReceptor e' ∧ w.on e' = true ∧ (∃ m', N.isMotor m' ∧ w.affects m' e' = true) ∧
      N.isMotor m ∧ (∃ k, w.kept k = true ∧ N.src k = e' ∧ N.dst k = m) ∧ w.affects m e = true

/-- hAct, elementary: some motor is both enabled by a kept self contingency and driven by a coupled
receptor that is on. -/
def ElemAct : Prop :=
  ∃ m, N.isMotor m ∧
    (∃ k, w.kept k = true ∧ N.selfEdge k ∧
      (N.dst k = m ∨ ∃ k', w.kept k' = true ∧ N.src k' = N.dst k ∧ N.dst k' = m)) ∧
    (∃ e, N.isReceptor e ∧ w.on e = true ∧ (∃ m', N.isMotor m' ∧ w.affects m' e = true) ∧
      ∃ k, w.kept k = true ∧ N.src k = e ∧ N.dst k = m)

/-- hBound, elementary: some kept self contingency drives a motor. -/
def ElemBound : Prop := ∃ k, w.kept k = true ∧ N.selfEdge k ∧ N.isMotor (N.dst k)

def ElemDC : Prop := w.ElemSelf ∧ w.ElemSMC ∧ w.ElemAct ∧ w.ElemBound

instance : Decidable w.ElemSelf := by unfold ElemSelf; infer_instance
instance : Decidable w.ElemSMC := by unfold ElemSMC; infer_instance
instance : Decidable w.ElemAct := by unfold ElemAct; infer_instance
instance : Decidable w.ElemBound := by unfold ElemBound; infer_instance
instance : Decidable w.ElemDC := by unfold ElemDC; infer_instance

/-- The check Julia runs (`formal/README.md`: Julia implements exactly this form). -/
def checkDC : Bool := decide w.ElemDC

/-! ### Statements -/

theorem mem_pi_star' {M C : Type*} (r : M → Set C) (A : Set M) (c : C) :
    c ∈ Closure.pi_star r A ↔ ∃ m, m ∈ A ∧ c ∈ r m := by
  simp [Closure.pi_star]
theorem mem_rho_star' {M C : Type*} (r : C → Set M) (Y : Set C) (m : M) :
    m ∈ Closure.rho_star r Y ↔ ∃ c, c ∈ Y ∧ m ∈ r c := by
  simp [Closure.rho_star]
theorem mem_alpha_star' {M E : Type*} (r : M → Set E) (A : Set M) (e : E) :
    e ∈ Adj.alpha_star r A ↔ ∃ m, m ∈ A ∧ e ∈ r m := by
  simp [Adj.alpha_star]
theorem mem_sigma_star' {M E : Type*} (r : E → Set M) (X : Set E) (m : M) :
    m ∈ Adj.sigma_star r X ↔ ∃ e, e ∈ X ∧ m ∈ r e := by
  simp [Adj.sigma_star]

theorem self_iff : w.ElemSelf ↔ w.kappa () ⊆ Closure.Phi w.piRel w.rhoRel (w.kappa ()) := by
  constructor
  · intro h k hk
    have hk' : w.kept k = true ∧ N.selfEdge k := hk
    obtain ⟨k', m, h1, h2, h3, h4, h5⟩ := h k hk'.1 hk'.2
    show k ∈ Closure.pi_star w.piRel (Closure.rho_star w.rhoRel (w.kappa ()))
    rw [mem_pi_star']
    refine ⟨m, ?_, (show N.isMotor m ∧ w.reproduced m k = true from ⟨h3, h5⟩)⟩
    rw [mem_rho_star']
    exact ⟨k', (show w.kept k' = true ∧ N.selfEdge k' from ⟨h1, h2⟩), (show N.isMotor m ∧ _ from ⟨h3, h4⟩)⟩
  · intro h k hk hs
    have h2 := h (show k ∈ w.kappa () from (show w.kept k = true ∧ N.selfEdge k from ⟨hk, hs⟩))
    change k ∈ Closure.pi_star w.piRel (Closure.rho_star w.rhoRel (w.kappa ())) at h2
    rw [mem_pi_star'] at h2
    obtain ⟨m, hm1, hm2⟩ := h2
    rw [mem_rho_star'] at hm1
    obtain ⟨k', hk', hmk⟩ := hm1
    have hk'' : w.kept k' = true ∧ N.selfEdge k' := hk'
    have hmk' : N.isMotor m ∧ (N.dst k' = m ∨ ∃ k'', w.kept k'' = true ∧ N.src k'' = N.dst k' ∧ N.dst k'' = m) := hmk
    have hm2' : N.isMotor m ∧ w.reproduced m k = true := hm2
    exact ⟨k', m, hk''.1, hk''.2, hmk'.1, hmk'.2, hm2'.2⟩

theorem smc_iff : w.ElemSMC ↔ w.epsilon () ⊆ Hinge.T_prime w.alphaRel w.sigmaRel (w.epsilon ()) := by
  constructor
  · intro h e he
    have he' : N.isReceptor e ∧ w.on e = true ∧ w.coupled e := he
    obtain ⟨e', m, h1, h2, h3, h4, h5, h6⟩ := h e he'.1 he'.2.1 he'.2.2
    show e ∈ Adj.alpha_star w.alphaRel (Adj.sigma_star w.sigmaRel (w.epsilon ()))
    rw [mem_alpha_star']
    refine ⟨m, ?_, (show N.isMotor m ∧ N.isReceptor e ∧ w.affects m e = true from ⟨h4, he'.1, h6⟩)⟩
    rw [mem_sigma_star']
    exact ⟨e', (show N.isReceptor e' ∧ w.on e' = true ∧ w.coupled e' from ⟨h1, h2, h3⟩),
      (show N.isMotor m ∧ N.isReceptor e' ∧ _ from ⟨h4, h1, h5⟩)⟩
  · intro h e hr hon hc
    have h2 := h (show e ∈ w.epsilon () from (show N.isReceptor e ∧ w.on e = true ∧ w.coupled e from ⟨hr, hon, hc⟩))
    change e ∈ Adj.alpha_star w.alphaRel (Adj.sigma_star w.sigmaRel (w.epsilon ())) at h2
    rw [mem_alpha_star'] at h2
    obtain ⟨m, hm1, hm2⟩ := h2
    rw [mem_sigma_star'] at hm1
    obtain ⟨e', he', hme⟩ := hm1
    have he'' : N.isReceptor e' ∧ w.on e' = true ∧ w.coupled e' := he'
    have hme' : N.isMotor m ∧ N.isReceptor e' ∧ ∃ k, w.kept k = true ∧ N.src k = e' ∧ N.dst k = m := hme
    have hm2' : N.isMotor m ∧ N.isReceptor e ∧ w.affects m e = true := hm2
    exact ⟨e', m, he''.1, he''.2.1, he''.2.2, hme'.1, hme'.2.2, hm2'.2.2⟩

theorem act_iff : w.ElemAct ↔ (Hinge.Act w.rhoRel w.sigmaRel w.kappa w.epsilon ()).Nonempty := by
  constructor
  · rintro ⟨m, hm, ⟨k, hk1, hk2, hk3⟩, ⟨e, he1, he2, he3, k2, hk21, hk22, hk23⟩⟩
    refine ⟨m, ?_, ?_⟩
    · rw [mem_rho_star']
      exact ⟨k, (show w.kept k = true ∧ N.selfEdge k from ⟨hk1, hk2⟩), (show N.isMotor m ∧ _ from ⟨hm, hk3⟩)⟩
    · rw [mem_sigma_star']
      exact ⟨e, (show N.isReceptor e ∧ w.on e = true ∧ w.coupled e from ⟨he1, he2, he3⟩),
        (show N.isMotor m ∧ N.isReceptor e ∧ _ from ⟨hm, he1, k2, hk21, hk22, hk23⟩)⟩
  · rintro ⟨m, h1, h2⟩
    rw [mem_rho_star'] at h1
    rw [mem_sigma_star'] at h2
    obtain ⟨k, hk, hmk⟩ := h1
    obtain ⟨e, he, hme⟩ := h2
    have hk' : w.kept k = true ∧ N.selfEdge k := hk
    have hmk' : N.isMotor m ∧ (N.dst k = m ∨ ∃ k', w.kept k' = true ∧ N.src k' = N.dst k ∧ N.dst k' = m) := hmk
    have he' : N.isReceptor e ∧ w.on e = true ∧ w.coupled e := he
    have hme' : N.isMotor m ∧ N.isReceptor e ∧ ∃ k, w.kept k = true ∧ N.src k = e ∧ N.dst k = m := hme
    exact ⟨m, hmk'.1, ⟨k, hk'.1, hk'.2, hmk'.2⟩, ⟨e, he'.1, he'.2.1, he'.2.2, hme'.2.2⟩⟩

theorem bound_iff : w.ElemBound ↔ (w.kappa () ∩ N.boundary).Nonempty := by
  constructor
  · rintro ⟨k, h1, h2, h3⟩
    exact ⟨k, (show w.kept k = true ∧ N.selfEdge k from ⟨h1, h2⟩), h3⟩
  · rintro ⟨k, hk, hb⟩
    have hk' : w.kept k = true ∧ N.selfEdge k := hk
    exact ⟨k, hk'.1, hk'.2, hb⟩

/-- The elementary form is exactly the four DC fields for the relations built from the window. -/
theorem elemDC_iff_fields :
    w.ElemDC ↔
      (w.kappa () ⊆ Closure.Phi w.piRel w.rhoRel (w.kappa ()) ∧
       w.epsilon () ⊆ Hinge.T_prime w.alphaRel w.sigmaRel (w.epsilon ()) ∧
       (Hinge.Act w.rhoRel w.sigmaRel w.kappa w.epsilon ()).Nonempty ∧
       (w.kappa () ∩ N.boundary).Nonempty) := by
  unfold ElemDC
  rw [w.self_iff, w.smc_iff, w.act_iff, w.bound_iff]

/-- The DC certificate of the occurrence, from the elementary form. -/
def toDC (h : w.ElemDC) : DC (Fin N.nU) (Fin N.nU) (Fin N.nK) Unit where
  alphaRel := w.alphaRel
  sigmaRel := w.sigmaRel
  piRel := w.piRel
  rhoRel := w.rhoRel
  kappa := w.kappa
  epsilon := w.epsilon
  boundary := N.boundary
  s := ()
  hSelf := ((w.elemDC_iff_fields).1 h).1
  hSMC := ((w.elemDC_iff_fields).1 h).2.1
  hAct := ((w.elemDC_iff_fields).1 h).2.2.1
  hBound := ((w.elemDC_iff_fields).1 h).2.2.2

/-- Soundness of the Julia check: `true` gives a DC certificate. -/
theorem dc_of_check (h : w.checkDC = true) :
    Nonempty (DC (Fin N.nU) (Fin N.nU) (Fin N.nK) Unit) :=
  ⟨w.toDC (of_decide_eq_true h)⟩

/-- Completeness for these relations: if the DC fields hold for them, the Julia check says `true`. -/
theorem check_of_fields
    (h : w.kappa () ⊆ Closure.Phi w.piRel w.rhoRel (w.kappa ()) ∧
       w.epsilon () ⊆ Hinge.T_prime w.alphaRel w.sigmaRel (w.epsilon ()) ∧
       (Hinge.Act w.rhoRel w.sigmaRel w.kappa w.epsilon ()).Nonempty ∧
       (w.kappa () ∩ N.boundary).Nonempty) :
    w.checkDC = true :=
  decide_eq_true ((w.elemDC_iff_fields).2 h)

/-- No hinge without a coupled receptor that is on (a consequence to be proved: an occurrence where only
the noise and clock receptors are on carries no DC certificate). -/
theorem no_dc_without_coupled_input (h : ∀ e, w.on e = true → ¬ w.coupled e) : ¬ w.ElemDC := by
  rintro ⟨-, -, ⟨m, -, -, ⟨e, -, he2, he3, -⟩⟩, -⟩
  exact h e he2 he3

/-! ### D4 with a state-dependent α (item 69, user 2026-11-01)

The declared reach of each motor (item 67) is opened or closed by the medium's state at the occurrence: a motor's
acts reach its features only while they can change the medium. -/

/-- The gated α: motor `m` reaches `e` iff its gate is open at the occurrence and `e` is in its declared reach. -/
def gatedAffects (N : Net) (reach : Fin N.nU → Fin N.nU → Bool) (gate : Fin N.nU → Bool) :
    Fin N.nU → Fin N.nU → Bool :=
  fun m e => gate m && reach m e

/-- The lab's gate (`core/dc.jl`): the patch motors only in the world phase while their patch yields (an act then
takes a positive share and the pool decreases; the nursery and school yields are scripted), the call only while the
partner is live. `patchOf` is the motor's patch (1, 2, 3 = the call; 0 otherwise). -/
def labGate (N : Net) (patchOf : Fin N.nU → Nat) (inWorld y1pos y2pos partnerLive : Bool) : Fin N.nU → Bool :=
  fun m => match patchOf m with
    | 1 => inWorld && y1pos
    | 2 => inWorld && y2pos
    | 3 => partnerLive
    | _ => false

/-- With every motor's gate closed, nothing is coupled, so the occurrence carries no DC certificate. -/
theorem no_dc_when_gate_closed (reach : Fin N.nU → Fin N.nU → Bool) (gate : Fin N.nU → Bool)
    (hA : w.affects = gatedAffects N reach gate) (hc : ∀ m, N.isMotor m → gate m = false) : ¬ w.ElemDC := by
  apply w.no_dc_without_coupled_input
  rintro e - ⟨m, hm, hme⟩
  rw [hA] at hme
  simp [gatedAffects, hc m hm] at hme

/-- DQ7: before the world phase (nursery, school) and without a live partner, the lab's gate is closed for every
motor, so no occurrence carries a DC certificate. -/
theorem no_dc_before_world_without_partner (reach : Fin N.nU → Fin N.nU → Bool) (patchOf : Fin N.nU → Nat)
    (y1pos y2pos : Bool) (hA : w.affects = gatedAffects N reach (labGate N patchOf false y1pos y2pos false)) :
    ¬ w.ElemDC := by
  refine w.no_dc_when_gate_closed reach _ hA (fun m _ => ?_)
  unfold labGate
  split <;> simp

/-- The gated α never couples more than the declared one. -/
theorem gated_le_reach (reach : Fin N.nU → Fin N.nU → Bool) (gate : Fin N.nU → Bool) (m e : Fin N.nU)
    (h : gatedAffects N reach gate m e = true) : reach m e = true := by
  simp [gatedAffects] at h
  exact h.2

end Window

/-! ## DC over the circuit's own clock (`TemporalDC`) -/

/-- D2 (decided 2026-10-31 as recommended): the certification of a generated trace by the windows of its occurrences.
Named assumption SHARED-TICK: in the lab's runs the world and the circuit advance on one common step, which is taken
as the occurrence clock; TemporalDC's requirement that the TRM itself generates the ticks is not claimed. -/
def certification {A : OpenEvolution.OpenSystem} (T : TemporalDC.GeneratedTrace A) (N : Net)
    (window : T.Occurrence → Window N) : TemporalDC.Certification T :=
  ⟨fun x => (window x).ElemDC⟩

/-! ## M4 -/

/-- The circuit's protected trace has no external set-point channel: its type is `Empty`. -/
abbrev CircuitTrace (NuPhi Value Obj Action : Type*) :=
  MetaSelection.InternalTrace Empty NuPhi Value Obj Action

/-- M4a holds for every trace of the circuit, by its type (the circuit has no target input). -/
theorem m4a_circuit {NuPhi Value Obj Action : Type*} (t : CircuitTrace NuPhi Value Obj Action) :
    t.M4a := by
  cases h : t.externalSetPoint with
  | none => exact h
  | some x => exact x.elim

/-- D5 (why the seeking diagram must be chosen, not read off the dynamics): if some state is reachable
from every state, as death is for a precarious system (M1), the plain reachability diagram has a
terminal object, so M4b read on it would fail for every precarious system. -/
theorem reachability_terminal_of_absorbing {σ : Type*} (next : σ → σ → Prop) (dead : σ)
    (h : ∀ x, TemporalDC.Reachable next x dead) :
    Body.HasTerminalSetPoint (⟨TemporalDC.Reachable next⟩ : Body.SetPointDiagram σ) :=
  ⟨dead, h⟩

/-! ## M4b over living occurrences (D5, decided 2026-10-31 as recommended) -/

/-- Occurrences of a being with which of them are living (carry a DC certificate) and which act (some motor acts). -/
structure SeekingTrace where
  Occ : Type
  next : Occ → Occ → Prop
  living : Occ → Prop
  acts : Occ → Prop

namespace SeekingTrace

variable (T : SeekingTrace)

/-- A set point: a living occurrence where acting has stopped and from which no living occurrence acts again. -/
def SetPoint (t : T.Occ) : Prop :=
  T.living t ∧ ¬ T.acts t ∧ ∀ y, TemporalDC.Reachable T.next t y → T.living y → ¬ T.acts y

/-- D5: the seeking diagram. Its objects are the living occurrences only (death carries no DC certificate, so it is
not an object and cannot be terminal, unlike in `reachability_terminal_of_absorbing`); `x` reaches `t` when `t` is a
set point reachable from `x` by the being's own transitions. -/
def diagram : Body.SetPointDiagram {x // T.living x} :=
  ⟨fun x t => TemporalDC.Reachable T.next x.1 t.1 ∧ T.SetPoint t.1⟩

/-- M4b in the reading of D5. -/
def M4b : Prop := Body.NoTerminalSetPoint T.diagram

/-- A being that acts at every living occurrence has no terminal set point. -/
theorem m4b_of_acting (h : ∀ x, T.living x → T.acts x) : T.M4b := by
  rintro ⟨t, ht⟩
  exact (ht t).2.2.1 (h t.1 t.2)

end SeekingTrace

/-- A recorded run of `n` occurrences (one step to the next), with the Julia check's verdicts. -/
def finiteTrace (n : Nat) (living acts : Fin n → Bool) : SeekingTrace :=
  ⟨Fin n, fun i j => j.val = i.val + 1, fun i => living i = true, fun i => acts i = true⟩

/-- The Julia check for M4b on a recorded run: every living occurrence acts. Sufficient, not necessary. -/
def checkM4b (n : Nat) (living acts : Fin n → Bool) : Bool :=
  decide (∀ i, living i = true → acts i = true)

theorem m4b_of_check {n : Nat} {living acts : Fin n → Bool} (h : checkM4b n living acts = true) :
    (finiteTrace n living acts).M4b := by
  have h' : ∀ i : Fin n, living i = true → acts i = true := by simpa [checkM4b] using h
  exact (finiteTrace n living acts).m4b_of_acting h'

/-! ## Agency's trials from tables measured in Julia -/

section Trials

open ERIEC.Agency

/-- A survival table: `tab p v` = the variant `v` survives perturbation `p` (D6: what survival and the
ablation are for the circuit is a decision). -/
def survivalTrialOf {P : Type*} (tab : P → Variant → Bool) : SurvivalTrial P :=
  ⟨fun p v => tab p v = true⟩

def checkValueNeeded {P : Type*} [Fintype P] (tab : P → Variant → Bool) : Bool :=
  decide ((∃ p, tab p .intact = true ∧ tab p .ablated = false) ∧
          (∀ p, tab p .ablated = true → tab p .intact = true))

theorem valueNeeded_iff_check {P : Type*} [Fintype P] (tab : P → Variant → Bool) :
    ValueNeeded (survivalTrialOf tab) ↔ checkValueNeeded tab = true := by
  simp [ValueNeeded, checkValueNeeded, survivalTrialOf]

def structureTrialOf {Q : Type*} (tab : Q → Variant → Bool) : StructureTrial Q :=
  ⟨fun q v => tab q v = true⟩

def checkSelfProducing {Q : Type*} [Fintype Q] (tab : Q → Variant → Bool) : Bool :=
  decide ((∀ q, tab q .ablated = false) ∧ (∃ q, tab q .intact = true))

theorem selfProducing_iff_check {Q : Type*} [Fintype Q] (tab : Q → Variant → Bool) :
    SelfProducing (structureTrialOf tab) ↔ checkSelfProducing tab = true := by
  simp [SelfProducing, checkSelfProducing, structureTrialOf]

def repairTrialOf {D : Type*} (tab : D → Variant → Bool) : RepairTrial D :=
  ⟨fun d v => tab d v = true⟩

def checkSelfRepairing {D : Type*} [Fintype D] (tab : D → Variant → Bool) : Bool :=
  decide (0 < Fintype.card D ∧ (∀ d, tab d .intact = true) ∧ (∀ d, tab d .ablated = false))

theorem selfRepairing_iff_check {D : Type*} [Fintype D] (tab : D → Variant → Bool) :
    SelfRepairing (repairTrialOf tab) ↔ checkSelfRepairing tab = true := by
  simp [SelfRepairing, checkSelfRepairing, repairTrialOf, Fintype.card_pos_iff]

/-- The structural value of coupling `e`: the kept self contingencies re-produced with `e` driving. -/
def nuPhiOf {N : Net} (w : Window N) : Finset (Fin N.nK) :=
  Finset.univ.filter fun k => w.kept k = true ∧ N.selfEdge k

def contributionOf {N : Net} (w : Window N) : Fin N.nU → Finset (Fin N.nK) := fun e =>
  Finset.univ.filter fun k => w.reproducedVia e k = true

/-- An agent from the Julia checks: DC at the occurrence, actions that differ with the structural value
(measured choice sets `act`), and the survival table. -/
def agentOf {N : Net} (w : Window N) {P A : Type*} [Fintype P] (act : Fin N.nU → Set A)
    (hdc : w.checkDC = true)
    (hdiff : ValueDifferentiated (Value.viabilityContribution (nuPhiOf w) (contributionOf w)) act)
    (tab : P → Variant → Bool) (hneed : checkValueNeeded tab = true) :
    Agent (Fin N.nU) (Fin N.nU) (Fin N.nK) Unit P A where
  dc := w.toDC (of_decide_eq_true hdc)
  nuPhi := nuPhiOf w
  contribution := contributionOf w
  act := act
  differentiated := hdiff
  trial := survivalTrialOf tab
  needed := (valueNeeded_iff_check tab).2 hneed

end Trials

/-! ## The idle-first choice (item 72, user 2026-11-01 "推奨どおりでいい、固定化を解く規則変更から進めて")

Item 71: the motor that wins first gathers confidence and keeps winning (lock-in), because `core/circuit.jl` ranks the
candidate patch motors by their confident inputs, and a motor that never acts is never confirmed. The rule change
(`step!(...; idle_first = true)`, opt-in) prefers, among the candidates, a motor that has not acted for longer than
`FORGET` steps (the circuit's own constant, the same `idle` as learn3/bin3); the old ranking decides among the rest.
Two patch motors: `l1 l2` the steps at which each last acted, `pref` the old rule's winner (`true` = m1). -/

namespace IdleFirst

/-- The motor that last acted at `l` is idle at step `now`. -/
def idle (F now l : Nat) : Bool := decide (F < now - l)

/-- The winner between two candidate patch motors (`true` = m1): the only idle one, else the old rule's. -/
def pick (F now l1 l2 : Nat) (pref : Bool) : Bool :=
  if idle F now l1 && !idle F now l2 then true
  else if idle F now l2 && !idle F now l1 then false
  else pref

/-- Conservative: when both or neither are idle, the old rule decides. -/
theorem pick_eq_pref (F now l1 l2 : Nat) (pref : Bool) (h : idle F now l1 = idle F now l2) :
    pick F now l1 l2 pref = pref := by
  unfold pick; cases h1 : idle F now l1 <;> cases h2 : idle F now l2 <;> simp_all

/-- The only idle candidate wins. -/
theorem pick_idle (F now l1 l2 : Nat) (pref : Bool) (h1 : idle F now l1 = true) (h2 : idle F now l2 = false) :
    pick F now l1 l2 pref = true := by simp [pick, h1, h2]

/-- A run where both patch motors are candidates at every step and nothing is silenced (the winner acts):
`now` the step, `l1 l2` the last acts; `pref n` is the old rule's winner at step `n` (any sequence). -/
structure S where
  now : Nat
  l1 : Nat
  l2 : Nat

def stepS (F : Nat) (pref : Nat → Bool) (s : S) : S :=
  if pick F (s.now + 1) s.l1 s.l2 (pref (s.now + 1)) then ⟨s.now + 1, s.now + 1, s.l2⟩ else ⟨s.now + 1, s.l1, s.now + 1⟩

def run (F : Nat) (pref : Nat → Bool) : Nat → S
  | 0 => ⟨0, 0, 0⟩
  | k + 1 => stepS F pref (run F pref k)

/-- The old rule alone (`pick` replaced by `pref`) can lock a motor out: with `pref` always m1, m2 never acts. -/
def runOld (pref : Nat → Bool) : Nat → S
  | 0 => ⟨0, 0, 0⟩
  | k + 1 => let s := runOld pref k
             if pref (s.now + 1) then ⟨s.now + 1, s.now + 1, s.l2⟩ else ⟨s.now + 1, s.l1, s.now + 1⟩

theorem old_rule_locks (k : Nat) : (runOld (fun _ => true) k).l2 = 0 := by
  induction k with
  | zero => rfl
  | succ k ih => simp [runOld, ih]

private def Inv (F : Nat) (s : S) : Prop :=
  s.l1 ≤ s.now ∧ s.l2 ≤ s.now ∧ s.now - s.l1 ≤ F ∧ s.now - s.l2 ≤ F ∧ (s.l1 = s.now ∨ s.l2 = s.now)

private theorem inv_step (F : Nat) (hF : 1 ≤ F) (pref : Nat → Bool) (s : S) (h : Inv F s) : Inv F (stepS F pref s) := by
  obtain ⟨a, b, c, d, e⟩ := h
  unfold stepS pick idle
  split_ifs with h1 h2 h3 <;> simp_all [Inv] <;> omega

theorem inv_run (F : Nat) (hF : 1 ≤ F) (pref : Nat → Bool) (k : Nat) : Inv F (run F pref k) := by
  induction k with
  | zero => simp [run, Inv]
  | succ k ih => exact inv_step F hF pref _ ih

/-- No lock-out: under the idle-first choice, while both patch motors are candidates at every step, neither goes more
than `F` steps without acting, whatever the old rule prefers (for the circuit, `F = FORGET = 100`). -/
theorem no_lockout (F : Nat) (hF : 1 ≤ F) (pref : Nat → Bool) (k : Nat) :
    (run F pref k).now - (run F pref k).l1 ≤ F ∧ (run F pref k).now - (run F pref k).l2 ≤ F :=
  let ⟨_, _, c, d, _⟩ := inv_run F hF pref k; ⟨c, d⟩

end IdleFirst

/-! ## The core gate (item 76, step 2; lab option `step!(...; core_gate = true)`)

AGENCY-001's hinge (`core_enables_action`) asks that silencing the core changes the choice. In the newborn wiring every
receptor reaches every motor directly, so two confident receptor inputs reach a motor's threshold without the core
(item 75). The gate: a patch motor comes on only if its input reaches the threshold and some contingency from a core
unit drove it. -/

namespace CoreGate

variable (N : Net)

/-- Some contingency from a core unit drove motor `m` (`drove k`: the edge counted this step, `core/circuit.jl`). -/
def coreDrive (drove : Fin N.nK → Bool) (m : Fin N.nU) : Bool :=
  decide (∃ k, N.dst k = m ∧ N.kind (N.src k) = .core ∧ drove k = true)

/-- The gated motor: threshold and a core drive. -/
def motorOn (theta total : Nat) (drove : Fin N.nK → Bool) (m : Fin N.nU) : Bool :=
  decide (theta ≤ total) && coreDrive N drove m

/-- The gate never adds an act: a gated motor that is on also reaches its threshold. -/
theorem gate_le (theta total : Nat) (drove : Fin N.nK → Bool) (m : Fin N.nU)
    (h : motorOn N theta total drove m = true) : theta ≤ total := by
  simp [motorOn] at h; exact h.1

/-- With every core unit silenced (a silenced source drives nothing), no gated motor comes on. -/
theorem off_when_core_silenced (sil : Fin N.nU → Bool) (drove : Fin N.nK → Bool)
    (hd : ∀ k, drove k = true → sil (N.src k) = false) (hs : ∀ u, N.kind u = .core → sil u = true)
    (theta total : Nat) (m : Fin N.nU) : motorOn N theta total drove m = false := by
  simp only [motorOn, coreDrive, Bool.and_eq_false_iff, decide_eq_false_iff_not]
  right
  rintro ⟨k, -, hc, hk⟩
  have h1 := hd k hk; have h2 := hs _ hc
  rw [h1] at h2; exact Bool.false_ne_true h2

end CoreGate

end BridgeLab

#print axioms BridgeLab.Window.elemDC_iff_fields
#print axioms BridgeLab.Window.dc_of_check
#print axioms BridgeLab.Window.check_of_fields
#print axioms BridgeLab.Window.no_dc_without_coupled_input
#print axioms BridgeLab.Window.no_dc_when_gate_closed
#print axioms BridgeLab.Window.no_dc_before_world_without_partner
#print axioms BridgeLab.Window.gated_le_reach
#print axioms BridgeLab.m4a_circuit
#print axioms BridgeLab.reachability_terminal_of_absorbing
#print axioms BridgeLab.m4b_of_check
#print axioms BridgeLab.valueNeeded_iff_check
#print axioms BridgeLab.selfProducing_iff_check
#print axioms BridgeLab.selfRepairing_iff_check
#print axioms BridgeLab.agentOf
#print axioms BridgeLab.IdleFirst.pick_eq_pref
#print axioms BridgeLab.IdleFirst.pick_idle
#print axioms BridgeLab.IdleFirst.old_rule_locks
#print axioms BridgeLab.IdleFirst.no_lockout
#print axioms BridgeLab.CoreGate.gate_le
#print axioms BridgeLab.CoreGate.off_when_core_silenced
