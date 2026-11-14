# S48b predictions (frozen before any code exists; 2026-11-14). Spec: ../discussion/specs/S48b-death-drive.md r1.

Units: seeds 615-616 (smoke), 617-626 (main, run once) x laws L2, L2+SF x drives D3, D4 = 40 lives. N = 10000 drives.
D3: n < 2000 as D1 (BO_CUR 800 then frozen seasons); 2000 <= n < 6000 (0,0); n >= 6000 (5,5).
D4: n < 6000 (0,0); n >= 6000 (5,5). The drive is a function of n only.

- PD1: every one of the 40 lives is detected dead at some d < 6000. (My guess; I have not run a zero drive on a raised body.)
- PD2 equivalence up to detection: for every t < d the OneLife state after drive t equals the end-of-step-t snapshot of
  body_org_run fed the same sequence, the acts are equal, and death = d on both sides (where the reference can be fed the same
  sequence without changing body_org.jl; otherwise that span is reported as out of scope).
- PD3 after death: from the detection to N (including the (5,5) span from n = 6000) the saved bytes are identical at every step.
- PD4 resume across death: saving after n drives, loading in another process and continuing to N equals the straight run, for
  n = d-2, d-1, d, d+1, d+2, 6000 and floor(k*N/5), k = 0..4.
- PD5: every one of 200 single-bit flips of the save of a dead state is refused by the loader.
- Count rule (fixed before the run): per cell (law x drive, 10 lives), fewer than 3 lives detected dead before n = 6000 -> the
  death items of that cell are "not checked". A life not dead by 6000 is outside PD3/PD4 and counted as "not checked".
- Any single mismatch in PD2-PD5 = not established. Survival performance is not read.
