# Predictions for S41 (discussion/specs/S41-rb-provenance.md r2), frozen before any run on seeds 481-490

Revision r2 (2026-11-09, during the I-R before the freeze; no claim seed has been run). r1 was written after the smoke run on seed 1
(as stated below) and never frozen. r2 changes, codex I-R 2: PV4 three-valued (r1: a hit whenever no W zeroing was seen, which let
undetermined targets pass); "distinct" defined with the place of the zeroing (r1: (seed, schedule, edge, update, class), which could
split one zeroing by class or merge zeroings of different branches); the falsification limited to what is judged (PV3 false = Z0 not
confirmed, which does not say the edge was positive). PV1-PV3 thresholds are unchanged. This r2 is the version frozen.

Objects: RB :swap, seeds 481-490 (never run before), 4 survival schedules, H 392, Z branches of 15 updates from t in 32:32:392.
Events and target edges E* as the spec section 1. Written after the smoke run on seed 1 (seen, not evidence).
- PV1: the attribution matches the actual q at every update of every target's history (no target is undetermined).
- PV2: among the targets whose q at the trial's start is > 0, >= 90% are "zeroed by D while m* did not act", both counted over
  all target occurrences and over the distinct (seed, schedule, edge, zeroing place).
- PV3: every target whose q at the trial's start is 0 is "Z0" (zero over the whole trial).
- PV4: no target is zeroed by W (alone or with D).
PV4 is three-valued: a W zeroing -> miss; no W zeroing but an undetermined target -> undetermined; every target classified and no
W zeroing -> hit. "Distinct" means distinct (seed, schedule, edge, place of the zeroing: the main run's update, shared by every
branch, or the Z branch's update); this merges the same zeroing seen from different branch points.
Falsification (each refutes only its proposition): PV1 false -> the rule's copy does not reproduce q at some update (there the
attribution, not the circuit, is wrong); PV2 false -> the share of "zeroed by D while m* did not act" among the initially positive
targets is below 90% in one of the two counts; PV3 false -> Z0 is not confirmed for some initially zero target (it was positive at some update,
or it is undetermined; an undetermined one does not say it was positive); PV4 false -> some current zero was produced by a W drop (an act of m* without an answer).
