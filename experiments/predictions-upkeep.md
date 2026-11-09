# Predictions for item 83: does the circuit's upkeep kill the body in the random world? (frozen 2026-11-03 before the runs)

User 2026-11-03: "bridge-agency-labの開発に続いをやって". Item 82's remaining steps 1-3 all change a rule or a world
number (user's decision). This item changes nothing: it tests item 81's inference 2 by reading and by controls.

Item 81 found: raised with the body (FEED, RAISE "body", KC 0.002, L2's rule bin3 + idle_first + core gate, one-way, no
capacity), the random world (SCHED random, SCHEDSEED = seed, PHASE (seed-1)*100) survives 1/10; GREEDY (4 kept, same KC)
10/10. Inference 2: the ~13 kept contingencies (0.026/step) kill the body in the scarce blocks.

Runs (experiments/eval_upkeep.jl, seeds 1-10, 10 000 steps, random world):
  A = L2's rule, KC 0.002 (item 81 repeated).
  B = L2's rule, KC 0 (control: same rule, no upkeep).
  C = GREEDY, KC 0.0065 (control: GREEDY's 4 kept charged 0.026/step, about L2's load in item 81).
  D = GREEDY, KC 0.002 (item 81 repeated).
Harvest per step = U * sum of d over the acted patches (d <= y, so it is what is taken from the pools).

- UQ1: A and D reproduce item 81 exactly (A deaths 4525 3272 6741 4589 4223 1852 3251 1513 8821; D 10/10).
- UQ2 (item 81's frozen falsification of inference 2): in A, the mean number of kept contingencies over the 200 alive
  steps before death is >= 8 for every dying seed (item 81: refuted if about 4, as GREEDY).
- UQ3: B survives >= 8/10.
- UQ4: C survives <= 5/10.
- UQ5: harvest per alive step from step 800 to death (or 10 000) in A is >= 0.8 x D's, for >= 7/10 seeds.
- UQ6: for >= 7 of A's 9 deaths, the 300-step block of the death step or the block before it has total yield
  (y1 + y2 of the world) <= 3.

Reported without prediction: B and C body sizes, A's upkeep vs act cost in the 300 steps before death.

Falsification: inference 2 (the upkeep of a large circuit kills the body in the scarce world) is refuted if UQ2 fails, or
if UQ3 fails (without upkeep the same rule still dies: the choices, not the upkeep, kill). If UQ3 holds but UQ4 fails,
the upkeep is necessary for the death but GREEDY's choices withstand it: the circuit's harvest is part of the cause.
