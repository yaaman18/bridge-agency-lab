# Predictions for S40 (discussion/specs/S40-rb-restmech.md r1), frozen before any run on seeds 471-480

Revision r2 (2026-11-09, during the I-R before the freeze, no claim seed has been run): r1 (written after the smoke run) differed in
RM5 (r1 asked only the conf deficit, with "decided by key, not by a tie" in parentheses; r2 makes both a conjunction, codex I-R 2 #5)
and lacked the definition of the m1-m2 patch-number tie and of the compared state (added, codex I-R 2 #2-#4). RM1-RM4 thresholds are
unchanged. r1 was never frozen; this r2 is the version frozen. The pass criteria are the ones written in each RM (RM5: >= 90%).
Objects: RB :swap, seeds 471-480 (never run before), 4 survival schedules, H 392, branch points t in 32:32:392 alive; branches
N, Z (S39), ZM (Z with the circuit state mirrored by mu) of 15 updates. Written after the smoke run on seed 1 (seen, not evidence).
- RM1: mu preserves the wiring, and mirroring twice restores the state at every tested state.
- RM2: one-update equivariance (mirror(step(X)) = step(mirror(X)) with the mirrored schedule) holds at every tested state where
  neither update decided an m1-m2 tie by the patch number.
- RM3: at every branch point, ZM's acts equal mu(N's acts) at every update up to the first update (in N or ZM) whose choice was
  decided by the patch number between m1 and m2; when no such update occurs, the m0 counts of N and ZM are equal.
- RM4: the decision self-check holds at every recorded update (the rebuilt candidates equal the circuit's, the act is among them).
- RM5: in Z, among the updates where m0 wins with a patch motor among the candidates, at >= 90% both hold: the motor of the patch
  with the larger y at that update has a smaller conf than m0, and the choice was decided by key (after the idle filter), not by a
  tie on key.
"An m1-m2 tie decided by the patch number" (RM2, RM3) means: the final pool after key and old holds both m1 and m2 (a pool of m1
or m2 with m0 alone commutes with mu and is not excluded). The equivariance compares the whole state (AS.State and every side field:
circuit, world, noise, pools, Q0).
Falsification (each refutes only its proposition; causes are candidates): RM1 false -> mu is not a symmetry of the wiring or the
mirror is wrong; RM2 false -> the rule (or the mirror) is not mirror-equivariant outside patch-number ties (implementation omission or a
rule asymmetry, checked first); RM3 false -> ZM is not mirrored N before the first symmetry break; RM4 false -> the decision record does
not reproduce the circuit's choice (the record, not the circuit, is wrong); RM5 false -> m0's wins after Z are not mostly a conf deficit
of the newly high patch's motor.
