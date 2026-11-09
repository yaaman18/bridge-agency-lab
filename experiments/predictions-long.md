# Predictions for S24 (discussion/specs/S24-body-long.md r1), frozen before any run: the frozen S7 and S17 predictions, verbatim except the seeds and H.
## S7 part (selfmaint.jl, HORIZONS=392,784); the survival horizon is with_horizon(params, H) and branches run to the absolute time t+H
Objects: SF rule (item 93 default), arms :std and :swap, seeds 231-240 (never run before), the 4 frozen survival schedules
(su.params, not abundant), H 392/784 (160 main runs). Branch points E = {32, 64, ..., <= H} with the body alive;
branches N (none), X (m1, m2 silenced from t+1), Y (c1, c2 silenced from t+1), to the absolute time t+H.
Written from the rules (L2, L9, core_gate) and not from any run of these seeds.
- SP1 (L9 correspondence): no confirmation (patch or call) occurs in any X branch, nor in any Y branch, at any branch point.
- SP2 (L2 correspondence): (b1) holds at every branch point (kappa empty or the body dead within 32 updates under X).
- SP3: the X branch dies by t+H at every branch point.
- SP4: the Y branch dies at the same absolute time as the X branch at every branch point (core_gate: no patch motor
  comes on without a core-sourced drive, so Y stops every patch act, as X).
- SP5: the N branch is alive at t+H at >= 90% of the branch points (pooled over all runs).
- SP6: (a) (DC) holds at >= 50% of the branch points (pooled), and T holds at >= 1 branch point in every run
  (seed, arm, schedule, H) whose body is alive at H.
- SP7: T_core(t) = T(t) at every branch point.
Falsification: SP1 false -> the L9 abstraction map is refuted (every (b1) relying on it becomes undetermined);
SP2 false -> the L2 correspondence is refuted; SP4 false -> Y is not equivalent to X for the patch acts in this system.
SP5/SP6 false are reported as measured values (how often T applies), not as refutations of D2.
## S17 part (agent2.jl, H from ENV)
Seeds 241-250 (never run), SF, arms :std/:swap (20 objects; the two arms of a seed are not independent samples), each at H 392 and at H 784 (each prediction applies to each H separately; 20 objects per H). One contract: survival schedules.
- AH1 (trajectory control): for all 20 objects, the survival recorded in B1 (p1-high) and B2 (p2-high) equals the tab's intact entries.
- AH2: an Agent value is built (agentOf type-checks) for >= 15 of the 20 objects.
- AH3: for >= 18 of the 20 objects, the window w passes checkDC.
- AH4: for >= 15 of the 20 objects, checkValueNeeded holds with T_struct (silenced from update 1 in all 4 survival schedules).
Each object that fails is reported with the missing fields; an unattributable receptor is not counted as a failure by itself.
