import Mathlib.Data.Fintype.Basic

/-!
# D3a CLAMP: the two channels from the medium into the circuit (statements first, then proofs)

Discussion D3a (`discussion/notes/D3a-clamp.md`, decisions-log #6). In `core/circuit.jl` one yield vector `y` feeds two
channels: the receptors' features (`:100`, `:117`, the sense channel) and the patch offer (`:151`, then `allocate`, the
answer, the gate; the answer channel). The variant gives the answer channel its own yields `y_offer` (default: `y`).
These lemmas fix the abstraction: the default is the old step; the receptors' input does not depend on `y_offer`; the
offer does not depend on the sensed yields; a zero offer vector gives no answer; with both channels given the same
inputs, the step gives the same result (the identity control of D3a §4, for a deterministic step).
`phenomenal_claim` is not touched.
-/

namespace BridgeLab.Clamp

/-- The offer of the acting patch motors (`core/circuit.jl:151`): the answer channel's yield of each acting patch. -/
def offer (acting : Fin 2 → Bool) (yOffer : Fin 2 → Nat) : Fin 2 → Nat := fun k => if acting k then yOffer k else 0

/-- The two channel inputs of a step: what the receptors read and what the offer is made of. -/
def inputs (acting : Fin 2 → Bool) (ySense yOffer : Fin 2 → Nat) : (Fin 2 → Nat) × (Fin 2 → Nat) :=
  (ySense, offer acting yOffer)

/-- The default (no `y_offer`): both channels read `y`. -/
def inputsDefault (acting : Fin 2 → Bool) (y : Fin 2 → Nat) := inputs acting y y

theorem default_is_same (acting : Fin 2 → Bool) (y : Fin 2 → Nat) :
    inputsDefault acting y = inputs acting y y := rfl

/-- The receptors' input does not depend on the answer channel's yields. -/
theorem sense_indep (acting : Fin 2 → Bool) (ys yo yo' : Fin 2 → Nat) :
    (inputs acting ys yo).1 = (inputs acting ys yo').1 := rfl

/-- The offer does not depend on the sensed yields. -/
theorem offer_indep (acting : Fin 2 → Bool) (ys ys' yo : Fin 2 → Nat) :
    (inputs acting ys yo).2 = (inputs acting ys' yo).2 := rfl

/-- A zero answer-channel yield gives a zero offer (so `allocate` gives no answer, `core/circuit.jl:86–91`). -/
theorem offer_zero (acting : Fin 2 → Bool) (yo : Fin 2 → Nat) (h : ∀ k, yo k = 0) : ∀ k, offer acting yo k = 0 := by
  intro k; simp [offer, h k]

/-- The identity control: a step that is a function of its state and the two channel inputs gives the same result when
both inputs are the same (the yoked branch Z with both channels yoked to N, from the same state). -/
theorem identity_control {St R : Type*} (step : St → (Fin 2 → Nat) × (Fin 2 → Nat) → R) (s : St)
    (acting : Fin 2 → Bool) (ys yo : Fin 2 → Nat) :
    step s (inputs acting ys yo) = step s (inputs acting ys yo) := rfl

#print axioms offer_zero

end BridgeLab.Clamp
