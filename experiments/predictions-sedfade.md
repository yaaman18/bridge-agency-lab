# Predictions for item 84: sed_fade, the sediment of unconfirmed contingencies fades (frozen 2026-11-03 before the runs)

User 2026-11-03: "じゃあ今日はそこからスタート" (item 83's next step: a rule that reduces the sediment-only contingencies,
inside the self-maintaining circuit; pleasure/pain is a separate upper layer, not coupled in).

Rule (core/circuit.jl step!(...; sed_fade = true), lab option, default off; Lean formal/LabCircuit.lean SedFade, no sorry):
a contingency not confirmed for a multiple of FORGET (= 100, existing constant) steps loses one sediment; a confirmed one
is untouched. So a habit never confirmed is no longer kept (nor paid for) after FORGET * P_SMAX = 400 steps. No number
changed. Item 83 found: in the random world L2's rule keeps 12-15 contingencies before death, 63/138 of them R->M edges
with confidence 0 kept only by sediment, and the upkeep (not the choices) kills (KC 0: 10/10).

Runs: experiments/eval_sedfade.jl (body_org raised with the body, FEED, RAISE body, KC 0.002, L2's rule bin3 + idle_first +
core gate, PHASE (seed-1)*100, seeds 1-10, 10 000 steps, worlds seasons / heldout / random as eval_grow.jl), with and
without SEDFADE, one-way and PER = 1; variant_horizon.jl GROW=1 SEDFADE=1 and SEDFADE=1 (scripted raising, L2's system).

- FQ1: SEDFADE unset: sh core/check/run.sh identical everywhere; eval_sedfade.jl without SEDFADE reproduces item 81's L2 and
  L2+PER1 rows (deaths and body means).
- FQ2: random world, one-way, SEDFADE: mean kept contingencies per alive step after step 800 <= 9 (item 83: about 14), for
  every seed.
- FQ3: random world, one-way, SEDFADE: survives >= 6/10 (item 81: 1/10).
- FQ4: seasons and heldout, one-way, SEDFADE: 10/10 each.
- FQ5: seasons, one-way, SEDFADE: body mean >= 14.0 (item 81: 15.1).
- FQ6: seasons, PER = 1, SEDFADE: survives >= 7/10 (item 81: 5/10).
- FQ7: variant_horizon GROW=1 SEDFADE=1 (H 294 392 588, both readings): L3 (:constituents), alive_somewhere and
  core_enables_action true 10/10; value-differentiated <= 2/10 (sed_fade does not touch inference 1); L2 false.
- FQ8: variant_horizon SEDFADE=1 (scripted raising): value-differentiated >= 8/10 (no harm to the value tracking); L2 false.

Reported without prediction: heldout/random with PER = 1, the composition of the kept contingencies, deaths.

Falsification: item 83's inference (reducing the sediment-only contingencies lets the body live in the scarce world) is
refuted if FQ2 holds and FQ3 fails (fewer kept is not enough). If FQ2 fails the rule does not do what it is meant to.
If FQ4 or FQ8 fails the fade costs the memory the sediment carries (relearning across seasons or the value tracking).
