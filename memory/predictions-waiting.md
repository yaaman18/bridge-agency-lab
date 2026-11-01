# Predictions for stage 52 (test_scaffold_seeds.js, summarize_waiting.js), written 2026-10-31 before any run beyond the
# five seeds already seen. Diagnosis first (post hoc, reported): in the seeds where waiting got worse with learn2/learn3
# (RESP-ADULT 3 and 4, SCAF-RAISED 2), the contingencies into m3 at the end of phase A are much the same as with turn.js;
# seeds 1 and 5 give identical runs; the measure is the share of calls made while waiting in the last 1000 steps of
# phase A (66-285 calls). Hypothesis: no systematic effect; learn3 changes only receptor -> patch motor edges, and any
# change makes these chaotic runs diverge. Checked: test_scaffold_seeds.js with the default seeds reproduces
# results-scaffold.json byte for byte. Seeds 1-40, turn.js vs turn_learn3.js. No new constants.
W1  For each condition (RESP-ADULT, SCAF-ADULT, SCAF-RAISED), phase A late waiting share: the number of seeds where
    learn3 is worse vs better is not significant by a two-sided sign test at 5% (ties dropped).
W2  For each condition, the median paired difference (learn3 - turn.js) is within +-0.03 and the mean over seeds with
    learn3 is at most the mean with turn.js + 0.03.
