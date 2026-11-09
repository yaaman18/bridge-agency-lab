# Predictions for S10 (discussion/specs/S10-body-paths.md r2), frozen before any paths.jl run

A (T2, seen objects, a post hoc diagnosis): seeds 35/37, :swap and :std, p2-high, main run H 392, t0 = 64 and 192, deadline t0+392;
cuts R (r2->m2, r8->m2), C (c2->m2), RC; q = sg = 0, one-shot or persistent.
- PP1: R persistent: the body is alive at the deadline in both :swap arms at both t0 (the receptor-side sediment is not needed for survival there).
- PP2: C persistent: the number of m2 acts in t0+1..t0+392 is at most half of the uncut copy's, in both :swap arms at both t0.
B (T3): the pairs (H 392, seeds 21-40) whose arms differ at some tie under J0; cuts Q, G, QG of every edge from r5, one-shot or persistent.
- PP3: QG persistent: in every such pair the arm difference at the ties disappears.
Everything else (one-shot cuts, Q, G, the :std arms) is described, not predicted.
