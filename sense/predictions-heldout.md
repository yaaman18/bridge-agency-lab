# Held-out validation of learn.js rev. 4 (heldout.js), written 2026-10-29 before running. Receptors: r1 noise p=.3,
# r2 y2>=4, r3 clock5, r4 y1>=1, r5 y1==0, r6 y2>y1, r7 y1>=4, r8 y2==0. Seasons: (2,4) (4,0) (0,4) (3,3) per 250 steps.
# Rev. 1-4 were each changed after seeing results on the original receptors and world, so this is the first test the
# rules were not tuned on.
H1  curriculum/full, seeds 1-5: noise (r1) and clock (r3) contingencies end at 0 for both motors.
H2  curriculum/full: test form >= 0.9 and answered >= 0.9.
H3  curriculum/full: silencing informative receptors changes the acting patch more often than silencing r1 (noise).
H4  explore-off never acts; fail-off answers no more than full.
