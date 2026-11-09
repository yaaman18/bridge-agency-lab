# Predictions for item 78 A: world variation (frozen 2026-11-02 before the runs)

User 2026-11-02: "おすすめで実装していって" (the recommendation: A, more variation of the world with the circuit and the
receptors unchanged, first; then B, more kinds of receptors, as a body_org lab variant).

Setup: body_org (U = 0.02, MCOST = 0.004, 10 000 steps, the circuit raised on BO_CUR before the body), seeds 1-10.
Rules: L2's system (bin3 + idle_first + core gate, items 75/77), the rule of stage 42 (contrast nothing), the fixed rule
GREEDY, and NONE (no act). Worlds (core/body_org.jl SCHED, lab option, default unchanged): the frozen seasons; the
held-out seasons of sense/heldout.js ((2,4) (4,0) (0,4) (3,3), 250 steps each, a lab precedent of 2026-10-29); random
300-step blocks with each patch's yield drawn from 0..5 (both 0 drawn again), the draw given by the seed. These yields are
new world settings asked for by the recommendation; the frozen seasons and every other number are unchanged.
"richer" = among living steps where both seen yields are positive and differ and one patch is acted on, the share on
the larger seen yield (the seen yields are the pools, lowered by the body's own harvest).

- WA1: with the new options unset, sh core/check/run.sh is identical everywhere.
- WA2: held-out seasons: L2's rule survives 10/10.
- WA3: random worlds: L2's rule survives >= 9/10.
- WA4: held-out seasons: L2's rule has richer > 0.5 for 10/10 seeds.
- WA5: held-out seasons: richer of L2's rule > richer of the stage 42 rule for >= 8/10 seeds.
- WA6: random worlds: L2's rule has richer > 0.5 for >= 8/10 seeds.
- WA7: NONE dies in every world, 10/10 (the world feeds no one who does not act).

Reported without prediction: GREEDY, the frozen seasons' numbers, the body's mean size, the answered share.

Falsification: if WA2 or WA3 fails, what the circuit learned in the raising does not carry it through worlds it was
not raised for; if WA4 or WA6 fails, the value differentiation of item 74 does not show in a world the body depletes
itself.
