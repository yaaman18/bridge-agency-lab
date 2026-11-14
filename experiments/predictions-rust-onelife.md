# S49 predictions (frozen before any code exists; 2026-11-14). Spec: ../discussion/specs/S49-rust-onelife.md.

Units: seeds 627-628 x laws L2, L2+SF x drives D1, D3 (S48b) = 8 lives, N = 10000 drives. Julia core/one_life.jl is the reference.
- PR1: for every life and every n = 1..N, the SHA-256 of the saved bytes after n drives is identical in Julia and Rust
  (live steps, the detection step and all steps after death).
- PR2: the final saved bytes are identical; a Julia save loaded by Rust and continued equals the Julia continuation, and a Rust
  save loaded by Julia and continued equals the Rust continuation (save positions n = 0, 1999, 2000, d, d+1 where it dies, 9999).
- PR3 (onelife-run, interrupted): killing the process with SIGKILL after n = 1, 1999, 2000, 6000, 9998 drives have been consumed and restarting from the run file with
  the remaining drives (from position n recorded in the file) ends with the same bytes as the uninterrupted run, for all 8 lives. With the crash-point test build (abort before the temp write, after
  it, after its fsync, after the rename) the run file is always one complete version, old or new, and the continuation ends with
  the same bytes. The claim is consistency under process interruption, not durability under power loss.
- PR4 (onelife-run, after death): for D3 lives, after detection the payload bytes of the run file never change while the
  drives keep being consumed and n keeps increasing to N; the process ends normally when the input ends.
- PR5 (no repair): a run file with one flipped bit (200 positions per life, header and payload) is refused with a non-zero exit
  and is not rewritten; a missing run file is an error (no birth); truncation, trailing bytes, an
  unknown version, non-zero reserved bytes, an out-of-range length and n = u64::MAX are refused without rewriting; an out-of-range drive on a live state stops without saving.
- PR6 (exp): the written-out fdlibm exp equals Julia's jsexp on every one of the 400,000 inputs and on every exp argument that
  occurs in the 8 lives (implied by PR1).
- Any single mismatch = not established; S49 then stops (no tolerance). Expected: all established. I do not know whether D3
  lives of seeds 627-628 die before 6000 (S48b has not been run when this is frozen); if a D3 life does not die, the death
  parts of PR1, PR2, PR4 are "not checked" for that life.
