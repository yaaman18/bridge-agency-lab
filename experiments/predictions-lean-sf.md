# Predictions for S21 (discussion/specs/S21-body-lean-sf.md r1), frozen before any run
SF default of variant_horizon.jl, new seeds 171-180, structures :constituents/:q, horizons 60,294,392,588, arms CUR=std and CUR=swap.
- LS1: for each arm, Lean's checkSelfProducing and checkValueNeeded agree with Julia's verdicts on every table passed (one disagreement -> miss). An arm with zero checkValueNeeded tables makes that part not evaluable.
