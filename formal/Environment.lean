import ERIEC.Adjunction

/-!
# D3 response to the environment: the formal lemmas (statements first, then proofs)

Discussion D3 (`discussion/notes/D3.md`, claude-lab and codex-lab, 2026-11-07). Rules of reading M2 in this substrate; they
do not touch bridge-protocol's definitions.
- LE1: if some action reaches two different features, no sensory relation makes the existential images a Galois
  connection (the contrapositive of bridge-protocol's `rigidity_of_gc`). The lab's declared alpha (m1 reaches r1, r3, r7,
  r8, `core/dc.jl:24`) is such an alpha, so the lab does not claim M2 for its circuit's sigma.
- LE2: for every alpha, the universal image gives a Galois connection (`galoisConn_induced`), so that statement says
  nothing about the agent.
`phenomenal_claim` is not touched.
-/

namespace BridgeLab.Environment

open ERIEC

/-- LE1: a multi-valued action relation has no existential right adjoint. -/
theorem le1 {M E : Type*} (alphaRel : M → Set E) (sigmaRel : E → Set M)
    (h : ∃ m e₁ e₂, e₁ ≠ e₂ ∧ e₁ ∈ alphaRel m ∧ e₂ ∈ alphaRel m) :
    ¬ GaloisConnection (Adj.alpha_star alphaRel) (Adj.sigma_star sigmaRel) := by
  intro hGC
  obtain ⟨m, e₁, e₂, hne, h₁, h₂⟩ := h
  obtain ⟨e, _, huniq⟩ := (Adj.rigidity_of_gc alphaRel sigmaRel hGC).1 m
  exact hne ((huniq e₁ h₁).trans (huniq e₂ h₂).symm)

/-- The lab's declared reach of m1 and m2 on the eight BODY receptors (0-based r1..r8; `core/dc.jl:24`, before the
state gate of item 69, which only removes pairs). -/
def labAlpha : Fin 2 → Set (Fin 8)
  | 0 => {0, 2, 6, 7}
  | 1 => {1, 3, 6, 7}

/-- LE1 for the lab's alpha: no sigma makes it an ERIE system. -/
theorem le1_lab (sigmaRel : Fin 8 → Set (Fin 2)) :
    ¬ GaloisConnection (Adj.alpha_star labAlpha) (Adj.sigma_star sigmaRel) :=
  le1 labAlpha sigmaRel ⟨0, 0, 2, by decide, by simp [labAlpha], by simp [labAlpha]⟩

/-- LE1b (codex D3 round 1, P2): an action with no reach also has no existential right adjoint (rigidity needs exactly
one feature per action). -/
theorem le1_empty {M E : Type*} (alphaRel : M → Set E) (sigmaRel : E → Set M) (h : ∃ m, alphaRel m = ∅) :
    ¬ GaloisConnection (Adj.alpha_star alphaRel) (Adj.sigma_star sigmaRel) := by
  intro hGC
  obtain ⟨m, hm⟩ := h
  obtain ⟨e, he, _⟩ := (Adj.rigidity_of_gc alphaRel sigmaRel hGC).1 m
  rw [hm] at he
  exact he

/-- The state-gated alpha of item 69 at an event: motor `i` reaches its declared features when its gate `g i` is open
(world phase and its patch yields), and nothing otherwise. -/
def labAlphaGated (g : Fin 2 → Bool) : Fin 2 → Set (Fin 8) := fun i => if g i then labAlpha i else ∅

/-- LE1 at every event: whatever the gates, the lab's gated alpha has no existential right adjoint (each motor's reach is
either four features or empty). -/
theorem le1_gated (g : Fin 2 → Bool) (sigmaRel : Fin 8 → Set (Fin 2)) :
    ¬ GaloisConnection (Adj.alpha_star (labAlphaGated g)) (Adj.sigma_star sigmaRel) := by
  cases h0 : g 0
  · exact le1_empty _ sigmaRel ⟨0, by simp [labAlphaGated, h0]⟩
  · exact le1 _ sigmaRel ⟨0, 0, 2, by decide, by simp [labAlphaGated, labAlpha, h0], by simp [labAlphaGated, labAlpha, h0]⟩

/-- LE2: the universal image is always a right adjoint (bridge-protocol's `galoisConn_induced`, restated). -/
theorem le2 {M E : Type*} (alphaRel : M → Set E) :
    GaloisConnection (Adj.alpha_star alphaRel) (Adj.sigma_star_induced alphaRel) :=
  Adj.galoisConn_induced alphaRel

#print axioms le1_lab
#print axioms le1_gated
#print axioms le2

end BridgeLab.Environment
