# Predictions for stage 23, learning to wait on top of the orienting response (turn.js, test_orient.js with
# CORE=./turn.js NOPROPRIO=1), written 2026-10-30 after stage 22 (results-orient.json: 4/7; the cue was learned
# with REPLAY rather than RESPONSIVE, and live and replayed partners were not told apart) and before any run of turn.js.
# No new constants.
T1  No harm: ABSENT keeps form >= 0.99 in every phase and seed, and its share of patch actions answered is within
    0.05 of BASELINE in every phase and seed.
T2  Waiting is learned (falsification criterion of stage 21, now with orienting): with RESPONSIVE, the share of calls
    made while a call is pending is <= 0.2 in the last 1000 steps of phase A and lower than in its first 300 steps,
    in >= 4/5 seeds.
T3  Through which receptor: at the end of phase A with RESPONSIVE, r11 (not waiting) -> m3 has sediment >= 1 and
    r10 (waiting) -> m3 has sediment 0, in >= 4/5 seeds.
T4  A reactive caller does not tell live from replay (from stage 22): the late share of calls made while waiting
    differs by < 0.1 between RESPONSIVE and REPLAY in >= 4/5 seeds.
T5  It needs the proprioception: with NOPROPRIO the late share of calls made while waiting is at least 0.1 higher
    than with RESPONSIVE in >= 4/5 of the seeds where both make >= 10 calls in that window.
T6  The partner becomes a cue: with RESPONSIVE, r9 -> m3 has sediment >= 1 at the end of phase A in >= 3/5 seeds.
T7  Quiet when the partner leaves: with RESPONSIVE, calls in the last 500 steps of phase B are <= 50 in >= 4/5 seeds.
T8  Recognition on return: with RESPONSIVE, the first call strictly after the first gesture of phase C comes within
    3 steps in >= 4/5 seeds.
