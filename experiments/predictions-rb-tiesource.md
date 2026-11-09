# Predictions for S38 (discussion/specs/S38-rb-tiesource.md r1), frozen before any run on seeds 451-460

Objects: RB, arms :std/:swap, seeds 451-460 (never run before), H 392, tie probes (1,1)..(5,5), window 5:15. Interventions J as S8
x the rb condition (normal / rb clamped false). Written after the smoke run on seed 1 (seen, not evidence): these predictions are
informed by it. "Acts" = the winner of each window step (m0, a patch motor, or none), the same denominator for every cell.
- TR1: J3 and J4 each give the J0 acts at every window step of every probe, for every arm and rb condition (r3, r4 are off at ties).
- TR2: with the normal rb input, J0 has no patch act at any window step of any probe, for every arm (m0 acts at every step).
- TR3: J1256 has no patch act at any window step of any probe, for every arm and rb condition.
- TR4: with rb clamped false, J56 has patch acts at every window step of (3,3), (4,4), (5,5) and none at (1,1), (2,2), for every arm.
Each TR is judged over all 10 seeds x 2 arms (x the rb conditions named). TR2 is both halves (no patch act, and m0 the winner at
every step); the checker also prints the first half alone. Falsification (what is refuted; the causes named are candidates, not
conclusions): TR1 false -> "an off receptor does not change the acts" is refuted for these objects; TR2 false -> the claim that m0
wins every tie step under the normal rb input is refuted (a patch act or a step with no act is enough); TR3 false -> "only r1, r2,
r5, r6 make tie patch acts" is refuted; TR4 false -> the seed-1 pattern of J56 under rb false is refuted for these seeds.
