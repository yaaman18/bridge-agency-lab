# Predictions for stage 21, learning to wait (wait.js, test_wait.js), written 2026-10-30 before any run of wait.js
# with the partner. User decision 2026-10-30: adopt rev. 2/3; implement option 1 (acquire waiting by learning).
# Changes from partner.js rev. 3: no superseding (each call pending on its own, a gesture answers the oldest one),
# proprioceptive receptors r10 (waiting) and r11 (not waiting). No new numerical constants.
# wait.js with partner=false reproduces memory.js (check_partner_off.js with CORE=./wait.js, 118000/118000).
W1  No harm: ABSENT keeps form >= 0.99 in every phase and seed, and its share of patch actions answered is within
    0.05 of BASELINE in every phase and seed.
W2  Waiting is learned (falsification criterion of the stage): with RESPONSIVE, the share of calls made while a call is
    already pending falls to <= 0.2 in the last 1000 steps of phase A, and is lower than in its first 300 steps,
    in >= 4/5 seeds.
W3  Through which receptor: at the end of phase A with RESPONSIVE, r11 (not waiting) -> m3 has sediment >= 1 and
    r10 (waiting) -> m3 has sediment 0, in >= 4/5 seeds.
W4  Only a contingent partner teaches it: with REPLAY the share of calls made while waiting in the last 1000 steps of
    phase A stays >= 0.5 in >= 4/5 seeds.
W5  It needs the proprioception: with NOPROPRIO (RESPONSIVE partner) that share in the last 1000 steps of A is at least
    0.1 higher than with RESPONSIVE in >= 4/5 seeds (seeds where both make >= 10 calls in that window).
W6  The partner becomes a cue: with RESPONSIVE, r9 -> m3 has sediment >= 1 at the end of phase A in >= 3/5 seeds.
W7  Quiet when the partner leaves: with RESPONSIVE, calls in the last 500 steps of phase B are <= 50 in >= 4/5 seeds.
W8  Recognition on return: with RESPONSIVE, in phase C the first call strictly after the partner's first gesture comes
    within 3 steps in >= 3/5 seeds.
