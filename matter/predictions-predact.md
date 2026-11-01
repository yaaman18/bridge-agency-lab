# Predictions for stage 35, the prediction currency made causal (trm2.js modes predact / frozen, test_trm2.js = test_trm.js
# with the module and modes as parameters), written 2026-10-31 after results-trm.json and results-field-matter.json and
# before any run of trm2.js in these modes. Reference: stage 33 nogate (results-trm.json): lean means 194/198/193, longest
# starvation survived 500/500/500, activity before lean vs rich 0.692/0.682, 0.664/0.690, 0.686/0.708.
# Note: trm2.js draws one more random number per network (wp), so trm2's nogate is not identical to trm.js's; the fixed
# mode is identical (checked).
V1  Conservation |error| < 1e-6 and persistence (> 0 at every sample, supply x0.5 and x1) for predact and frozen, 3/3 seeds.
V2  Prediction used for action helps under starvation: predact's longest survived starvation >= nogate's (run in the same
    file) in >= 2/3 seeds.
V3  Within-life learning matters when the prediction drives action: predact's lean-season mean count exceeds frozen's
    in >= 2/3 seeds.
V4  Anticipation: predact's activity in the 100 steps before a lean season is lower than before a rich season by >= 0.02
    in >= 2/3 seeds, and frozen's in <= 1/3 seeds.
