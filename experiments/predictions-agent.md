# Predictions for S15 (discussion/specs/S15-body-agent.md r1), frozen before any agent.jl run
Seeds 71-80 (never run), SF rule, arms :std/:swap (20 objects), H 392.
- AG1: the provenance hash of the raised state is the same in C1, C2 and the survival table, for all 20 objects.
- AG2: an Agent value is built (the generated Lean file type-checks with agentOf) for >= 10 of the 20 objects.
- AG3: every object whose tool L2 is true, whose window w passes checkDC and which has a witness pair, builds an Agent (no object fails only in Lean).
- AG4: for >= 18 of the 20 objects, r7 and r8 are both attributable (r7 on through 5:15 only in C1, r8 only in C2).
Falsification: AG3 false -> the Julia checks and the Lean predicates disagree on some object (stop and inspect the mapping).
