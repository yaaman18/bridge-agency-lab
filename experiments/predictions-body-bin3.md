# Predictions for item 74 (frozen 2026-11-02 before the runs)

User 2026-11-02: "じゃあそれらお案で実装してみて" (the three recommendations left after item 73: (1) try body_org's circuit
with the app's rule bin3 (+ idle_first), predictions first; (2) record L2's falsity as the by-design result; (3) the
raising-order test of item 71: does the history decide which motor locks in?). (2) is a record, not a trial.

Setup: body_org of stage 42 (U = 0.02, MCOST = 0.004), only the circuit's rule or the order of the raising changes. No
number is changed. `experiments/eval_body_bin3.jl` (raising seeds 1-10; body_org ORG 10 000 steps of seasons, seeds 1-10)
and `experiments/variant_horizon.jl` with CONTRAST=bin3 IDLE=1 (results-horizon-bin3idle.json) and with CUR=swap (old rule,
results-horizon-swap.json), horizons 60/294/392/588, seeds 1-10, both structure readings. CUR=swap = the nursery's
50-step blocks swapped (starts on [0,5], ends on [5,0]); the school is unchanged (experiments/curricula.jl).
Known before: old rule, standard raising: the school is m2 at all 400 steps for 10/10 seeds, m1 has no confident input
(item 72). bin3 + idle_first in the app's being broke the lock (item 72). Nothing of the new runs was looked at.

Implementation
- BQ1: variant_horizon.jl without the new settings reproduces results-horizon.json (every field but the seconds).
- BQ7: Lean's checkSelfProducing agrees with Julia on every table of both new horizon runs (horizon_lean.jl, IN=...).

(1) body_org with bin3 + idle_first
- BQ2: the lock is broken in the school: the unforced winner switches at least once, for >= 8/10 seeds.
- BQ3: at the end of the raising both m1 and m2 have at least one confident receptor input, for >= 8/10 seeds.
- BQ4: H = 294, 392, 588, both readings: L2 false and not value-differentiated, 10/10 (the binary answer, item 71).
- BQ5: H = 392, :constituents: L3 true and alive_somewhere true, 10/10.
- BQ6: body_org ORG 10 000 steps with bin3 + idle_first survives 10/10.

(3) the raising order, old rule
- SQ1: with the nursery swapped, m1 takes >= 390 of the 400 school steps, 10/10 seeds (the history decides).
- SQ2: with the nursery swapped, H = 392: the choice is m1 in both choice schedules (c1-better and c2-better), and L2 is
  false, 10/10.

Reported without prediction: bin3 without idle_first, bin3 + idle_first with the swapped nursery, forced choices, H = 60.

Falsification: if SQ1 fails with m2 still taking the school, the history (the last nursery block) does not decide the
lock-in and inference 2 of item 71 is weakened (the patch-number tie-break or the school itself would decide); if BQ2 and
BQ3 both fail, bin3's reset of an idle motor's statistics is not what broke the lock in the app (inference of item 72);
if BQ4 fails for some seed, inference 1 (the binary answer cannot separate 5 from 4) is refuted for that circuit.
