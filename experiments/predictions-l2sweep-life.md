# Predictions for item 86, the life check of the plateau (frozen 2026-11-03 after VQ5 failed, before these runs)

Validation: VQ1-VQ4 held (SF 30/30 at 0.003 and 0.002 on seeds 11-20, S 0/30), VQ5 failed: body_org's life with the same
circuit (scripted raising + sed_fade) and KC 0.003 from birth dies in seasons 10/10 (900-2526 steps), heldout 7/10,
random 10/10. The AGENCY-001 horizons (<= 588) end before those deaths.
Runs: eval_l2sweep_life.jl with KC = 0.0015, 0.002, 0.0025 (env KCLIFE), same worlds and seeds.

- LQ1: survival in seasons rises as KC falls; at 0.0015 seasons >= 8/10.
- LQ2: at 0.002 seasons <= 7/10.
- LQ3: random <= 3/10 at every KC.
