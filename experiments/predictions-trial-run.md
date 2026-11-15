# S54 predictions (r2 after the S-R; r1 is in freeze 0; frozen before any code is written and before the trial is started; 2026-11-15). Spec: ../discussion/specs/S54-trial-run.md.

Two rehearsal lives on the Raspberry Pi 5 (seed 669; L2 and L2+SF; 60480 drives, 10 s per step, about 7 days). The
reference (Julia, every step) is computed before the trial, so the death steps will be known; whether a life lives is
not predicted and not a question of this stage.
- PT1 (agreement): at every hourly check the run file on the Pi (one copy; n and SHA from that copy) is, byte for byte, the reference state at its n; at the
  end every commit line in each audit carries the reference SHA of its n (missing commit lines after a power cut are
  counted and reported, not a miss; a commit line with a different SHA is a miss, reported with the first n).
- PT2 (interval): between any two checks at least 30 minutes apart with no boot between them, n grows by no more than
  (elapsed seconds on the Mac's clock) / 10, plus 1. The Pi's clock is not used.
- PT3 (stops and restarts): the number of boots is taken from the boot identifiers (S52 log, watch file); it is the
  canonical count. After every boot each life goes on without anyone's hand (n grows again by the next check) and PT1
  keeps holding; n never goes down between checks. For each life the number of start lines in the audit is at most
  boots + 1; start lines lost with the unsynced tail of the audit are counted and reported (not a miss). Unfinished
  steps and unknown stops are reported as a lower and an upper bound. No boot during the trial = "no occasion".
- PT4 (machine): throttled stays 0x0 at every check; no error line in either audit; no ext4 error in the kernel log
  that remains at each check (the log does not survive a power cut, so errors just before a cut cannot be excluded;
  after each boot the filesystem state and error count from tune2fs are recorded). A miss here is itself a finding.
- Reported without prediction: death steps (already in the reference), counts of break lines and of "audit behind",
  clock drift of the Pi at each resync, temperature from the S52 log.
- Not claimed: anything about other machines, real input channels, longer periods, a cut-out individual, or that an
  individual feels anything.
