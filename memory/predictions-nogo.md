# Predictions for stage 26, option A: the no-go default for the call (nogo.js = turn.js rev. 2 with m3 threshold 3),
# written 2026-10-31 before any run of nogo.js with threshold 3. With threshold 2 nogo.js reproduces
# results-scaffold.json exactly (checked before this file). Harnesses: test_scaffold.js and diag_scaffold.js (scaffolding),
# test_orient.js (live / replay / absent / no proprioception). New constant: CALL_THETA = 3 (user decision 2026-10-31).
N1  No harm: form >= 0.99 and share of patch actions answered within 0.05 of BASELINE in every phase, seed and
    condition of both harnesses.
N2  Waiting under scaffolding (criterion, from the abstract analysis): SCAF-ADULT late (last 1000 of A) share of
    calls made while waiting <= 0.05 in >= 4/5 seeds (turn.js rev. 2: 0.10-0.15).
N3  The conjunction is what changed: calls made while waiting right after a gesture in the last 1000 steps of A
    (diag_scaffold.js) <= 3 in >= 4/5 seeds (rev. 2: 6-14).
N4  Calling is not suppressed: SCAF-ADULT has >= 50 calls in the last 1000 steps of A and answers >= 0.5 of its
    phase-A calls, in >= 4/5 seeds.
N5  The partner still matters: RESP-ADULT late share of calls made while waiting is higher than SCAF-ADULT's by
    >= 0.1 in >= 4/5 seeds.
N6  Recognition and quiet (test_orient.js, RESPONSIVE): calls in the last 500 steps of B <= 50, and the first call
    strictly after the first gesture of C within 3 steps, in >= 4/5 seeds.
Not predicted, reported: live vs replay; no proprioception; calls before the partner (babble) under ABSENT.
