# Predictions for item 86, validation (frozen 2026-11-03 after the refinement, before these runs)

Refinement (predictions-l2sweep-refine.md): RQ1-RQ3 held. SF (scripted raising + sed_fade) L2 30/30 at KCTRIAL
0.0015-0.008 (0.008 with 10 runs lost even with the tracking intact), 17/30 at 0.00125, 0/30 at 0.010 and above (every run
lost with the tracking intact). Chosen by the frozen rule: geometric middle of the 30/30 plateau sqrt(0.0015 * 0.008) =
0.00346 -> grid value 0.003. 0.002 (the existing KC of stages 44-54) also lies on the plateau.

Validation runs on new seeds 11-20 (H 294 392 588, both readings): SF and S at 0.003 and 0.002. And 10 000 steps of
body_org (eval_l2sweep_life.jl: scripted raising, L2's rule + sed_fade, KC 0.003 for the whole life, worlds seasons /
heldout / random as eval_grow.jl, seeds 1-10).

- VQ1: SF at 0.003, seeds 11-20: L2 true >= 27/30 in each reading.
- VQ2: SF at 0.003, seeds 11-20: no run lost with the tracking intact.
- VQ3: SF at 0.002, seeds 11-20: L2 true >= 27/30 in each reading.
- VQ4: S at 0.003, seeds 11-20: L2 true 0/30 (sed_fade is what makes the tracking needed).
- VQ5: body_org life, KC 0.003: seasons and heldout 10/10, random <= 3/10.

Falsification: if VQ1 fails, the plateau found on seeds 1-10 is fitted to those seeds and the chosen value is not stable.
