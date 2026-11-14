# S51 predictions (r2 after the S-R; frozen before any build for the Pi and before any run on it; 2026-11-14). Spec: ../discussion/specs/S51-other-machine.md.

Machines: Mac (x86_64-apple-darwin, reference) and one Raspberry Pi 5 (aarch64, musl static build cross-compiled on the Mac).
Source: commit d5a7f6d (S49b). Lives: seeds 627-628 x laws L2, L2+SF x drives D1, D3, N = 10000. No new seeds.
- PM1 (arithmetic): on the Pi, onelife-selftest is true (SHA-256 vectors, sqrt and floor against the hardware on 2,000,000
  inputs), and the fdexp column of onelife-exp on the S49 inputs (780,553) is byte-identical to the Mac's. The std exp column
  (the platform's libm) is reported as an observation only; it may differ and that is not a failure.
- PM2 (every step, by the SHA-256 of the state after each step; no collision assumed): for each of the 8 lives, onelife-check on the Pi gives the same per-step SHA file and the same saves at
  the points (0, 1999, 2000, 9999, the last) as on the Mac: 8 of 8, all 10000 steps. For 627 x D3 x 3000 drives (both laws)
  the Pi's files equal the Julia reference in core/check/out directly.
- PM3 (onelife-run): for each of the 8 lives, onelife-run on the Pi fed the 10000 drives ends with a run file byte-identical
  to the Mac's; killed with SIGKILL after the run file at n = 2000 has been observed (onelife-info) and restarted with the remaining drives, the end is the same: 8 of 8.
- PM4 (the save format and the resume are compatible between the machines; an operator copies a snapshot, which is a check
  intervention, not an autonomous move and not a cut-out): a run file written on the Mac at n = 2000, copied to the Pi and continued there to
  10000, is byte-identical at the end to the uninterrupted Mac run; the same in the other direction (Pi to Mac): 8 of 8 each
  way. The D3 lives die on the same step on both machines.
- PM5 (lock): on the Pi a second onelife-run on the same run file exits 9 and leaves the file unchanged (1 life, 627-L2-D1).
- Any single failure = not established. Expected: all established (the core uses only + - * / sqrt floor and its own exp;
  no fused multiply-add is emitted by default). Falsified by any differing byte in the compared files and columns (the std exp column is not compared).
- Gate M1 also compares the SHA-256 of the Pi executable before and after the copy.
- Not claimed: a build made on the Pi, toolchain portability, other ARM machines, other OS or libc, other compiler versions, power-loss durability, Julia running on the Pi,
  anything about S49c (interval and audit).
- Smoke (frozen here too): 627-L2-D1, N = 50, to test the script and estimate the time; not used for any claim.
