# S48 predictions (frozen before any code exists; 2026-11-13). Spec: ../discussion/specs/S48-one-life.md r2 §5.

Units: seeds 589-590 (smoke, development), 591-600 (main, run once). Laws: L2 (bin3+IDLE+GATE), L2+SF (L2+SEDFADE).
Drives: D1 = BO_CUR (800 steps) then frozen seasons; D2 = frozen seasons from step 0. Horizon N = 10000 drives.
Numbers: U 0.02, MCOST 0.004, KC 0.002. Reference: body_org_run("ORG", seed, o) with RAISE "body", FEED true (D1) / false (D2).

Smoke (589-590): every gate G0-G7 and its negative control behaves as specified; P1, P3, P4, P5 hold on both seeds.

Main (591-600, both laws, both drives = 40 lives):
- P1 equivalence: for every life and every t < T (T = the reference's death step, or N), the OneLife state after drive t equals
  the reference's end-of-step-t snapshot (circuit state, wiring, perm, noise state, matter world, pools), and the acts of step t
  are equal. If the reference reports death = d, the OneLife step given drive d sets dead with death = d and changes nothing else.
  If the reference reports no death, dead stays false after N drives. Any single mismatch = not established.
- P3 after death: for every life that dies, and for one synthetic emptied state per law, 10000 drives of (5,5) and one
  out-of-range drive leave the saved bytes identical and raise no error.
- P4 save and resume: saving after n drives, loading in another process and continuing gives states identical to the straight
  run, for n = floor(k*N/20), k = 0..19, and, for lives that die at d, also n = d, d+1, d+2. Any mismatch = resume
  equivalence refuted (cause to be diagnosed; not read directly as "the state is insufficient").
- P5 corruption: each of 200 single-bit flips per life (positions drawn by Mulberry(seed), header and checksum included) makes
  the load fail with an error and return no state. A save of the other law is refused as well.
- Count rule: if fewer than 3 of the 40 lives die within N, the death items of P1, P3, P4 are reported "not checked" for the
  generated lives (the synthetic emptied state still counts for P3).

Expected: all of P1, P3, P4, P5 established. I do not know how many of the 40 lives die within N (weak guess: D2 lives die
more often than D1 lives; not a prediction).
