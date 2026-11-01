# Predictions for stage 32, the material layer with fixed-rule constituents (matter.js, test_matter.js), written
# 2026-10-31 before any run of test_matter.js. Parameters (DEF in matter.js, reservoir 300) were chosen in a short
# exploratory pass (explore.js: reservoir 150/300/600 x supply 0.5/1/2, and one starvation run with and without A-gen),
# reported as such; the maintenance cost METAB was added after the first exploratory pass showed that constituents never
# died (matter kept recirculating inside the body). Predictions below cover runs that were not explored (other start
# site, short starvation, damage) and restate the explored ones.
X1  Conservation: |total matter - initial| < 1e-6 mu at every step of every run.
X2  Persistence: with supply x0.5, x1, x2 and start sites (12,12), (9,15), constituents > 0 at every 100-step sample to
    5000 steps (6/6 runs).
X3  Material death is irreversible under A-gen: starvation from 1000 to 2000 leaves 0 constituents by 2000 and 0 until
    6000 although supply returns; with spontaneous generation (control) constituents are back (> 0) by 3000.
X4  Short starvation is survived: starvation 1000-1200 leaves >= 1 constituent at every sample and the count by 3000 is
    >= 80% of the undamaged twin's.
X5  Regeneration: removing every constituent in the left half (x < 12) at step 2000, the count is back to >= 80% of the
    undamaged twin within 1000 steps (by step 3000) and stays >= 80% at 3500 and 4000.
