# Predictions for stage 37 (test_var2.js; trm2.js unchanged), written 2026-10-31 after results-var.json (stage 36: 3/3,
# predact > frozen by 1-9% in 3 seeds) and before any run of test_var2.js. User: "continue 1 and 2".
# Paired per seed (same world for all modes). Seeds 1-10. MOVE 1000 (season period 300-800) and MOVE 500 (200-800).
U1  Conservation |error| < 1e-6 and persistence (> 0 at every 50-step sample) in every run.
U2  Within-life learning pays (MOVE 1000): predact's mean count (2000-8000) exceeds frozen's in >= 7/10 seeds.
U3  More variation, more payoff: with MOVE 500, predact exceeds frozen in >= 7/10 seeds, and the mean over seeds of
    (predact - frozen) / frozen is larger than with MOVE 1000.
U4  The structure-only form measures are defined for frozen: its F_coup > 0 in >= 9/10 seeds (unlike the precision-gated F).
U5  Coupling is not explained by learning alone: |F_coup(predact) - F_coup(frozen)| < 0.1 in >= 7/10 seeds (MOVE 1000).
