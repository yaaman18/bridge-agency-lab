# Predictions for item 81: stage 1 of self-maintenance, the circuit supported by the body (frozen 2026-11-02 before the runs)

User 2026-11-02: "じゃあ段階1から進めて" (stage 1 of the plan: the body pays for the circuit and raises it with itself).

Setup (every number from earlier stages; none new): body_org raised with the body (FEED: the first 800 steps feed the
pools in the nursery and school order; RAISE "body": the newborn circuit lives on the founder body from step 0; stage 46),
upkeep KC = 0.002 per kept contingency per step paid from the body's bound matter (stages 44-54), season phase
(seed - 1) * 100 (stage 47), U = 0.02, MCOST = 0.004. Two forms of dependence:
- one-way (no capacity): the body pays, but an unpaid upkeep costs the circuit nothing;
- mutual (capacity PER = 1, stage 46): at most one kept contingency per constituent; when the body shrinks the weakest
  are lost (core/body_org.jl enforce_capacity!, now shared with the AGENCY-001 adapter).
Rules: L2's system (bin3 + idle_first + core gate), bin3 alone (stage 54: 10/10 alive, body 14.6, one-way), GREEDY.
Runs: experiments/eval_grow.jl (10 000 steps, the 3 worlds of item 78 A, seeds 1-10) and variant_horizon.jl GROW=1
(the trials start from the body and circuit at step 800; KC paid in the trials too), without and with PER=1.
Only a smoke test (horizon 16, output hidden) was run before freezing.

- PQ1: sh core/check/run.sh identical everywhere (the capacity rule moved into a function).
- PQ2: one-way, L2's rule, frozen seasons: survives 10/10.
- PQ3: one-way, L2's rule, held-out and random worlds: survives >= 9/10 in each.
- PQ4: mutual (PER=1), L2's rule, frozen seasons: survives >= 8/10.
- PQ5: mutual (PER=1), L2's rule: the circuit loses contingencies to the capacity (lost > 0) for >= 8/10 seeds in the
  frozen seasons (the circuit now depends on the body); one-way: lost = 0 (by construction).
- PQ6: one-way, L2's rule: mean body >= bin3's mean body - 1 in each of the 3 worlds.
- PQ7: AGENCY-001 on the grown system (GROW=1), one-way and mutual, H = 294, 392, 588, :constituents: L3 true,
  alive_somewhere true, core_enables_action true, 10/10.
- PQ8: same runs: value-differentiated true for >= 8/10 seeds, and L2 false 10/10 (ValueNeeded false, item 77).

Reported without prediction: GREEDY, bin3 with PER=1, kept contingencies, the :q reading, H = 60.

Falsification: if PQ2 or PQ3 fails, the L2 rule cannot keep a body that pays for it (the gate and idle_first cost what
bin3 alone affords); if PQ4 fails, making the circuit depend on the body (capacity) still brings the downhill of stage 46
with the contrast rule; if PQ8's differentiation fails, raising with the body loses what the scripted raising taught.
