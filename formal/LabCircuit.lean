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

/-! ## Seen both before growing (item 79; lab option `step!(...; seen_both = true)`)

bin3 lets a receptor->motor contingency grow while its contrast is undefined ("not seen both": no answer rate yet with
the receptor on, or none with it off). Item 78: with more receptors, receptors that stay on through a phase gain
confidence this way and push out the ones that track the richer patch. The change: a contingency grows only when it has
been seen both ways (since its statistics were last emptied) and its contrast passes. Samples: (receptor on?, answered?)
of the motor's acts. -/

namespace SeenBoth

/-- Seen both ways: some sampled act with the receptor on and some with it off. -/
def seenBoth (samples : List (Bool × Bool)) : Bool := samples.any (·.1) && samples.any (!·.1)

/-- bin3's gate on growth: an undefined contrast passes. -/
def passesOld (samples : List (Bool × Bool)) (contrastOk : Bool) : Bool := !seenBoth samples || contrastOk

/-- The changed gate: it passes only when seen both ways and the contrast passes. -/
def passesNew (samples : List (Bool × Bool)) (contrastOk : Bool) : Bool := seenBoth samples && contrastOk

/-- The change never lets more through than bin3. -/
theorem new_le_old (samples : List (Bool × Bool)) (c : Bool) (h : passesNew samples c = true) :
    passesOld samples c = true := by
  simp [passesNew, passesOld] at *; exact Or.inr h.2

/-- Where both are defined, the two gates agree (the change only touches the undefined contrast). -/
theorem agree_when_seen (samples : List (Bool × Bool)) (c : Bool) (h : seenBoth samples = true) :
    passesNew samples c = passesOld samples c := by
  simp [passesNew, passesOld, h]

/-- A receptor that was on at every sampled act (such as y1>=1 through the school) never passes the changed gate,
whatever the answers. -/
theorem always_on_never_passes (samples : List (Bool × Bool)) (c : Bool) (h : ∀ x ∈ samples, x.1 = true) :
    passesNew samples c = false := by
  have : samples.any (!·.1) = false := by
    rw [List.any_eq_false]; intro x hx; simp [h x hx]
  simp [passesNew, seenBoth, this]

end SeenBoth

/-! ## Item 84: sed_fade (lab option, default off)

The sediment of a contingency that has not been confirmed for a multiple of F (= FORGET) steps falls by one. A confirmed
contingency is untouched (the old rule decides it). Statements first (user 2026-11-03 "じゃあ今日はそこからスタート"). -/
namespace SedFade

/-- One contingency: its sediment and the steps since it was last confirmed. -/
structure E where
  sg : Nat
  age : Nat

/-- The fade on an unconfirmed step: the age grows, and at every multiple of F the sediment falls by one. -/
def fade (F : Nat) (e : E) : E :=
  let a := e.age + 1
  { sg := if F ≤ a ∧ a % F = 0 then e.sg - 1 else e.sg, age := a }

/-- The changed rule: a confirmed step is the old rule's (`old`, which sets the age to 0); otherwise the fade. -/
def stepNew (F : Nat) (old : E → E) (confirmed : Bool) (e : E) : E := if confirmed then old e else fade F e

/-- The fade never adds sediment. -/
theorem fade_le (F : Nat) (e : E) : (fade F e).sg ≤ e.sg := by
  simp only [fade]; split_ifs <;> omega

/-- A confirmed contingency is decided by the old rule alone. -/
theorem confirmed_untouched (F : Nat) (old : E → E) (e : E) : stepNew F old true e = old e := by
  simp [stepNew]

/-- `n` unconfirmed steps from a fresh confirmation. -/
def runU (F : Nat) (e0 : E) : Nat → E
  | 0 => e0
  | n + 1 => fade F (runU F e0 n)

theorem runU_eq (F : Nat) (_hF : 1 ≤ F) (s : Nat) (n : Nat) :
    runU F ⟨s, 0⟩ n = ⟨s - n / F, n⟩ := by
  induction n with
  | zero => simp [runU]
  | succ n ih =>
    rw [runU, ih]; simp only [fade, E.mk.injEq, and_true]
    rw [Nat.succ_div]
    by_cases hd : F ∣ n + 1
    · have h0 : (n + 1) % F = 0 := Nat.mod_eq_zero_of_dvd hd
      have hle : F ≤ n + 1 := Nat.le_of_dvd (by omega) hd
      simp [hd, h0, hle]; omega
    · have h0 : (n + 1) % F ≠ 0 := fun h => hd (Nat.dvd_of_mod_eq_zero h)
      simp [hd, h0]

/-- A contingency left unconfirmed for F * S steps keeps no sediment (sediment is at most S = P_SMAX), so it is no
longer kept by sediment and no longer pays upkeep for it. -/
theorem clears (F : Nat) (hF : 1 ≤ F) (S s : Nat) (hs : s ≤ S) : (runU F ⟨s, 0⟩ (F * S)).sg = 0 := by
  rw [runU_eq F hF]; simp only
  rw [Nat.mul_div_cancel_left S (by omega)]; omega

