# Predictions for stage 39 (test_neutral.js, summarize_neutral.js): separating selection from drift. Written 2026-10-31
# before any run of seeds 1-10. Exploratory before freezing: a check that the observer hooks change nothing (seed 99,
# 800 steps, identical state) and one 1000-step smoke run per world with seed 99 (not a test seed).
# World as stage 38 rev. 2 (48x48, 6 patches, 9 founder groups = 81 lineages, nogate, 20000 steps), seeds 1-10, LEAN/RICH.
# New constants of this test (observers only): NMK = 20 neutral markers, NSH = 200 shadow populations.
N0  Conservation |error| < 1e-6 at every 500-step sample and > 0 constituents at every sample, all 20 runs.
N1  Selection on ba exists: final mean ba exceeds the final means of all 20 neutral markers (same genealogy, same
    mutation, no effect) in >= 8/10 seeds of EACH world. (Under no selection the chance per run is 1/21.)
N2  It is stronger in LEAN: (final mean ba - median of the 20 marker means) is larger in LEAN than RICH in >= 7/10 seeds
    (paired by seed).
N3  It acts through division (the gate act >= 0.5): the birth-side term Cb of ba is > 0 in >= 8/10 seeds of each world,
    and Cb > Cd (the death-side term) in >= 7/10 seeds of each world.
N4  Lineages are lost faster than by drift in a well-mixed population of the same census: final founder lineages below the
    2.5th percentile of the 200 neutral shadows in >= 8/10 seeds of each world.
N5  Drift alone (the shadows, which only know the census) already loses more lineages in LEAN: shadow median lineages
    LEAN < RICH in >= 8/10 seeds (paired).
N6  Stage 38 E4 replicates with 10 seeds: real final lineages LEAN < RICH in >= 8/10 seeds (paired).
Reading: N1 with N2 would say the rise of ba is selection, stronger where matter is scarce; N4 says lineage loss exceeds
well-mixed drift (selection and/or spatial structure, which this test does not separate); N5 says the census difference
alone predicts the direction of the lineage difference between worlds.
