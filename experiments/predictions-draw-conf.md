# S57 (A1) predictions (r2 after the S-R; r1 is in freeze 0; frozen before any code is written or run; 2026-11-15). Spec: ../discussion/specs/S57-draw-conf.md.

Arms DET, UNI, CONF (weights 1 + conf[m]); world of item 155 at M = 2.5; laws L2 and L2+SF judged separately; pilot
windows 686-689, evaluation windows 690-725 (n = 36). Known before this freeze: S55 (item 165) on windows 674-685 -
unpredicted counts of runs alive to the horizon: L2 DET 9, UNI 12, FIXP 12 of 12; L2+SF DET 8, UNI 11, FIXP 9 of 12.
Nothing is known for CONF or for these windows. Paired sign tests over windows, two-sided 5 %, ties dropped, fewer than
8 non-ties = undetectable. Each prediction judged alone, per law. The author's confidence is low for PB2-PB4.
- PB0 (pilot): both laws admitted (all arms alive at T0 + 2000 in at least 3 of 4 pilot windows, at least 200 drawing
  steps per window), and CONF has at least 100 drawing steps with unequal weights in every one of the 4 pilot windows.
  If the last part fails, PB2 is "below the pre-set admission condition" (not a proof that CONF equals UNI) and is
  reported so; no redraw, no added windows.
- PB1 (mechanism): for UNI and CONF, per law, pooled over the evaluation windows, for every group of draws with the same
  specified probabilities and at least 400 draws: the chi-square goodness-of-fit test does not reject at 1 % (Holm over
  the groups within law and arm; uncorrected p-values beside) and every chosen share is within 0.05 of the specified
  one. Replay from the bit files reproduces every recorded choice.
- PB2 (answered share of the heavier against the lighter candidate; CONF arm, the states CONF visits): per window, over
  the N drawing steps with unequal weights, D = mean[ 1(heavier chosen) Y / p_H - 1(lighter chosen) Y / p_L ], Y = 1 if
  the act was answered (y[p] > 0 at the step of the act), p_H and p_L the specified probabilities at that step. Windows
  with N < 100 are dropped (their number is reported). Predicted: D > 0 ("larger" by the sign test over windows), both
  laws. Beside it: the plain difference of the two chosen groups' answered shares, the smallest p_L and its
  distribution. If D is not larger, the reading "in the states CONF visits, the candidate with the larger certainty is
  answered more often" is not supported. No causal reading; nothing about states other arms visit.
- PB3 (replication of S55's unpredicted observation, now as a test): death step (counted from T0; a run alive at the
  common horizon T0 + 9200 gets 9201; windows where both arms reach the horizon are ties) of UNI later than DET
  ("larger" by the sign test), L2. For L2+SF: no direction predicted (reported). Wins, losses and ties are reported;
  "undetectable" is not read as "equal".
- PB4 (CONF against UNI and against DET, death step): CONF vs UNI undetectable; CONF vs DET larger (later death) for
  L2; L2+SF no prediction (reported).
- Reported without prediction: alive at T0 + 500, T0 + 2000 and the horizon per arm; body sizes; share of answered acts
  per arm; distribution of the weights; share of rejected bit groups; agreement with DET's choice from the recorded
  DET choice at the same state.
- Not claimed: that drawing is better in general; a causal reading of PB2; anything about real radio bits, a predictor,
  traces, worlds with swaps, or that the individual feels anything. "Matching", not "no goal-directedness".
