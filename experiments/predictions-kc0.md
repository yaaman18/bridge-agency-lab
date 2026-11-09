# Predictions for item 85: does the upkeep make L2 true? (frozen 2026-11-03 before the runs)

User 2026-11-03: "推奨どおり3の対照から進めて" (item 84's step 3: the control for inference 4, nothing changed in the rules).

Item 84 found (variant_horizon.jl GROW=1 SEDFADE=1, upkeep KC 0.002 in the raising and the trials): value-differentiated
7/10 at every horizon (seeds 2 3 5 6 7 8 9), L2 true in 5 of 40 runs per reading (H 392 seeds 2 6 9, H 588 seeds 2 9;
ValueNeeded true), and with the tracking intact some schedules die (H 588 seeds 6 8, H 392/588 seed 10).
Inference 4: the upkeep narrows the body's margin so that some schedules need the value tracking.

Controls (variant_horizon.jl, GROW=1 SEDFADE=1, H 60 294 392 588, seeds 1-10, both readings; new env options KC and KCTRIAL
only override the upkeep, defaults unchanged):
  (b) KCTRIAL=0: the same raising (KC 0.002), no upkeep in the trials.
  (a) KC=0: no upkeep in the raising nor in the trials.
  (0) no env: item 84 repeated.

- KQ1: (0) reproduces results-horizon-grow-sedfade.json (every run's L2, differentiated, value_needed, survival, survT).
- KQ2: (b) L2 false and value_needed false in all 80 runs (the 5 true runs of item 84 become false).
- KQ3: (b) value-differentiated for the same seeds as item 84 (2 3 5 6 7 8 9 at every horizon, both readings).
- KQ4: (b) with the tracking intact, all four survival schedules survive for every run with H >= 294.
- KQ5: (a) the circuit at step 800 is that of the raising with upkeep (the circuit reads the pools, which the upkeep does
  not touch), so differentiated for the same seeds as item 84, and L2 false in all 80 runs.

Falsification: inference 4 is refuted if KQ2 fails (L2 stays true without upkeep in the trials: the value tracking would be
needed for another reason than the narrowed margin).
