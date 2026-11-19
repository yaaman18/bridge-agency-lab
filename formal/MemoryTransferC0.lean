import Mathlib.Tactic.Linarith
import Mathlib.Tactic.Ring
import Mathlib.Algebra.BigOperators.Fin

/-!
# Memory transfer C0 pilot: the trace stays a probability, and the local product splits by action (statements first)

Pilot `experiments/memory-transfer-c0/` (predictions frozen in `experiments/freeze-memory-transfer-c0.txt`).
The trace of B1 and of the candidate LP is the leaky average `m ← m + (y − m)/8` (8 = `P_DECAY` of core/circuit.jl)
with `y ∈ {0, 1}`; it stays in `[0, 1]`, so B1's `p = m` is a probability before the clip.
The candidate reads `s = Σ_{i,j} w_(i,j) · f_i(a) · c_j` with the action code `f(a) = (1, σ_a)`, `σ_a = ±1`: this equals
`Σ_j (w_(0,j) + σ_a · w_(1,j)) · c_j`, one readout of the shared context per action, so the transferred coupling `w`
and the individual's context `c` alone give the score. `phenomenal_claim` is not touched.
-/

namespace BridgeLab.MemoryTransferC0

/-- The leaky average of the trace, with rate 1/8. -/
def leak (m y : ℚ) : ℚ := m + (y - m) / 8

/-- The trace stays in `[0, 1]`. -/
theorem leak_mem (m y : ℚ) (hm0 : 0 ≤ m) (hm1 : m ≤ 1) (hy0 : 0 ≤ y) (hy1 : y ≤ 1) :
    0 ≤ leak m y ∧ leak m y ≤ 1 := by
  unfold leak
  constructor <;> linarith

/-- The local-product score on the 2 × 3 shared channels. -/
def lpScore (w : Fin 2 → Fin 3 → ℚ) (σ : ℚ) (c : Fin 3 → ℚ) : ℚ :=
  ∑ j : Fin 3, (w 0 j * (1 * c j) + w 1 j * (σ * c j))

/-- The local product is one readout of the context per action. -/
theorem lpScore_split (w : Fin 2 → Fin 3 → ℚ) (σ : ℚ) (c : Fin 3 → ℚ) :
    lpScore w σ c = ∑ j : Fin 3, (w 0 j + σ * w 1 j) * c j := by
  unfold lpScore
  refine Finset.sum_congr rfl (fun j _ => ?_)
  ring

#print axioms leak_mem
#print axioms lpScore_split

end BridgeLab.MemoryTransferC0
