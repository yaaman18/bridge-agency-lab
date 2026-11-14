# S49c predictions (frozen before any code change; 2026-11-14). Spec: ../discussion/specs/S49c-interval-audit.md.

Lives: seeds 627-628 x laws L2, L2+SF x drives D1, D3 (the S49 check lives). No new seeds.
- PI1 (interval, production build): 6 drives fed at once to onelife-run take at least 60 s of wall time (measured by the test harness,
  not by onelife-run; it sleeps after the 6th drive too). The upper side is reported as an observation only (expected below
  about 63 s; scheduler load can exceed it and that is not a failure); the saved bytes equal those of the S49 build for the same drives.
- PI2 (the interval does not reach the state; fast test build): the whole of S49 (PR1-PR5) and S49b (PL1-PL5) still holds.
- PI3 (audit chain): after an uninterrupted run of N drives the audit has 1 start, N wait + 1 (the last wait meets the end of input), N begin, N commit, 1 end, no break; the
  chain verifies; every commit hash equals the SHA-256 of the payload after that drive (compared with the Julia reference).
- PI4 (unfinished steps and stops): aborting at the 4 crash points and with SIGKILL while waiting, then restarting: the audit
  tool reports the unfinished steps (crash before the rename: 1 each; after the rename: 0, reported as "audit behind"), a kill
  while waiting for input as an "unknown stop" (wait without begin),
  exactly the stops without end, and the end state equals the uninterrupted run. An unfinished step leaves the payload as before.
- PI5 (rollback and tampering): replacing the run file by an older complete version is reported by the audit tool; flipping a
  bit in the audit, deleting a line or deleting the file is reported (chain failure, or a break line with its reason: missing / unreadable / mismatch,
  started from an independent genesis); in each case onelife-run still
  runs and the state bytes are those of a run without the tampering. Two audits with different valid tails give the
  same payload and n after the same number of successful drives (the claim is non-interference of the transition result
  while audit writes succeed, not that the audit cannot stop the run).
- PI6 (audit unwritable): with the audit file not writable (also when the break line itself cannot be written) onelife-run exits
  non-zero before stepping and the run file is unchanged.
- Any single failure = not established. Expected: all established. Not claimed: detection of a fork made by copying both
  files elsewhere; durability under power loss; anything about another machine.
