# Predictions for stage 43 (body_org.js GREEDY and REVR, test_greedy.js), written 2026-10-31 before any run. No exploration
# of these conditions before freezing (only the check that body_org.js with defaults reproduces results-body-org.json).
# GREEDY = a fixed rule on the circuit's receptors (r7 -> 1, r8 -> 2, r1 -> 1, r2 -> 2); REVR = receptors crossed at 5000.
F0  Conservation |error| < 1e-6 in all 40 runs.
F1  In the unperturbed world the learned circuit is no better than the fixed rule: GREEDY mean body >= 0.95 x ORG mean
    body in >= 8/10 seeds.
F2  With crossed receptors the fixed rule starves: GREEDY-REVR dies before 10000 steps (10/10; deterministic, one case).
F3  With crossed receptors the circuit relearns in time: ORG-REVR alive at 10000 steps in >= 8/10 seeds.
F4  ORG-REVR mean body over steps 5000-10000 > GREEDY-REVR in >= 9/10 seeds.
