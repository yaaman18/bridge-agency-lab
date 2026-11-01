# Predictions for revision 4 of learn.js (only tested = transmitting contingencies can be confirmed), 2026-10-29,
# written after seeing rev. 3 (results-rev3.json) and before running rev. 4.
# Rev. 3 outcome in short: acquisition works (useful contingencies learned by step ~53 with the curriculum, ~305
# without; failure rule needed: without it answered falls 0.99 -> 0.70), but noise (r5) and clock (r6) receptors and
# cues of the other patch became confident by mere co-occurrence; silencing informative receptors changed the action
# in 0.11-0.24 of branch steps.
Q1  curriculum/full, seeds 1-5: at the end of training the noise and clock contingencies (r5, r6 into both motors)
    are at 0.
Q2  curriculum/full: test form >= 0.9 and answered >= 0.9 (as rev. 3).
Q3  curriculum/full: silencing the informative receptors changes the acting patch in more branch steps than in
    rev. 3 (> 0.13), and silencing the noise receptor in fewer than 0.02.
Q4  Curriculum still learns the useful contingencies earlier than no curriculum.
Q5  Ablations keep their direction: fail-off answers less than full; explore-off never acts.
