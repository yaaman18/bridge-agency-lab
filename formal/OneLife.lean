/-!
# One life with death as an absorbing state (S48 §4, P1-2; statements first)

Spec `discussion/specs/S48-one-life.md` r2. The body and the circuit are abstract: a law gives the living step
`liveStep` and the predicate "every site is empty" (`empty`). The state of one life carries the inner state, the step
count, the latch `dead` and the step `death` at which the death was detected. One step from a state and a drive gives the
next state; nothing else is an argument. The drive is the pair of scheduled yields, Fin 6 × Fin 6 (out-of-range drives
and the error return are outside this model; the implementation's gate G7 checks them). `decode (encode s) = some s` is a
hypothesis of (iii), not a property of the Julia serialization. (i) and (ii) follow from the construction and are not
counted as evidence about the implementation. `phenomenal_claim` is not touched.
-/

namespace BridgeLab.OneLife

/-- The drive of one step: the scheduled yields of the two patches, each in 0..5. -/
abbrev Drive := Fin 6 × Fin 6

/-- A law: the living step of the inner state (circuit, wiring, perm, noise, matter, pools) and the death predicate. -/
structure Law (ι : Type) where
  liveStep : ι → Drive → ι
  empty : ι → Bool

/-- The state of one life. -/
structure State (ι : Type) where
  inner : ι
  t : Nat
  dead : Bool
  death : Option Nat

/-- One step (S48 §3.2 order: dead first, then detection at the start of the step, then the living step). -/
def step {ι : Type} (L : Law ι) (s : State ι) (g : Drive) : State ι :=
  if s.dead then s
  else if L.empty s.inner then { s with dead := true, death := some s.t }
  else { s with inner := L.liveStep s.inner g, t := s.t + 1 }

/-- Running a list of drives. -/
def run {ι : Type} (L : Law ι) (s : State ι) (gs : List Drive) : State ι := gs.foldl (step L) s

/-- (i) A dead state is unchanged by a step with any drive. -/
theorem dead_absorbing {ι : Type} (L : Law ι) (s : State ι) (h : s.dead = true) (g : Drive) :
    step L s g = s := by
  simp [step, h]

/-- (ii) With the law fixed, the step is a function of the state and the drive only. -/
theorem step_signature {ι : Type} (L : Law ι) :
    ∃ f : State ι → Drive → State ι, ∀ s g, f s g = step L s g :=
  ⟨step L, fun _ _ => rfl⟩

/-- (iii) Saving, loading and continuing gives the straight run, under the hypothesis that decoding inverts encoding. -/
theorem resume_eq {ι β : Type} (L : Law ι) (encode : State ι → β) (decode : β → Option (State ι))
    (hdec : ∀ s, decode (encode s) = some s) (s : State ι) (pre post : List Drive) :
    (decode (encode (run L s pre))).map (fun s' => run L s' post) = some (run L s (pre ++ post)) := by
  simp [hdec, run, List.foldl_append]

end BridgeLab.OneLife
