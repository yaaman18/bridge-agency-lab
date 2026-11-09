# Predictions for item 86, refinement (frozen 2026-11-03 after the coarse sweep, before these runs)

Coarse sweep (predictions-l2sweep.md, 2/6: WQ1 WQ5 held; WQ2 WQ3 WQ4 WQ6 failed): SF (scripted raising + sed_fade) L2 true
0/30 at 0.0005, 13/30 at 0.001, 30/30 at 0.0015-0.004 (both readings, no run lost with the tracking intact); S (no
sed_fade) 0/30 everywhere (no schedule needs the tracking); G best 7/30 at 0.0025 (bounded by its 7 differentiated seeds).
The search now finds the edges of SF's plateau and checks G near its best.

Runs: SF at KCTRIAL 0.00125 0.005 0.006 0.008 0.010 0.012 0.015 0.020; G at 0.00225 0.00275 (seeds 1-10, H 294 392 588).

- RQ1: SF stays 30/30 at 0.005 and 0.006; the upper edge (first value below 30/30) is >= 0.008, and beyond it runs are
  lost with the tracking intact.
- RQ2: SF at 0.00125 scores between 14 and 29.
- RQ3: G scores <= 7 at 0.00225 and 0.00275.

After these runs the chosen value is the geometric middle of SF's 30/30 plateau, rounded to an existing grid value; it is
validated on seeds 11-20 with a separate frozen prediction.
