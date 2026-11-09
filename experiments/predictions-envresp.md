# Predictions for S9 (discussion/specs/S9-body-envresp.md r2), frozen before any envresp.jl run

Objects: SF rule, seeds 41-50 (never run before), arms :std/:swap, 4 survival schedules, main run H 392, branch points
t in 32:32:392 alive. D3 R2-c with the revision r6 (Z = both patches exchanged: schedule and pools).
Written from the world rule (alpha) and the circuit's rule, not from any run of these seeds.
- EP1 (alpha check): no mismatch: an undeclared pair (m1 -> r2, r4; m2 -> r1, r3) never differs between C and Bm at any usable event.
- EP2: at least one declared pair is realized for each of m1 and m2 (pooled over all runs).
- EP3: among the branch points where (b) is determined, (b) holds at >= 50% (pooled).
- EP4: among the branch points where (b) holds and (b') is determined, (b') fails at >= 90% (the output of the coupled
  receptors is needed for the shift in >= 90%).
Seeds 35/37 :swap p2-high (seen) are described only. Falsification: EP1 false -> the declared alpha is in mismatch
(alpha-dependent judgments undetermined until the premise check); EP4 false -> the shift does not need the coupled
receptors' output in many windows (the patch's answer through the gate may carry the environment).
