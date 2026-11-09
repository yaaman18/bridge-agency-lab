/-!
# History comparison contract (S1, R-BODY-1; statements first)

User decision 2026-11-06 (D1, decisions-log #2): measure the history effect H under a declared comparison contract
(D0 decision 2): copies of one birth state, one law, and a declared difference of the input-generating policy only.
Here the policy is an open-loop script (`experiments/curricula.jl`), so an arm is a birth state and a script.
The law is a deterministic step function; in Julia it is `core/circuit.jl` `step!` called with the same rule arguments.
Nothing here is about agency or value: the contract only says when a difference of observations may be attributed
to the declared part of the history. `phenomenal_claim` is not touched.
-/

namespace BridgeLab.History

/-- A deterministic law: one step from a state and an input gives the next state and an observation. -/
structure Law (σ ι ο : Type) where
  step : σ → ι → σ × ο

/-- Running a law from a state over a script: the final state and the observations in order. -/
def run {σ ι ο : Type} (L : Law σ ι ο) : σ → List ι → σ × List ο
  | s, [] => (s, [])
  | s, x :: xs =>
    let r := L.step s x
    let rest := run L r.1 xs
    (rest.1, r.2 :: rest.2)

/-- Two arms under one law: births and scripts, and the declared positions where the scripts may differ. -/
structure Arms (σ ι : Type) where
  birthA : σ
  birthB : σ
  scriptA : List ι
  scriptB : List ι
  declared : Nat → Prop

/-- The comparison contract (S1-2 to S1-4): equal births, equal lengths, equal scripts outside the declared positions. -/
def Contract {σ ι : Type} (a : Arms σ ι) : Prop :=
  a.birthA = a.birthB ∧ a.scriptA.length = a.scriptB.length ∧
    ∀ i, ¬ a.declared i → a.scriptA[i]? = a.scriptB[i]?

/-- S1-4 in the lab (codex 6): the declaration covers only the nursery, Julia steps 1–400 = Lean indices 0–399. -/
def NurseryOnly {σ ι : Type} (a : Arms σ ι) : Prop :=
  ∀ i, a.declared i → i < 400

/-- (1) Replay control (S1-5): the same birth and the same script give the same final state and observations. -/
theorem replay_control {σ ι ο : Type} (L : Law σ ι ο) (s₁ s₂ : σ) (xs₁ xs₂ : List ι)
    (hs : s₁ = s₂) (hx : xs₁ = xs₂) :
    run L s₁ xs₁ = run L s₂ xs₂ := by
  subst hs; subst hx; rfl

/-- Scripts that agree at every position are equal. -/
theorem script_eq_of_agree {ι : Type} (xs ys : List ι) (h : ∀ i : Nat, xs[i]? = ys[i]?) : xs = ys :=
  List.ext_getElem? h

/-- (2) Nothing declared, nothing differs: under the contract with an empty declaration the runs agree
(final state and observations; S1-6 (a) is read from the observations, (b) from the final state). -/
theorem no_declared_no_difference {σ ι ο : Type} (L : Law σ ι ο) (a : Arms σ ι)
    (hc : Contract a) (hd : ∀ i, ¬ a.declared i) :
    run L a.birthA a.scriptA = run L a.birthB a.scriptB := by
  obtain ⟨hb, _, hs⟩ := hc
  exact replay_control L _ _ _ _ hb (script_eq_of_agree _ _ (fun i => hs i (hd i)))

/-- (3) Under the contract, a difference of the runs implies a declared position where the scripts differ.
It states existence only; it does not say which position contributed (codex 8). -/
theorem difference_needs_declared {σ ι ο : Type} (L : Law σ ι ο) (a : Arms σ ι) (hc : Contract a)
    (hne : run L a.birthA a.scriptA ≠ run L a.birthB a.scriptB) :
    ∃ i, a.declared i ∧ a.scriptA[i]? ≠ a.scriptB[i]? := by
  apply Classical.byContradiction
  intro hno
  apply hne
  obtain ⟨hb, _, hs⟩ := hc
  apply replay_control L _ _ _ _ hb
  apply script_eq_of_agree
  intro i
  apply Classical.byContradiction
  intro hdiff
  by_cases hdi : a.declared i
  · exact hno ⟨i, hdi, hdiff⟩
  · exact hdiff (hs i hdi)

/-- With the nursery-only declaration, a difference of the runs comes from a nursery position. -/
theorem difference_in_nursery {σ ι ο : Type} (L : Law σ ι ο) (a : Arms σ ι) (hc : Contract a)
    (hn : NurseryOnly a) (hne : run L a.birthA a.scriptA ≠ run L a.birthB a.scriptB) :
    ∃ i, i < 400 ∧ a.scriptA[i]? ≠ a.scriptB[i]? := by
  obtain ⟨i, hdi, hd⟩ := difference_needs_declared L a hc hne
  exact ⟨i, hn i hdi, hd⟩

/-- S2: any observable computed from the run (e.g. AGENCY-001's D and N read after the body phase, which is a fixed
deterministic continuation of the raising) inherits the attribution: a difference of the observable under the contract
implies a declared position where the scripts differ. -/
theorem observable_difference_needs_declared {σ ι ο β : Type} (L : Law σ ι ο) (a : Arms σ ι) (hc : Contract a)
    (f : σ × List ο → β) (hne : f (run L a.birthA a.scriptA) ≠ f (run L a.birthB a.scriptB)) :
    ∃ i, a.declared i ∧ a.scriptA[i]? ≠ a.scriptB[i]? :=
  difference_needs_declared L a hc (fun h => hne (congrArg f h))

#print axioms observable_difference_needs_declared
#print axioms no_declared_no_difference
#print axioms difference_needs_declared
#print axioms difference_in_nursery

end BridgeLab.History
