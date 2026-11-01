# Predictions for stage 22 revision 2 (orient.js rev. 2: habituation of the orienting response), written 2026-10-30
# after results-orient-rev1.json (3/6 held, two of them trivially) and before any run of rev. 2. test_orient.js gains
# only the report of h for r9->m3. orient=false still reproduces partner.js (check_orient_off.js, run before this file).
P1  No harm: ABSENT keeps form >= 0.99 in every phase and seed, and its share of patch actions answered is within
    0.05 of BASELINE in every phase and seed.
P2  The partner becomes a cue: with RESPONSIVE, r9 -> m3 has sediment >= 1 at the end of phase A in >= 4/5 seeds.
P3  Only a contingent partner makes it a cue: with REPLAY, r9 -> m3 has sediment 0 at the end of phase A in >= 4/5 seeds.
P4  No permanent silence, and the calls are cued: with RESPONSIVE, the last 1000 steps of phase A have >= 5 calls and
    >= 0.5 of them come at the step right after a gesture, in >= 4/5 seeds.
P5  Recognition on return: with RESPONSIVE, in phase C the first call strictly after the first gesture comes within
    3 steps in >= 4/5 seeds.
P6  Quiet when the partner leaves: with RESPONSIVE, calls in the last 500 steps of phase B are <= 50 in >= 4/5 seeds.
P7  Habituation keeps the clock and noise out of the habits: in ABSENT at the end of phase A, the summed sediment of
    r5 and r6 into m1 and m2 is <= 2 in >= 4/5 seeds (rev. 1: 6-8 of 8).
