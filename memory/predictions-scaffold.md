# Predictions for stage 25, the scaffolding partner (test_scaffold.js, CORE=turn.js), written 2026-10-30 before any
# SCAF run. User 2026-10-30: "continue implementing with your recommendations for a while" -> orient.js rev. 2 is
# adopted as the lab's base (recommended), then scaffolding is tried. test_scaffold.js reproduces results-raise.json
# for RESP/TURN conditions exactly (checked before this file). No new constants except the scaffold length 1500.
S1  No harm: SCAF-ADULT and SCAF-RAISED keep form >= 0.99 and a share of patch actions answered within 0.05 of
    BASELINE in every phase and seed.
S2  Babble ends under scaffolding (unlike TURN): calls in the last 1000 steps of phase A < 500 in >= 4/5 seeds, for
    SCAF-ADULT and for SCAF-RAISED.
S3  Waiting is learned (criterion): late (last 1000 of A) share of calls made while waiting <= 0.3 in >= 3/5 seeds for
    SCAF-ADULT, and lower than RESP-ADULT in >= 4/5 seeds.
S4  If S3 fails, the cause is the conjunction limit: the calls made while waiting are mostly (>= 0.5) at the step right
    after a gesture (driven by r9). [Measured from the trace by diag_scaffold.js only if S3 fails.]
S5  SCAF-RAISED learns waiting at least as well as SCAF-ADULT (late share no higher by more than 0.1) in >= 4/5 seeds.
