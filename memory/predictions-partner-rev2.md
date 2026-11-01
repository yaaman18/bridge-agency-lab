# Predictions for stage 20 revision 2 (partner.js rev. 2, test_partner.js rev. 2), written 2026-10-30 after
# results-partner-rev1.json (0/6 predictions held) and before any run of rev. 2. Changes: selection ranks
# confident > sedimented (habit) > sampled input; REPLAY shifts the recorded gestures by half a phase; the
# "first call after the first gesture" counts only calls strictly after it. Constants as in rev. 1.
# partner=false still reproduces memory.js (check_partner_off.js, 118000/118000 steps, run before this file).
Y1  No harm when absent: ABSENT keeps form >= 0.99 in every phase and seed, and its share of patch actions
    answered is within 0.05 of BASELINE in every phase and seed.
Y2  Perceptual crossing, answers: in phase A the share of calls answered is higher with RESPONSIVE than with REPLAY
    in >= 4/5 seeds, median difference >= 0.15.
Y3  Perceptual crossing, the circuit's behaviour (falsification criterion of the stage): the number of calls in
    phase A differs between RESPONSIVE and REPLAY by >= 20% (direction not predicted) in >= 4/5 seeds.
Y4  The partner's gesture is NOT learned as a cue for calling under these rules: r9->m3 ends phase A with
    confidence 0 and sediment 0 in >= 4/5 seeds with RESPONSIVE (rev. 1: an edge into a unit that has left the
    untried state is never tested again, and gestures mostly come after calls, not before).
Y5  Calls stop when the partner leaves: with RESPONSIVE, calls in the last 500 steps of phase B are <= 5 in
    >= 4/5 seeds.
Y6  Repetition is not digestible: in phase A, among seeds where both RESPONSIVE and REPETITIVE make >= 5 calls,
    REPETITIVE has the lower share answered in all of them (and there are >= 3 such seeds).
