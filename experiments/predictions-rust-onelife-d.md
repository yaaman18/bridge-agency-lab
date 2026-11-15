# S49d predictions (r3; r2 is in freeze 1 and its PD1 is recorded as a MISS, see the note at the end; r1 is in freeze 0; frozen before any code change; 2026-11-15). Spec: ../discussion/specs/S49d-partial-line.md.

Known before this freeze: gate H1 of S54 failed on the S49c build (the break line is glued to the partial line);
the final states were equal to the uninterrupted run.
- PD1 (partial line; r3): for an audit cut inside its last line at three places, on the 8 comparison lives, the next
  start writes a newline and then "break mismatch"; onelife-audit reports breaks 1 with the reason mismatch; the run
  goes on and its final run file is byte-identical to the uninterrupted run. Malformed lines before the break: exactly 1
  for the cuts 1 byte into the line and mid-line; exactly 0 for the cut just before the newline (the whole record is
  there, the added newline completes it and it chains; chain_ok true). Negative controls: the S49c build on the same
  cut audits reports breaks 0; an uncut audit gets no break.
- PD2 (no other change): for audits that end in a newline (including empty and missing audits), the S49d build and the
  S49c build write byte-identical run files and audits on the 8 lives x 10000 steps and in the crash and tamper scenes
  of S49c's PI4 and PI5.
- PD3 (S49c still holds): PI1, PI3, PI4, PI5, PI6 of S49c hold with the S49d build, including a missing audit, an
  empty audit and a newline-terminated audit at the start. PI2 is replaced by PD2 (plan B of the S-R); the source diff
  against the S49c build is only the branch in Audit::open (checked).
- PD5 (the newline cannot be written): with a partial last line and an audit that cannot be written, onelife-run stops
  with a non-zero exit before stepping; the run file is unchanged. Negative control: the same audit, writable, goes on.
- PD4: rust/being-core and core/ unchanged (SHA as in freeze-rust-onelife-c-code.txt); sh core/check/run.sh exits 0; 0 warnings.
- Not claimed: truncation at a line boundary is caught; the audit survives a power cut (no fsync); anything about the Pi.
- Note on r2's PD1 (a miss, kept): r2 predicted "exactly 1 malformed line before it" for all three cuts. The smoke run
  (life 627-L2-D1, N = 40, before the code freeze and before the one main run) showed 0 malformed lines for the cut
  just before the newline. That was claude-lab's error in the prediction, not a defect of the fix. r3's PD1 for that cut
  is therefore written knowing the smoke result on one life; for the other 7 lives and N = 10000 it is not yet known.
