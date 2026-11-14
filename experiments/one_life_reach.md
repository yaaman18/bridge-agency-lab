# S48 G4 (2): existing functions reached from onelife_step (core/one_life.jl)

Read from the source (2026-11-13), the path of the two laws L2 and L2+SF only (contrast :bin3, idle_first, core_gate,
seen_both false, sed_fade per law; no sil, y_offer, body_flag, rest options). "External state" = ENV, global, time, rand,
Ref, file I/O, or a mutable const that is written. Token scan of core/circuit.jl, matter.jl, jsmath.jl, body_org.jl for
ENV / global / time( / rand( / Ref / open( / read( / write(: no hit in code (two hits of "global" are comments, circuit.jl:73, :288).

| function | file:line | external state |
|---|---|---|
| `Base.deepcopy` | Base | none (copies the input) |
| `Mulberry(seed::Integer)`, `(r::Mulberry)()` | core/jsmath.jl:111, :112 | none (state in the object) |
| `state_int32` | core/jsmath.jl:119 | none |
| `step!(st::CState, b::Circuit, y; ...)` and its local closures `idle`, `key`, `rank`, `passes`, `grow`, `weaken`, `ok`, `okc`, `rm` | core/circuit.jl:116-303 | none; reads the const `FEATURES`, `P_*`, `ALPHA`, `THETA_*`, `FORGET`, `L2RULES`; default `sil = Set{Int}()` is fresh per call |
| `feature` | core/circuit.jl:26 | reads const `FEATURES` (Vector of closures; never written in core/ or experiments/*.jl) |
| feature closures (`FEATURES` entries) | core/circuit.jl:13-20 | none; "noise" calls the passed rng |
| `allocate` | core/circuit.jl:107 | none |
| `port_take!`, `port_give!` | core/matter.jl:17, :20 | none (the port in the world) |
| `step!(w::World, sources, ctl = NOCTL)` | core/matter.jl:83-130 | none; `NOCTL` (:81) is an immutable struct of nothings; work arrays P, out, scl, pi, pj, pf live in the world |
| `bell` | core/matter.jl:65 | none |
| `jsexp` | core/jsmath.jl:13 | ccall to libm `exp`: taken as fixed values on the same machine and the same executable. Agreement across machines is the question of the Rust comparison (P1-6) and is not checked here |
| `nsites` | core/matter.jl:63 | none |

Mutable consts of core/ (Vector, Dict): `FEATURES` (circuit.jl:13, reached, never written), `_NPIO2_HW` (jsmath.jl:41,
not reached by this path; read only), `BO_CUR` (body_org.jl:9, not reached by the step; read by the drive maker),
`RULES` (life.jl:9) and `ALPHA_FEATURES` (dc.jl:24) not reached. Only reached-and-read; none written (grep for indexed
assignment and push! on them: no hit in core/ or experiments/*.jl; one hit in core/check/js_scenarios.js, the JavaScript copy).

The save and load (`onelife_save`, `onelife_load_L2`, `onelife_load_L2SF`) reach `SHA.sha256` (Julia stdlib, read with
`using SHA`; not in Project.toml [deps], claude-lab decision 2026-11-13) on bytes in memory; no file I/O in core/one_life.jl.

Birth (`onelife_birth`, not the step) reaches `make_world`, `kernel`, `jshypot`, `seed!`, `newborn`, `reindex!`, `init`.
