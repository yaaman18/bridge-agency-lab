# Predictions for stage 22, the orienting response as an innate rule (orient.js, test_orient.js), written 2026-10-30
# before any run of test_orient.js. User: run the experiments in order, (a) -> (b) -> (c). Base: partner.js rev. 3
# (adopted; superseding calls, no proprioception). orient=false reproduces partner.js (check_orient_off.js, 34000/34000).
# With orient on, the patch side also changes (check_partner_off.js with CORE=./orient.js: 1769/118000 identical
# to memory.js), so harm is a real question here. No new numerical constants.
O1  No harm: ABSENT keeps form >= 0.99 in every phase and seed, and its share of patch actions answered is within
    0.05 of BASELINE in every phase and seed.
O2  The partner becomes a cue: with RESPONSIVE, r9 -> m3 has sediment >= 1 at the end of phase A in >= 4/5 seeds.
O3  Only a contingent partner makes it a cue: with REPLAY, r9 -> m3 has sediment 0 at the end of phase A in >= 4/5 seeds.
O4  No permanent silence, and the calls are cued: with RESPONSIVE, the last 1000 steps of phase A have >= 5 calls and
    >= 0.5 of them come at the step right after a gesture, in >= 4/5 seeds.
O5  Recognition on return: with RESPONSIVE, in phase C the first call strictly after the first gesture comes within
    3 steps in >= 4/5 seeds.
O6  Quiet when the partner leaves: with RESPONSIVE, calls in the last 500 steps of phase B are <= 50 in >= 4/5 seeds.
Not predicted, reported: sediment of the noise (r5) and clock (r6) receptors into the patch motors.
