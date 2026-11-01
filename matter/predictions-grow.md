# Predictions for stage 46 (body_org.js FEED/RAISE/PER, test_grow.js), written 2026-10-31 before any full run. Checked
# first (mechanics only, 300 steps of seed 1, survival not looked at): the options run; capacity blocks and drops
# contingencies. body_org.js with defaults still gives stage 43 (5/5 reproduced). New constants: PER = 1 (one constituent
# per kept contingency), the feeding schedule = the curriculum of the organization world (FEED); KC = 0.002 from stage 44.
G0  Conservation |error| < 1e-6 in all runs.
G1  Growing together works: GROW (newborn on the body, raised by the fed pools, capacity PER = 1) alive at 10000 in >= 8/10.
G2  Stage 44 replicates in this world: PRE (pre-raised, no capacity) dies in >= 9/10.
G3  Raising on the body alone is not enough: BODY (no capacity) dies in >= 6/10.
G4  The capacity alone is enough: PRECAP (pre-raised, capacity PER = 1) alive in >= 8/10.
G5  The grown circuit still adapts: GROWR (receptors crossed at 5800) alive in >= 8/10; GREEDYR dies (10/10, deterministic).
G6  In the unchanging world the fixed rule still wins: GREEDY mean body over 5000-10000 > GROW in >= 8/10.
