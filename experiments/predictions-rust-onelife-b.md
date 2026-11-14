# S49b predictions (frozen before any code change; 2026-11-14). Spec: ../discussion/specs/S49b-single-writer.md.

Lives: seeds 627-628 x laws L2, L2+SF x drives D1, D3 (the S49 check lives). No new seeds.
- PL1 (second writer refused): while one onelife-run holds a run file (blocked on its input), a second onelife-run on the same
  file exits with code 9 without changing the run file; the first then continues and ends with the same bytes as a solo run.
  All 8 lives. "Same file" means the same path name; aliases (symlink, hardlink) are outside the contract and not tested.
- PL2 (race): two onelife-run started at the same moment on the same run file with different drive inputs, 50 trials per life:
  in every trial exactly one proceeds and the other exits 9; the run file is at every observation one complete version; the
  end equals the solo run of the drives of the one that proceeded.
- PL3 (no stale lock): the holder is fed drives 0..1999, and killed with SIGKILL once the run file shows n = 2000 (it is then
  blocked on its input); a new onelife-run on the same path takes the lock and is fed drives 2000..9999; the end equals the
  uninterrupted run of drives 0..9999. All 8 lives. The lock file's presence or content changes nothing (an existing lock file with arbitrary bytes, and
  a missing one, give the same result).
- PL4 (regression): the whole of sh experiments/onelife_rust_check.sh (PR1-PR6 of S49) is still true with the new onelife-run.
- PL5 (input lines): a malformed line stops with code 6 without saving, alive or dead; an out-of-range integer pair stops with
  code 8 when alive and is consumed when dead (payload unchanged, n + 1).
- Any single failure = not established. Expected: all established.
