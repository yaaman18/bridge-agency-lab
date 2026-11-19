import Mathlib.Tactic.Linarith
import Mathlib.Tactic.Ring

/-!
# Memory transfer pilot: the additive readout cannot separate the four test pairs (statements first, then proofs)

Pilot `experiments/memory-transfer-pilot/` (roadmap `discussion/notes/memory-transfer-roadmap.md` step 3, review
`discussion/reviews/memory-transfer-design.md`, the clarify of `discussion/notes/D-memory-transfer-codex.md`).
A readout that adds a left-port term and a right-port term, `s i j = L i + R j`, gives the score of the pair `(i, j)`;
`s > 0` reads X, `s < 0` reads Y, `s = 0` is a tie and counts as wrong. Because `s c c + s d d = s c d + s d c`, the
same pairs `CC`, `DD` cannot both read one label while the different pairs `CD`, `DC` both read the other: at most
three of the four are right, whichever label is assigned to "same". The bias is absorbed into `L` (or `R`).
`phenomenal_claim` is not touched.
-/

namespace BridgeLab.MemoryTransfer

/-- The additive readout: one term per port. -/
def additive {α : Type} (L R : α → ℚ) (i j : α) : ℚ := L i + R j

/-- The identity behind the bound. -/
theorem additive_swap {α : Type} (L R : α → ℚ) (c d : α) :
    additive L R c c + additive L R d d = additive L R c d + additive L R d c := by
  unfold additive; ring

/-- Assignment "same → X": the four answers cannot all be right. -/
theorem additive_not_four_sameX {α : Type} (L R : α → ℚ) (c d : α) :
    ¬ (0 < additive L R c c ∧ 0 < additive L R d d ∧ additive L R c d < 0 ∧ additive L R d c < 0) := by
  rintro ⟨h1, h2, h3, h4⟩
  have := additive_swap L R c d
  linarith

/-- Assignment "same → Y" (labels inverted): the four answers cannot all be right either. -/
theorem additive_not_four_sameY {α : Type} (L R : α → ℚ) (c d : α) :
    ¬ (additive L R c c < 0 ∧ additive L R d d < 0 ∧ 0 < additive L R c d ∧ 0 < additive L R d c) := by
  rintro ⟨h1, h2, h3, h4⟩
  have := additive_swap L R c d
  linarith

#print axioms additive_not_four_sameX
#print axioms additive_not_four_sameY

end BridgeLab.MemoryTransfer
