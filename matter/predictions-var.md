# Predictions for stage 36, a variable world (test_var.js, trm2.js), written 2026-10-31 after results-predact.json (stage 35:
# within-life learning showed no benefit in the fixed seasonal world; predact raised activity before lean seasons) and
# before any run of test_var.js. Inference behind W2-W3 (Baldwin): learning pays when the world varies within a life in ways
# inherited constants cannot track.
W1  Conservation |error| < 1e-6 and persistence (> 0 at every 50-step sample) for all three modes and seeds.
W2  Within-life learning pays in a variable world: predact's mean count (steps 2000-8000) exceeds frozen's in >= 2/3 seeds.
W3  It pays most after the sources move: predact's mean of the minimum counts in the 500 steps after each move exceeds
    frozen's in >= 2/3 seeds.