/-- Before F unconfirmed steps nothing fades (the memory of a recent confirmation is kept as before). -/
theorem keeps_before (F : Nat) (hF : 1 ≤ F) (s n : Nat) (hn : n < F) : (runU F ⟨s, 0⟩ n).sg = s := by
  rw [runU_eq F hF]; simp [Nat.div_eq_of_lt hn]

/-! T1 (agenda T1, notes/T1.md, lab variant SFD, default off): use also restores. `driven` = this contingency drove its
motor in this update AND that motor acted (it is in the update's acting set). In the same update the restore replaces
the fade (the fade step comes after the acts). -/

/-- The variant step: confirmed → the old rule; driven (and its motor acted) → the age goes back to 0 and the sediment
stays; otherwise the fade. -/
def stepDrive (F : Nat) (old : E → E) (confirmed driven : Bool) (e : E) : E :=
  if confirmed then old e else if driven then { sg := e.sg, age := 0 } else fade F e

/-- Without use the variant is the sed_fade rule. -/
theorem stepDrive_undriven (F : Nat) (old : E → E) (c : Bool) (e : E) :
    stepDrive F old c false e = stepNew F old c e := by
  cases c <;> simp [stepDrive, stepNew]

/-- A confirmed contingency is still decided by the old rule alone. -/
theorem stepDrive_confirmed (F : Nat) (old : E → E) (d : Bool) (e : E) : stepDrive F old true d e = old e := by
  simp [stepDrive]

/-- An unconfirmed contingency that drove its acting motor keeps its sediment and restarts its age. -/
theorem driven_keeps (F : Nat) (old : E → E) (e : E) : stepDrive F old false true e = ⟨e.sg, 0⟩ := by
  simp [stepDrive]

/-- The variant never adds sediment on an unconfirmed step. -/
theorem stepDrive_le (F : Nat) (old : E → E) (d : Bool) (e : E) : (stepDrive F old false d e).sg ≤ e.sg := by
  cases d
  · simpa [stepDrive] using fade_le F e
  · simp [stepDrive]

/-- Neither confirmed nor used for F * S steps from a restart: no sediment is left (the sed_fade clearing still holds
for unused contingencies). -/
theorem clears_unused (F : Nat) (hF : 1 ≤ F) (S s : Nat) (hs : s ≤ S) (old : E → E) :
    (Nat.iterate (stepDrive F old false false) (F * S) ⟨s, 0⟩).sg = 0 := by
  have h : ∀ n, Nat.iterate (stepDrive F old false false) n ⟨s, 0⟩ = runU F ⟨s, 0⟩ n := by
    intro n
    induction n with
    | zero => rfl
    | succ n ih =>
      rw [Function.iterate_succ_apply', ih, runU]; simp [stepDrive]
  rw [h]; exact clears F hF S s hs

end SedFade

/-! ## G9 (gaps C): νΦ as the greatest fixed point, computed by iteration from the whole set

On a finite type, iterating a monotone `F` from `univ` gives a decreasing chain that stops within `Nat.card C` steps,
and its value there is `Closure.nu F` (the Knaster–Tarski greatest post-fixed point of bridge-protocol). Then the lab's
`nuPhiOf` (κ, the kept self contingencies) is replaced, in a separate variant of the structural value, by the window's
νΦ computed this way. -/

namespace GFP

open ERIEC

variable {C : Type*} (F : Set C → Set C)

/-- `X n = F^[n] univ`. -/
def X (n : Nat) : Set C := F^[n] Set.univ

theorem X_succ (n : Nat) : X F (n + 1) = F (X F n) := by
  simp [X, Function.iterate_succ_apply']

theorem X_anti (hF : Monotone F) (n : Nat) : X F (n + 1) ⊆ X F n := by
  induction n with
  | zero => simp [X]
  | succ n ih =>
    calc X F (n + 1 + 1) = F (X F (n + 1)) := X_succ F (n + 1)
      _ ⊆ F (X F n) := hF ih
      _ = X F (n + 1) := (X_succ F n).symm

theorem post_le_X (hF : Monotone F) {Y : Set C} (hY : Y ⊆ F Y) (n : Nat) : Y ⊆ X F n := by
  induction n with
  | zero => simp [X]
  | succ n ih => rw [X_succ]; exact hY.trans (hF ih)

theorem nu_le_X (hF : Monotone F) (n : Nat) : Closure.nu F ⊆ X F n := by
  intro c hc
  obtain ⟨Y, hY, hcY⟩ := Set.mem_sUnion.mp hc
  exact post_le_X F hF hY n hcY

theorem stable_from (hF : Monotone F) {k : Nat} (hk : X F (k + 1) = X F k) : ∀ m, X F (k + m) = X F k := by
  intro m
  induction m with
  | zero => rfl
  | succ m ih =>
    show X F (k + m + 1) = X F k
    rw [X_succ F (k + m), ih, ← X_succ F k, hk]

variable [Finite C]

theorem chain (hF : Monotone F) (n : Nat) :
    (∃ k ≤ n, X F (k + 1) = X F k) ∨ (X F n).ncard + n ≤ Nat.card C := by
  induction n with
  | zero => right; simp [X, Set.ncard_univ]
  | succ n ih =>
    rcases ih with ⟨k, hk, h⟩ | h
    · exact Or.inl ⟨k, by omega, h⟩
    · by_cases he : X F (n + 1) = X F n
      · exact Or.inl ⟨n, by omega, he⟩
      · right
        have hss : X F (n + 1) ⊂ X F n := Set.ssubset_iff_subset_ne.mpr ⟨X_anti F hF n, he⟩
        have := Set.ncard_lt_ncard hss (Set.toFinite _)
        omega

/-- The iteration is stable at `Nat.card C`. -/
theorem stable_at_card (hF : Monotone F) : X F (Nat.card C + 1) = X F (Nat.card C) := by
  rcases chain F hF (Nat.card C) with ⟨k, hk, h⟩ | h
  · have h1 := stable_from F hF h (Nat.card C + 1 - k)
    have h2 := stable_from F hF h (Nat.card C - k)
    rw [show k + (Nat.card C + 1 - k) = Nat.card C + 1 by omega] at h1
    rw [show k + (Nat.card C - k) = Nat.card C by omega] at h2
    rw [h1, h2]
  · have h0 : (X F (Nat.card C)).ncard = 0 := by omega
    have he : X F (Nat.card C) = ∅ := (Set.ncard_eq_zero (Set.toFinite _)).mp h0
    apply Set.Subset.antisymm (X_anti F hF _)
    rw [he]; exact Set.empty_subset _

/-- G9: the iteration from `univ` at `Nat.card C` is `Closure.nu F`. -/
theorem X_card_eq_nu (hF : Monotone F) : X F (Nat.card C) = Closure.nu F := by
  apply Set.Subset.antisymm
  · have hfix : X F (Nat.card C) ⊆ F (X F (Nat.card C)) := by
      rw [← X_succ F (Nat.card C), stable_at_card F hF]
    exact Closure.coinduction hfix
  · exact nu_le_X F hF _

end GFP

namespace Window

variable {N : Net} (w : Window N)

/-- ρ as a Bool table (computable). -/
def rhoB (k : Fin N.nK) (m : Fin N.nU) : Bool :=
  decide (N.isMotor m ∧ (N.dst k = m ∨ ∃ k', w.kept k' = true ∧ N.src k' = N.dst k ∧ N.dst k' = m))

/-- Φ on finite sets (computable): the contingencies re-produced by a motor that some contingency of `Y` enables. -/
def phiFin (Y : Finset (Fin N.nK)) : Finset (Fin N.nK) :=
  Finset.univ.filter fun k => ∃ m : Fin N.nU, (decide (N.isMotor m) && w.reproduced m k) = true ∧ ∃ c ∈ Y, w.rhoB c m = true

theorem phiFin_coe (Y : Finset (Fin N.nK)) :
    (↑(w.phiFin Y) : Set (Fin N.nK)) = Closure.Phi w.piRel w.rhoRel ↑Y := by
  ext k
  simp only [phiFin, rhoB, Finset.coe_filter, Finset.mem_univ, true_and, Set.mem_setOf_eq, Closure.Phi,
    Closure.pi_star, Closure.rho_star, piRel, rhoRel, Set.mem_iUnion, Bool.and_eq_true, decide_eq_true_eq,
    Finset.mem_coe, exists_prop]
  constructor
  · rintro ⟨m, ⟨hm, hr⟩, c, hc, hcm⟩; exact ⟨m, ⟨c, hc, hcm⟩, hm, hr⟩
  · rintro ⟨m, ⟨c, hc, hcm⟩, hm, hr⟩; exact ⟨m, ⟨hm, hr⟩, c, hc, hcm⟩

/-- G9: νΦ of the window, by `nK` iterations of Φ from all contingencies. -/
def nuFin : Finset (Fin N.nK) := (w.phiFin)^[N.nK] Finset.univ

theorem nuFin_eq : (↑w.nuFin : Set (Fin N.nK)) = Closure.nu (Closure.Phi w.piRel w.rhoRel) := by
  have h : ∀ n, (↑((w.phiFin)^[n] Finset.univ) : Set (Fin N.nK)) = GFP.X (Closure.Phi w.piRel w.rhoRel) n := by
    intro n
    induction n with
    | zero => simp [GFP.X]
    | succ n ih => rw [Function.iterate_succ_apply', GFP.X_succ, ← ih, phiFin_coe]
  rw [nuFin, h, ← GFP.X_card_eq_nu _ (Closure.phi_mono _ _), Nat.card_eq_fintype_card, Fintype.card_fin]

/-- The structural value counted on the greatest fixed point (G9 variant): |contribution(e) ∩ νΦ|. -/
def valueGfp (e : Fin N.nU) : Nat := Value.viabilityContribution w.nuFin (contributionOf w) e

end Window

open ERIEC.Agency in
/-- G9 variant of `agentOf`: the same data, with νΦ the window's greatest fixed point (`Window.nuFin`) instead of κ. -/
def agentOfGfp {N : Net} (w : Window N) {P A : Type*} [Fintype P] (act : Fin N.nU → Set A)
    (hdc : w.checkDC = true)
    (hdiff : ValueDifferentiated (Value.viabilityContribution w.nuFin (contributionOf w)) act)
    (tab : P → Variant → Bool) (hneed : checkValueNeeded tab = true) :
    Agent (Fin N.nU) (Fin N.nU) (Fin N.nK) Unit P A where
  dc := w.toDC (of_decide_eq_true hdc)
  nuPhi := w.nuFin
  contribution := contributionOf w
  act := act
  differentiated := hdiff
  trial := survivalTrialOf tab
  needed := (valueNeeded_iff_check tab).2 hneed

/-! ## G16 (gaps C, R-CON-2): the constituents' death and division stages of `core/matter.jl` step! (abstract)

After the field and the metabolism/binding updates (which change A and B, not C), the step has two stages that change C:
the death stage (C 1 → 0 where B < THETA_EXIST) and the division stage (each `i` of `order` — constituents with
B ≥ THETA_DIV at that time and `may_divide` — in turn gives a new constituent to one empty 4-neighbour, if any).
With `spontaneous = false` nothing else writes C. Only these stages are modelled; the numbers are abstracted into `keep`
(the death test) and `order` (the dividing constituents at the division stage). -/

namespace ConMatter

variable {n : Nat}

/-- The death stage: a constituent stays only if it passes `keep`. -/
def deathStage (keep : Fin n → Bool) (C : Fin n → Bool) : Fin n → Bool := fun i => C i && keep i

/-- The division stage, sequential over `order`; `pick C i` is the empty neighbour chosen for `i` (or none). -/
def divStage (pick : (Fin n → Bool) → Fin n → Option (Fin n)) (order : List (Fin n)) (C : Fin n → Bool) : Fin n → Bool :=
  order.foldl (fun C i => match pick C i with | some j => Function.update C j true | none => C) C

/-- P1: after the division stage, a constituent was there before, or was given by some `i` of `order` to a site that
`pick` returns, which is a 4-neighbour of `i` (`hpick`). -/
theorem divStage_source (nb : Fin n → Fin 4 → Fin n) (pick : (Fin n → Bool) → Fin n → Option (Fin n))
    (hpick : ∀ C i j, pick C i = some j → ∃ m, nb i m = j) (order : List (Fin n)) (C : Fin n → Bool) (j : Fin n)
    (h : divStage pick order C j = true) : C j = true ∨ ∃ i ∈ order, ∃ m, nb i m = j := by
  induction order generalizing C with
  | nil => exact Or.inl h
  | cons i rest ih =>
    simp only [divStage, List.foldl_cons] at h
    rcases hp : pick C i with _ | k
    · rw [hp] at h
      rcases ih C h with h1 | ⟨i', hi', m, hm⟩
      · exact Or.inl h1
      · exact Or.inr ⟨i', List.mem_cons_of_mem _ hi', m, hm⟩
    · rw [hp] at h
      rcases ih _ h with h1 | ⟨i', hi', m, hm⟩
      · by_cases hjk : j = k
        · subst hjk; obtain ⟨m, hm⟩ := hpick C i j hp; exact Or.inr ⟨i, List.mem_cons_self .., m, hm⟩
        · left; simpa [Function.update_of_ne hjk] using h1
      · exact Or.inr ⟨i', List.mem_cons_of_mem _ hi', m, hm⟩

/-- The death stage never creates a constituent. -/
theorem deathStage_le (keep : Fin n → Bool) (C : Fin n → Bool) (i : Fin n) (h : deathStage keep C i = true) : C i = true := by
  simp [deathStage] at h; exact h.1

/-- One step (death, then division with `order` drawn from the survivors): a site that is a constituent after the step
was one before it, or is a 4-neighbour of a constituent that survived the death stage and divided. -/
theorem step_source (nb : Fin n → Fin 4 → Fin n) (keep : Fin n → Bool) (pick : (Fin n → Bool) → Fin n → Option (Fin n))
    (hpick : ∀ C i j, pick C i = some j → ∃ m, nb i m = j) (order : List (Fin n)) (C : Fin n → Bool)
    (horder : ∀ i ∈ order, deathStage keep C i = true) (j : Fin n)
    (h : divStage pick order (deathStage keep C) j = true) :
    C j = true ∨ ∃ i ∈ order, C i = true ∧ ∃ m, nb i m = j := by
  rcases divStage_source nb pick hpick order _ j h with h1 | ⟨i, hi, m, hm⟩
  · exact Or.inl (deathStage_le keep C j h1)
  · exact Or.inr ⟨i, hi, deathStage_le keep C i (horder i hi), m, hm⟩

/-- Corollary (R-CON-1, the abstract version): with no constituent, the step leaves no constituent. -/
theorem empty_absorbing (nb : Fin n → Fin 4 → Fin n) (keep : Fin n → Bool) (pick : (Fin n → Bool) → Fin n → Option (Fin n))
    (hpick : ∀ C i j, pick C i = some j → ∃ m, nb i m = j) (order : List (Fin n)) (C : Fin n → Bool)
    (horder : ∀ i ∈ order, deathStage keep C i = true) (h0 : ∀ i, C i = false) (j : Fin n) :
    divStage pick order (deathStage keep C) j = false := by
  by_contra hne
  have h : divStage pick order (deathStage keep C) j = true := by simpa using hne
  rcases step_source nb keep pick hpick order C horder j h with h1 | ⟨i, _, hi, _⟩
  · simp [h0 j] at h1
  · simp [h0 i] at hi

end ConMatter


/-! ## Activity (S32): is the BODY's activity kept maximal by its rules? (`notes/R-rest-def.md` §3, P1–P3)

An abstraction of one update of `core/circuit.jl` (`step!`, :105–150): an edge drives when its source was on and not
silenced and it holds (q ≥ 1, sg ≥ 1, the destination is stale, or an onset); a unit's total is the number of driving
edges into it (weights 1); a patch motor is a candidate when it reaches its threshold and some core edge drove it
(`core_gate`); one winner is picked from the idle-preferred pool by a total rank. The agreement with the Julia code
is checked on recorded runs (S32 E), not proved. Nothing here says that every reachable state has a candidate. -/

namespace Activity

variable {U K : Type*} [Fintype K] [DecidableEq K]

/-- The drive rule of an edge (`circuit.jl:108–109`). `onset k` stands for the whole Julia clause
`onset[src] ∧ q = 0 ∧ sg = 0 ∧ h = 0` of the edge (not the bare rise of the source). -/
def drives (src dst : K → U) (old sil : U → Bool) (q sg : K → Nat) (stale : U → Bool) (onset : K → Bool) (k : K) : Bool :=
  old (src k) && !sil (src k) && (decide (1 ≤ q k) || decide (1 ≤ sg k) || stale (dst k) || onset k)

/-- The number of driving edges into `u`. -/
def total [DecidableEq U] (dst : K → U) (drove : K → Bool) (u : U) : Nat :=
  (Finset.univ.filter (fun k => dst k = u ∧ drove k = true)).card

/-- A1: a core that was on, not silenced, with a confident self edge, reaches its threshold 1 (it stays on). -/
theorem core_stays_on [DecidableEq U] (src dst : K → U) (old sil : U → Bool) (q sg : K → Nat) (stale : U → Bool)
    (onset : K → Bool) (u : U) (k : K) (hs : src k = u) (hd : dst k = u) (ho : old u = true) (hn : sil u = false)
    (hq : 1 ≤ q k) :
    1 ≤ total dst (drives src dst old sil q sg stale onset) u := by
  unfold total
  apply Finset.card_pos.mpr
  refine ⟨k, ?_⟩
  simp [drives, hs, hd, ho, hn, hq]

/-- Some edge from a core drove `m` (`CoreGate.coreDrive`, here over an abstract kind map). -/
def coreDrive [DecidableEq U] (src dst : K → U) (isCore : U → Bool) (drove : K → Bool) (m : U) : Bool :=
  decide (∃ k, dst k = m ∧ isCore (src k) = true ∧ drove k = true)

/-- A patch motor is a candidate: threshold and core drive (`circuit.jl:116–128`). -/
def cand [DecidableEq U] (src dst : K → U) (isCore : U → Bool) (theta : U → Nat) (drove : K → Bool) (m : U) : Bool :=
  decide (theta m ≤ total dst drove m) && coreDrive src dst isCore drove m

/-- A2: S(m) — a confident edge from an on, unsilenced core, and a confident or sedimented edge from an on,
unsilenced receptor (two different edges) — makes `m` a candidate when its threshold is 2. -/
theorem cand_of_S [DecidableEq U] (src dst : K → U) (isCore : U → Bool) (theta : U → Nat) (old sil : U → Bool)
    (q sg : K → Nat) (stale : U → Bool) (onset : K → Bool) (m : U) (kc kr : K) (hne : kc ≠ kr)
    (hθ : theta m = 2) (hcd : dst kc = m) (hcc : isCore (src kc) = true) (hco : old (src kc) = true)
    (hcs : sil (src kc) = false) (hcq : 1 ≤ q kc)
    (hrd : dst kr = m) (hro : old (src kr) = true) (hrs : sil (src kr) = false) (hrq : 1 ≤ q kr ∨ 1 ≤ sg kr) :
    cand src dst isCore theta (drives src dst old sil q sg stale onset) m = true := by
  have dc : drives src dst old sil q sg stale onset kc = true := by simp [drives, hco, hcs, hcq]
  have dr : drives src dst old sil q sg stale onset kr = true := by
    rcases hrq with h | h <;> simp [drives, hro, hrs, h]
  have h2 : 2 ≤ total dst (drives src dst old sil q sg stale onset) m := by
    unfold total
    have hsub : ({kc, kr} : Finset K) ⊆ Finset.univ.filter
        (fun k => dst k = m ∧ drives src dst old sil q sg stale onset k = true) := by
      intro k hk
      simp only [Finset.mem_insert, Finset.mem_singleton] at hk
      rcases hk with rfl | rfl <;> simp_all
    calc 2 = ({kc, kr} : Finset K).card := (Finset.card_pair hne).symm
      _ ≤ _ := Finset.card_le_card hsub
  simp only [cand, Bool.and_eq_true, decide_eq_true_eq, coreDrive]
  exact ⟨hθ ▸ h2, ⟨kc, hcd, hcc, dc⟩⟩

/-- The selection pool: the idle-preferred candidates if any, else all candidates (`IdleFirst`, `circuit.jl:139–143`). -/
def pool {M : Type*} [DecidableEq M] (c pref : Finset M) : Finset M := if (pref ∩ c).Nonempty then pref ∩ c else c

theorem pool_nonempty {M : Type*} [DecidableEq M] (c pref : Finset M) (h : c.Nonempty) : (pool c pref).Nonempty := by
  unfold pool; split_ifs with hp
  · exact hp
  · exact h

theorem pool_sub {M : Type*} [DecidableEq M] (c pref : Finset M) : pool c pref ⊆ c := by
  unfold pool; split_ifs
  · exact Finset.inter_subset_right
  · exact Finset.Subset.refl _

/-- A3 (P2): from a nonempty candidate set, an injective rank into a linear order has exactly one maximal element of
the pool (the winner), and it is a candidate. -/
theorem unique_winner {M α : Type*} [DecidableEq M] [LinearOrder α] (c pref : Finset M) (f : M → α)
    (hf : Function.Injective f) (h : c.Nonempty) :
    ∃! w, w ∈ pool c pref ∧ ∀ x ∈ pool c pref, f x ≤ f w := by
  obtain ⟨w, hw, hmax⟩ := Finset.exists_max_image (pool c pref) f (pool_nonempty c pref h)
  refine ⟨w, ⟨hw, hmax⟩, ?_⟩
  rintro v ⟨hv, hvmax⟩
  exact hf (le_antisymm (hmax v hv) (hvmax w hw))

/-- The rank of `circuit.jl:135–138`: the key, then having been on, then the smaller patch. Injective when the patches
are (the two patch motors have patches 1 and 2). -/
def rank {M : Type*} (key : M → Nat) (old : M → Bool) (patch : M → Nat) (m : M) : Nat ×ₗ Bool ×ₗ (Nat)ᵒᵈ :=
  toLex (key m, toLex (old m, OrderDual.toDual (patch m)))

theorem rank_injective {M : Type*} (key : M → Nat) (old : M → Bool) (patch : M → Nat) (hp : Function.Injective patch) :
    Function.Injective (rank key old patch) := by
  intro x y h
  simp only [rank, toLex_inj, Prod.mk.injEq] at h
  exact hp (OrderDual.toDual.injective h.2.2)

/-- A4 (P3): if every update of a window of `W` updates acts with exactly one patch motor, the activity is `W`. -/
theorem activity_full (W : Nat) (acting : Fin W → Nat) (h : ∀ i, acting i = 1) : ∑ i, acting i = W := by
  simp [h]

end Activity


/-! ## Rest, first stage (S33, `notes/R-rest.md` §3 and §5): the motor m0 (patch 4)

An abstraction of the variant `newborn(rest = true)` of `core/circuit.jl`: m0 joins the candidates and the core gate
(patch 4), but not the patch motors' offer, answers, statistics or the failure weakening (those keep `patch ≤ 2`).
`rest_off` (the release of `notes/R-rest-def.md` §3) removes m0 from the candidates and from the acting units. -/

namespace Rest

/-- Candidate kinds by patch: the old rule admits patches 1 and 2; the variant also patch 4. -/
def admitsOld (p : Nat) : Bool := decide (p ≤ 2)
def admitsNew (restOff : Bool) (p : Nat) : Bool := decide (p ≤ 2) || (!restOff && decide (p = 4))

/-- R1: on a circuit without a patch-4 motor, the variant admits exactly the old candidates. -/
theorem admits_same {M : Type*} (patch : M → Nat) (h : ∀ m, patch m ≠ 4) (restOff : Bool) (m : M) :
    admitsNew restOff (patch m) = admitsOld (patch m) := by
  simp [admitsNew, admitsOld, h m]

/-- R4: with `rest_off`, the variant admits exactly the old candidates (m0 is not a candidate). -/
theorem admits_off (p : Nat) : admitsNew true p = admitsOld p := by simp [admitsNew, admitsOld]

/-- The patch motors among the acting units (`onPatch`, `circuit.jl:149`). -/
def onPatch {M : Type*} (patch : M → Nat) (acting : List M) : List M := acting.filter (fun m => decide (patch m ≤ 2))

/-- The offer to patch `i` (`circuit.jl:153`): the yield, if a patch motor of patch `i` acts. -/
def offer {M : Type*} (patch : M → Nat) (acting : List M) (y : Nat → Nat) (i : Nat) : Nat :=
  if (onPatch patch acting).any (fun m => decide (patch m = i)) then y i else 0

/-- R2: when the only acting motor is m0 (patch 4), no patch motor acts and both offers are 0 (so the allocation, the
answers and the intake are 0: `allocate` gives `d i ≤ offer i`). -/
theorem rest_no_offer {M : Type*} (patch : M → Nat) (m0 : M) (h0 : patch m0 = 4) (y : Nat → Nat) (i : Nat) :
    onPatch patch [m0] = [] ∧ offer patch [m0] y i = 0 := by
  simp [offer, onPatch, h0]

/-- One update of an edge's (q, sg) (`circuit.jl:194–212, 248–258`): grown if confirmed, weakened if it drove a failed
patch motor, faded by sed_fade. A confirmation needs the destination answered; an answer needs a patch motor. -/
structure E where
  q : Nat
  sg : Nat

def update (smax : Nat) (confirmed weakened faded : Bool) (e : E) : E :=
  let e1 : E := if confirmed then (if e.q < smax then ⟨min smax (e.q + 1 + e.sg), e.sg⟩ else e) else e
  let e2 : E := if weakened then (if e.q > 0 then ⟨e.q - 1, e1.sg⟩ else ⟨e1.q, e1.sg - 1⟩) else e1
  if faded then ⟨e2.q, e2.sg - 1⟩ else e2

/-- An edge into m0 is never confirmed (m0 is never answered: `answered` is defined on `onPatch` only) and never
weakened (the weakening runs over `onPatch`). -/
def intoRest (patchDst : Nat) (answered : Bool) (inOnPatch : Bool) : Prop :=
  patchDst = 4 → answered = false ∧ inOnPatch = false

/-- R3: an edge into m0 that starts at q = sg = 0 stays there through one update, whatever the fading. It needs that no
transition raises the edge's q or sg (no confirmation, so no grow); the global decay of `circuit.jl:285` (omitted in `update`)
leaves 0 at 0. -/
theorem rest_edge_stays (smax : Nat) (faded : Bool) :
    update smax false false faded ⟨0, 0⟩ = ⟨0, 0⟩ := by
  cases faded <;> simp [update]

/-- R3 over a run: edges into m0 are at q = sg = 0 after every number of updates (`confirmed` and `weakened` are false
for them at every update, by `intoRest`; the fading may be anything). -/
def run (smax : Nat) (faded : Nat → Bool) : Nat → E
  | 0 => ⟨0, 0⟩
  | n + 1 => update smax false false (faded n) (run smax faded n)

theorem rest_edges_zero (smax : Nat) (faded : Nat → Bool) (n : Nat) : run smax faded n = ⟨0, 0⟩ := by
  induction n with
  | zero => rfl
  | succ n ih => simp only [run, ih]; exact rest_edge_stays smax (faded n)

end Rest


/-! ## Rest, second stage (S34 attempt, `notes/R-rest2.md` §5): an innate body edge into m0 does not persist

`core/circuit.jl:285`: at every update with `now % P_DECAY = 0`, every edge that was not confirmed loses one q (bounded
below by 0). Edges into m0 are never confirmed, and no rule raises their q (no confirmation; grow needs a confirmation).
So an innate q0 > 0 into m0 is lost within `P_DECAY` updates: the approved innate wiring (BP4 (3)) does not persist
under the current rules. (An earlier statement here omitted this decay; it was withdrawn on 2026-11-08.) -/

namespace RestBody

/-- One update of an unconfirmed edge's q: the global decay on decay steps, otherwise unchanged. -/
def stepQ (decayStep : Bool) (q : Nat) : Nat := if decayStep then q - 1 else q

/-- A run of updates from q0, with `decay n` telling whether update n is a decay step. -/
def runQ (decay : Nat → Bool) (q0 : Nat) : Nat → Nat
  | 0 => q0
  | n + 1 => stepQ (decay n) (runQ decay q0 n)

theorem runQ_le (decay : Nat → Bool) (q0 : Nat) (n : Nat) : runQ decay q0 (n + 1) ≤ runQ decay q0 n := by
  simp only [runQ, stepQ]; split_ifs <;> omega

/-- The innate q0 = 1 is 0 after any run that contains a decay step (and stays 0: no transition raises it). -/
theorem innate_lost (decay : Nat → Bool) (n k : Nat) (hk : k < n) (hd : decay k = true) : runQ decay 1 n = 0 := by
  have hmono : ∀ a b, a ≤ b → runQ decay 1 b ≤ runQ decay 1 a := by
    intro a b hab
    induction b with
    | zero => simp at hab; subst hab; exact le_rfl
    | succ b ih =>
      rcases Nat.lt_or_ge a (b + 1) with h | h
      · exact le_trans (runQ_le decay 1 b) (ih (by omega))
      · have : a = b + 1 := by omega
        subst this; exact le_rfl
  have h1 : runQ decay 1 k ≤ 1 := by
    have := hmono 0 k (Nat.zero_le k); simpa [runQ] using this
  have h2 : runQ decay 1 (k + 1) = 0 := by simp only [runQ, stepQ, hd, if_true]; omega
  have := hmono (k + 1) n (by omega)
  omega

/-- A core edge with q = sg = 0 into a motor that is not stale does not drive (onset is a receptor-only clause). -/
theorem core_edge_idle {U K : Type*} (src dst : K → U) (old sil : U → Bool) (q sg : K → Nat) (stale : U → Bool)
    (onset : K → Bool) (k : K) (hq : q k = 0) (hs : sg k = 0) (hst : stale (dst k) = false) (ho : onset k = false) :
    Activity.drives src dst old sil q sg stale onset k = false := by
  simp [Activity.drives, hq, hs, hst, ho]

/-- If no core edge into m drives, m has no core drive, so under the core gate it is not a candidate. -/
theorem not_cand_without_core {U K : Type*} [Fintype K] [DecidableEq K] [DecidableEq U] (src dst : K → U) (isCore : U → Bool)
    (theta : U → Nat) (drove : K → Bool) (m : U) (h : ∀ k, dst k = m → isCore (src k) = true → drove k = false) :
    Activity.cand src dst isCore theta drove m = false := by
  simp only [Activity.cand, Activity.coreDrive, Bool.and_eq_false_iff, decide_eq_false_iff_not]
  right
  rintro ⟨k, hd, hc, hk⟩
  rw [h k hd hc] at hk; exact Bool.false_ne_true hk

end RestBody


/-! ## Rest, second stage with α (S34, user approval 2026-11-08): innate edges into m0 are exempt from the global decay

`core/circuit.jl:285` with α: an edge into a patch-4 motor with q0 > 0 is exempt from the global decay (the exemption is
read from `b.patch` and `b.q0`, for every such edge). The model assumes, as for `RestBody.runQ`, that no other transition
changes these edges' q: they are never confirmed (m0 is never answered, so no grow), never weakened (the weakening runs
over `onPatch`), and the capacity rule is not used in BODY's SF version. The agreement is checked on records (S34). -/

namespace RestAlpha

open RestBody

/-- One update of an unconfirmed edge's q with the exemption flag. -/
def stepQx (exempt decayStep : Bool) (q : Nat) : Nat := if exempt then q else stepQ decayStep q

def runQx (exempt : Bool) (decay : Nat → Bool) (q0 : Nat) : Nat → Nat
  | 0 => q0
  | n + 1 => stepQx exempt (decay n) (runQx exempt decay q0 n)

/-- An exempt edge keeps q = q0 over every run. -/
theorem exempt_keeps (decay : Nat → Bool) (q0 n : Nat) : runQx true decay q0 n = q0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [runQx, stepQx, ih]

/-- A non-exempt edge follows the old decay (the default rule is unchanged). -/
theorem nonexempt_old (decay : Nat → Bool) (q0 n : Nat) : runQx false decay q0 n = runQ decay q0 n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [runQx, runQ, stepQx, ih]

/-- Stale (`circuit.jl:105–106`, without the idle clause, which concerns patch motors only): every edge into the unit
has q = sg = 0. An edge into m with q ≥ 1 makes m not stale. -/
def staleAll {K : Type*} (ins : List K) (q sg : K → Nat) : Bool := ins.all (fun k => decide (q k = 0 ∧ sg k = 0))

theorem not_stale_of_q {K : Type*} (ins : List K) (q sg : K → Nat) (k : K) (hk : k ∈ ins) (hq : 1 ≤ q k) :
    staleAll ins q sg = false := by
  unfold staleAll
  rw [Bool.eq_false_iff]
  intro h
  rw [List.all_eq_true] at h
  have := h k hk
  simp at this
  omega

end RestAlpha

/-! ## RB (S37, `discussion/notes/RB-redo.md` §2, 2026-11-09): an unreproducible kept self-edge closes hSelf

In RB the innate edges c1, c2 → m0 are kept (q0 = 1, exempt from decay by α) and are self-edges, but m0 is never answered,
so no motor re-produces them (`core/dc.jl` dc_record: repro only for answered patch acts and call confirmations). Then
ElemSelf is false on every window: the reading of (a) with κ as is cannot hold in RB, by rule. -/
namespace Window
variable {N : Net} (w : Window N)

theorem no_self_of_unreproduced (k : Fin N.nK) (hk : w.kept k = true) (hs : N.selfEdge k)
    (hr : ∀ m, w.reproduced m k = false) : ¬ w.ElemSelf := by
  intro h
  obtain ⟨k', m, _, _, _, _, hrep⟩ := h k hk hs
  rw [hr m] at hrep
  exact Bool.false_ne_true hrep

end Window

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
#print axioms BridgeLab.SeenBoth.new_le_old
#print axioms BridgeLab.SeenBoth.agree_when_seen
#print axioms BridgeLab.SeenBoth.always_on_never_passes
#print axioms BridgeLab.SedFade.clears
#print axioms BridgeLab.SedFade.fade_le
#print axioms BridgeLab.SedFade.driven_keeps
#print axioms BridgeLab.SedFade.stepDrive_undriven
#print axioms BridgeLab.SedFade.stepDrive_le
#print axioms BridgeLab.SedFade.clears_unused
#print axioms BridgeLab.GFP.X_card_eq_nu
#print axioms BridgeLab.Window.nuFin_eq
#print axioms BridgeLab.agentOfGfp
#print axioms BridgeLab.ConMatter.step_source
#print axioms BridgeLab.ConMatter.empty_absorbing
#print axioms BridgeLab.Activity.core_stays_on
#print axioms BridgeLab.Activity.cand_of_S
#print axioms BridgeLab.Activity.unique_winner
#print axioms BridgeLab.Activity.rank_injective
#print axioms BridgeLab.Activity.activity_full
#print axioms BridgeLab.Rest.admits_same
#print axioms BridgeLab.Rest.admits_off
#print axioms BridgeLab.Rest.rest_no_offer
#print axioms BridgeLab.Rest.rest_edges_zero
#print axioms BridgeLab.RestBody.innate_lost
#print axioms BridgeLab.RestBody.core_edge_idle
#print axioms BridgeLab.RestBody.not_cand_without_core
#print axioms BridgeLab.RestAlpha.exempt_keeps
#print axioms BridgeLab.RestAlpha.nonexempt_old
#print axioms BridgeLab.RestAlpha.not_stale_of_q
#print axioms BridgeLab.Window.no_self_of_unreproduced
