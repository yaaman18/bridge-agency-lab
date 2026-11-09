# Predictions for S39 (discussion/specs/S39-rb-envresp.md r1), frozen before any run on seeds 461-470

Objects: RB, seeds 461-470 (never run before), arms :std/:swap, 4 survival schedules, H 392, branch points t in 32:32:392 alive.
R2-c as S9 (D3 r6, Z = both patches exchanged), plus b_act, b_rb and a_prec (spec section 1). Written after the smoke run on
seed 1 (seen, not evidence): in its :swap Z branches m0 won most counted updates and (b) held at 8 of 48 points.
- EV1 (alpha check): no mismatch (an undeclared coupled pair never differs between C and Bm at a usable event).
- EV2: on :swap, among the branch points where (b) is determined, (b) holds at <= 30% (pooled).
- EV3: on :swap, m0 acts at >= 50% of the counted updates of the Z branches (pooled over the points).
- EV4: on :swap, b_rb = b at >= 90% of the branch points (clamping rb false in N and Z leaves (b) unchanged in most windows).
- EV5: every :std run dies before H, and (b) holds at no :std branch point.
Falsification (each refutes only the measured proposition; causes are candidates): EV1 false -> the declared alpha is in mismatch
(alpha-dependent judgments undetermined until the premise check); EV2 false -> "(b) holds at <= 30% of the determined :swap points"
is refuted; EV3 false -> "m0 acts at >= 50% of the counted Z updates" is refuted; EV4 false -> "b_rb and b agree (as three-valued
verdicts, a change to undetermined counts as a disagreement) at >= 90% of the :swap points" is refuted; EV5 false -> "every :std
run dies before H and (b) holds at no :std point" is refuted for these seeds.
