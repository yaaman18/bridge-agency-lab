# Predictions for stage 20 revision 3 (partner.js rev. 3: the call is its own channel, not in the one-action
# selection), written 2026-10-30 after results-partner-rev2.json and before any run of rev. 3. test_partner.js is
# unchanged from rev. 2. partner=false still reproduces memory.js (check_partner_off.js, run before this file).
Z1  No harm: ABSENT keeps form >= 0.99 in every phase and seed; its share of patch actions answered is within 0.05
    of BASELINE and its number of patch actions within 5% of BASELINE, in every phase and seed.
Z2  Babbling: with the partner ABSENT the untried m3 calls in >= 2500 of the 3000 steps of phase A in all seeds
    (a failure at confidence 0 has nothing to erode, so an untried call never stops).
Z3  Perceptual crossing, answers: in phase A the share of calls answered is higher with RESPONSIVE than with REPLAY
    in >= 4/5 seeds, median difference >= 0.15.
Z4  Perceptual crossing, the circuit's behaviour (falsification criterion): calls in phase A differ between
    RESPONSIVE and REPLAY by >= 20% (direction not predicted) in >= 4/5 seeds.
Z5  The partner becomes a cue only when it answers: at the end of phase A, r9->m3 has sediment >= 1 in >= 3/5
    seeds with RESPONSIVE and sediment 0 in >= 4/5 seeds with REPLAY.
Z6  Quiet when the partner leaves: with RESPONSIVE, calls in the last 500 steps of phase B are <= 50 in >= 4/5 seeds.
Z7  Recognition on return: with RESPONSIVE, in phase C the first call strictly after the partner's first gesture
    comes within 3 steps in >= 3/5 seeds.
Z8  Repetition is not digestible: in phase A, REPETITIVE has a lower share of calls answered than RESPONSIVE in
    >= 4/5 seeds.
