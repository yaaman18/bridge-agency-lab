# Predictions for turn.js rev. 2 (proprioception at the end of the step), written 2026-10-30 after
# results-scaffold.json / results-diag-scaffold.json (stage 25 with rev. 1: S1, S2, S5 held; S3, S4 failed: late share of
# calls made while waiting 0.53-0.63 with SCAF-ADULT; only 0.29-0.41 of them right after a gesture; r11 and r10 drove
# about half) and before any run of rev. 2. Same harnesses (test_orient.js for stage 23, test_scaffold.js for 25).
V1  No harm (both harnesses): form >= 0.99 and share of patch actions answered within 0.05 of BASELINE everywhere.
V2  Waiting is learned under scaffolding: SCAF-ADULT late share of calls made while waiting <= 0.3 in >= 3/5 seeds.
V3  Through r11: SCAF-ADULT ends phase A with r11 -> m3 sediment >= 1 in >= 3/5 seeds.
V4  Still not with an indifferent partner: RESP-ADULT late share > 0.5 in >= 4/5 seeds.
V5  The remaining calls made while waiting are mostly right after a gesture (>= 0.5, diag on SCAF-ADULT), i.e. the
    conjunction limit (c3 + r9 alone reaches threshold) is what is left.
