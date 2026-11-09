# Predictions for S37 (discussion/specs/S37-rb-selfmaint.md r1), frozen before any run on seeds 441-450

Objects: RB (SF + rest + rest_body :B + alpha), arms :std and :swap, seeds 441-450 (never run before), the 4 frozen survival
schedules, H 392 (80 main runs). Branch points E = {32, 64, ...} with the body alive; branches N, X (m1, m2 silenced), Y (c1, c2
silenced) to t+H. Written from the rules (LS9, LSH2, LSH2k, Window.no_self_of_unreproduced, core_gate) and from S36 (the :std
raising was crossed on 10/10 seeds 431-440), not from any run of seeds 441-450. Seed 1 (smoke) was seen before these were written, and kappa_prec / H3 were
defined after the smoke run showed (a) false everywhere: these predictions are informed by that smoke run, not independent of it.
- RP1 (L9): no confirmation occurs in any X branch.
- RP2 (LSH2k): in every X branch the original kappa is never empty while the body is alive.
- RP3 (no_self_of_unreproduced): the original (a) fails at every branch point (hSelf false), so the original T never holds.
- RP4 (LSH2): b1p holds at every branch point, and the LSH2 map holds on kappa_prec in every X branch (q <= 4, and each
  update q_new <= decay(now, q_old)).
- RP5: the X branch dies by t+H at every branch point.
- RP6: the Y branch dies no earlier than the X branch at every branch point (Y stops every act; X leaves m0's acts and their cost).
  Refuted by a point where Y dies before X; a point where both live to t+H is undetermined for the order, and RP6 holds only
  when no such point remains (otherwise RP6 is undetermined).
- RP7 (S36): every :std run dies before H, and (b2) fails at every :std branch point (N dies by t+H), so T_prec fails there.
- RP8: on :swap, a_prec holds at >= 50% of the branch points (pooled), and T_prec holds at >= 1 branch point in every :swap run
  alive at H (if no :swap run is alive at H, the second half has nothing to judge and RP8 is undetermined, not a hit).
- RP9: T_prec_core = T_prec at every branch point.
Falsification: RP1 false -> the L9 map is refuted (every b1/b1p resting on it is undetermined); RP2 or RP3 false -> the lemma's
abstraction map (exempt innate edges, m0 never answered) is refuted; RP4 false -> H2 or the LSH2 map is refuted; RP7 false ->
the crossing reading of S36 does not carry to these seeds (reported, not explained away). RP9 false -> the points where
T_prec_core differs from T_prec are listed (Y did not stop the maintenance there). RP5, RP6, RP8 false are reported as measured values.
