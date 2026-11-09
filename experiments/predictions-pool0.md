# Predictions for S22 (discussion/specs/S22-body-pool0.md r1), frozen before any pool0.jl run
New seeds 181-220 (never run), SF, arms std/swap, 4 survival schedules, H 392, trial start pools P0 in {[0,0] (default), [5U,5U], [50U,50U]}; same raised object and noise copy.
A "j3 run" = a run with at least one point t in 64:32:384 where (3) of S18 holds (S19 three_at). Zero j3 runs under [0,0] -> GP1 and GP2 not evaluable.
- GP1: no run that is a j3 run under [0,0] is a j3 run under [50U,50U] (the same seed, arm, schedule). One such run -> miss.
- GP2: in every j3 run under [0,0], each edge of E (at the first j3 point) has its cOff first finite in the trial (not initially finite) at a trial update <= 3, with the value 1.0.
- GP3: the number of j3 runs under [5U,5U] and under [50U,50U] is each <= the number under [0,0].
