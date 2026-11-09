# Predictions for item 82: does reading the self-depleted pools cost the value differentiation? (frozen 2026-11-02 before the runs)

User 2026-11-02: "推奨どおり1から進めて" (item 81's next step 1: test inference 1 without changing a rule).

Control (lab option, default off): body_org raised with the body as in item 81 (FEED, RAISE "body", KC 0.002, L2's rule
bin3 + idle_first + core gate, one-way, no capacity), but during the raising (steps 0-799) the circuit is given the
scripted yields that feed the pools (BO_CUR, as in the scripted raising) instead of the pool levels; the harvest is still
taken from the pools, so the body lives on what is really there. After step 800 the circuit reads the pools as before.
Item 81 found: raised with the body and reading the pools, value-differentiated 0/10; at step 800 m2 <- r2 only.

- CQ1: with READCUR unset, sh core/check/run.sh identical everywhere.
- CQ2: at step 800, m1 has a confident input from r1 (y1>=3) or r7 (y1>y2) and m2 from r2 or r8, for >= 8/10 seeds.
- CQ3: AGENCY-001 (variant_horizon.jl GROW=1 READCUR=1), H = 294, 392, 588, both readings: value-differentiated true for
  >= 8/10 seeds.
- CQ4: same runs: L3 (:constituents) true, alive_somewhere true, core_enables_action true, L2 false, 10/10.
- CQ5: 10 000 steps (eval_grow.jl READCUR=1), frozen seasons, one-way L2's rule: survives 10/10.

Reported without prediction: the other worlds, PER=1, body sizes.

Falsification (as frozen in item 81): if CQ2 and CQ3 fail, inference 1 (reading the self-depleted pools keeps the
comparison receptors from learning) is refuted; something else of raising with the body (the body's small early size, the
upkeep, the depletion of the harvest) is what costs the differentiation.
