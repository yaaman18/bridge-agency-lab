# Predictions for the acquisition of sensation (learn.js, educate.js), written 2026-10-29 before any run.
# Receptors: r1 y1>=3, r2 y2>=3, r3 y1==0, r4 y2==0, r5 noise, r6 clock3, r7 y1>y2, r8 y2>y1 (the circuit is not told).
# Useful contingencies: r1->m1 or r7->m1, and r2->m2 or r8->m2. Harmful: r3->m1, r4->m2.
P1  curriculum/full, seeds 1-5: at the end of training a useful contingency for each motor has confidence >= 1,
    and both harmful ones are at 0.
P2  curriculum/full, test world (1000 steps): form >= 0.9 and answered >= 0.9 of acting steps.
P3  curriculum/full: silencing the informative receptors changes the acting patch in >= 0.2 of branch steps,
    more than silencing the noise receptor does.
P4  fail-off: at least one harmful contingency ends >= 1, and the test's answered share is lower than full's.
P5  explore-off: the newborn never acts (no contingency into a motor can ever be confirmed); test form < 0.1.
P6  no-curriculum/full also satisfies P1 by the end (2000 world steps); reported: first step at which the
    useful contingencies are learned, curriculum vs none.
