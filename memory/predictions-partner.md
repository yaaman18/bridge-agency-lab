# Predictions for stage 20, the partner as part of the world (partner.js, test_partner.js)
# Written 2026-10-30 before any run of partner.js with partner=true. New constants chosen for this stage (not
# changes of existing numbers): answer window W = 10 steps, gesture kinds 4, freshness 0..5 regrowing +1 every 20 steps.
# Scripted partners only (protocol in the header of test_partner.js). Seeds 1-5.
X1  Perceptual crossing, answers: in phase A the share of calls answered is higher with RESPONSIVE than with REPLAY
    in >= 4/5 seeds, and the median difference is >= 0.15.
X2  Perceptual crossing, the circuit's own behaviour (the falsification criterion of the stage): calls in the last
    500 steps of phase A differ between RESPONSIVE and REPLAY by >= 20% (RESPONSIVE more) in >= 4/5 seeds.
    If they do not differ, the partner is for the circuit only "a place that answers sometimes", not a partner.
X3  No harm when the partner is absent: ABSENT keeps form >= 0.99 in every phase, and its share of patch actions
    answered is within 0.05 of BASELINE in every phase and seed.
X4  The partner sediments: with RESPONSIVE, at the end of phase B (2000 steps absent) r9->m3 still has sediment
    >= 1 in >= 4/5 seeds, while calls in the last 500 steps of B are <= 20% of those in the last 500 of A.
X5  Return: in phase C with RESPONSIVE, the first call after the partner's first gesture comes within 3 steps in
    >= 4/5 seeds.
X6  Repetition is not digestible: in phase A, REPETITIVE has a lower share of calls answered than RESPONSIVE in all
    5 seeds.
