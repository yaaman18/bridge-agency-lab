# Predictions for the idle-first choice (item 72; frozen 2026-11-01 before the runs)

User 2026-11-01: "推奨どおりでいい、固定化を解く規則変更から進めて" (after item 71: the lock-in, where the motor that wins
first gathers confidence and keeps winning, and the binary answer, which cannot tell 5 from 4).

Rule (opt-in, `core/circuit.jl` `step!(...; idle_first = true)`; default off, so every existing rule and the app are
unchanged): among the candidate patch motors, one that has not acted for longer than FORGET (= 100, the circuit's own
constant, the same "idle" as learn3/bin3) is preferred; the old ranking (conf, habit, total, was on, patch) decides among
the preferred ones, or among all when none is idle. No amount is used (X5), no number is changed or added.
Lean first (`formal/LabCircuit.lean` IdleFirst): `pick_eq_pref` (the old rule decides when both or neither are idle),
`pick_idle`, `old_rule_locks` (the old rule can lock a motor out forever), `no_lockout` (with the new rule, while both
patch motors are candidates at every step, neither goes more than FORGET steps without acting). Proved, propext /
Classical.choice / Quot.sound only, no sorry.

Runs: `experiments/eval_idle.jl` (app's being saved v528 and newborn, 2000 steps each, no partner, old vs idle; body_org's
raising seeds 1-10; body_org ORG of stage 42, 10 000 steps, seeds 1-10) and the horizon variant with IDLE=1
(`results-horizon-idle.json`, horizons 60/294/392/588, seeds 1-10, both structure readings). Before freezing only the
equivalence check (sh core/check/run.sh, default off) and the Lean proofs were run; no trial output was looked at.

Implementation
- IQ1: with idle_first off, `sh core/check/run.sh` is identical everywhere (JS 42, Rust 24, wasm 1, app_embed, body_org
  reproduction). (Run before freezing: holds.)
- IQ2: Lean's `IdleFirst.pick` agrees with the Julia winner on every exported two-candidate choice, and the exported
  choices include the "one idle" branch.

The lock-in (inference 2 of item 71)
- IQ3: saved v528 with idle_first: m2 acts, not forced (the old ranking would also have picked it), at >= 1 world step
  where both patches yield and y2 > y1 (old rule: 0; m1 took all 556 such steps).
- IQ4: saved v528 with idle_first: the edge r2 "y2>=3" -> m2 reaches q >= 1 at some step of the run (old: expected 0).
- IQ5: saved v528: hSMC over the windows of steps where both patches yield is higher with idle_first than with the old
  rule (item 69: the remaining failures were r2 unsupported, 605/629, in v518).
- IQ6: saved v528: DC rate higher with idle_first than with the old rule (old 69.7% in item 69).
- IQ7: newborn, world phase (steps > 800): DC rate with idle_first >= old.
- IQ8: M4b (every living occurrence acts) in every app run.
- IQ9: body_org's raising with idle_first: in the school part (both patches positive) both m1 and m2 act at least 4
  times, for 10/10 seeds.

The binary answer (inference 1 of item 71): the lock-in is broken but 5 vs 4 is still not separated
- IQ10: horizon variant with idle_first, H = 294, 392, 588: L2 false and value-differentiated false for 10/10 seeds at
  each horizon and structure reading.

Nothing else broken
- IQ11: horizon variant with idle_first, H = 392, :constituents: L3 true and alive_somewhere true for 10/10.
- IQ12: body_org ORG (stage 42, U = 0.02, MCOST = 0.004, 10 000 steps of seasons) with idle_first survives 10/10 seeds
  (old: 10/10).

Reported without prediction: the numbers of forced choices, the confident receptor inputs of each motor at the end, the
newborn's whole-run DC and hSMC, H = 60.

Falsification: if IQ3 and IQ4 both fail (the forced acts happen but m2 never wins on its own nor gains r2), the lock-in
is not what keeps r2 unsupported (or one forced act per FORGET steps is too weak to undo it); if IQ10 fails (some seed
separates 5 from 4), inference 1 (the binary answer cannot tell 5 from 4) is refuted for that circuit.
