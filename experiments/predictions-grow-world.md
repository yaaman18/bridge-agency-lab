# Predictions for S29 (discussion/specs/S29-body-grow-world.md r1), frozen before any run: the frozen S7 / S17 texts, verbatim except the objects (counts scaled for S17: 15/20 -> 8/10, 18/20 -> 9/10).
## (a) S7 part, G version
Objects: the G version (grow = true, KC 0.002, sed_fade, trials from the copy after update 799; one arm, the raising does not use the nursery arms), seeds 351-360 (never run before), the 4 frozen survival schedules
(su.params, not abundant), H 294/392/588 (120 main runs). Branch points E = {32, 64, ..., <= H} with the body alive;
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
## (a) S17 part, G version
Seeds 361-370 (never run), the G version (as above), one arm (10 objects), H 392. One contract: survival schedules.
- AH1 (trajectory control): for all 10 objects, the survival recorded in B1 (p1-high) and B2 (p2-high) equals the tab's intact entries.
- AH2: an Agent value is built (agentOf type-checks) for >= 8 of the 10 objects.
- AH3: for >= 9 of the 10 objects, the window w passes checkDC.
- AH4: for >= 8 of the 10 objects, checkValueNeeded holds with T_struct (silenced from update 1 in all 4 survival schedules).
Each object that fails is reported with the missing fields; an unattributable receptor is not counted as a failure by itself.
## (b) S7 part, the lab schedules (SF). Not applicable (excluded from the judgments, not refutations): a run with no branch point (the body dead before t = 32).
Objects: SF rule (item 93 default), arms :std and :swap, seeds 371-380 (never run before) shared by all 4 schedules, the 4 lab schedules
mid-32, mid-23, mid-32to23, mid-41to14 (switch 20; su.params, not abundant), H 294/392/588 (240 main runs). Branch points E = {32, 64, ..., <= H} with the body alive;
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
