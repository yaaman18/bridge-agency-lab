# Predictions for stage 42 (body_org.js, test_body_org.js), written 2026-10-31 before any run of seeds 1-10.
# Exploration before freezing (seed 99, 6000 steps, reported): with the patches as source patches on the field the choice
# of patch could not matter (ORG = REPLAY), so the patches became pools behind the MaterialPort; the first REPLAY shift
# (half the run = 3 season cycles) was in phase with the seasons (ORG = REPLAY again) and was changed to half the run plus
# 500 steps. With pools and the new shift, U in {0.01, 0.02, 0.04}, MCOST in {0, 0.004}: ORG alive (mean 9-41
# constituents, answered 0.99), REPLAY dead by step 393-1587 (answered 0.51-0.76), NONE dead at step 196.
# Chosen: U = 0.02, MCOST = 0.004 (new constants), 10000 steps. ORG-REV (patches exchange their seasons at 5000) not explored.
I0  Conservation |error| < 1e-6 (body, pools and reservoir) in all 40 runs.
I1  The body alone dies (material death) in 10/10 seeds.
I2  The body with the circuit is alive at 10000 steps in >= 9/10 seeds.
I3  It is the coupling, not the acts: mean body size ORG > REPLAY in >= 9/10 seeds.
I4  Answered fraction of motor acts ORG > REPLAY in >= 9/10 seeds.
I5  REPLAY dies before 10000 steps in >= 7/10 seeds.
I6  After the reversal at 5000 (ORG-REV) the body is still alive at 10000 in >= 8/10 seeds (the circuit relearns in time).
