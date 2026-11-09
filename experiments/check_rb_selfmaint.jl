# S37 check (spec discussion/specs/S37-rb-selfmaint.md r1): gates first (no verdicts if one fails), then RP1-RP9.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
f = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-selfmaint.json")))
SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(441:450, ",")), ","))   # SEEDS is set only for the smoke test on used seeds
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
runs = f["runs"]; ok = true
fail(m) = (println("GATE FAIL ", m); global ok = false)
f["rule"] == "rb" || fail("rule")
f["seeds"] == SEEDS || fail("seeds"); f["horizons"] == [392] || fail("H"); f["arms"] == ["std", "swap"] || fail("arms")
keys3 = [(x["seed"], x["arm"], x["schedule"]) for x in runs]
(sort(keys3) == sort([(s, a, c) for s in SEEDS for a in ("std", "swap") for c in SCHEDULES]) && allunique(keys3)) || fail("combinations")
get(f, "controls_ok", false) === true || fail("controls $(get(f, "controls", nothing))")
get(f, "lean_windows", 0) > 0 || fail("no Lean windows")
ev = [merge(e, Dict("arm" => x["arm"])) for x in runs for e in x["events"]]
isempty(ev) && fail("no branch points")
all(e -> haskey(e, "a_prec") && haskey(e, "b1p") && haskey(e, "T_prec"), ev) || fail("RB fields missing")
# codex I-R 5: the frozen sha and Lean's agreement are gates before any verdict
if get(ENV, "SKIPFREEZE", "0") != "1"   # SKIPFREEZE only for the smoke test before the freeze
    # codex I-R 3 #8: every required file must be in the freeze file, and each match is printed
    REQUIRED = ["predictions-rb-selfmaint.md", "../discussion/specs/S37-rb-selfmaint.md", "selfmaint.jl", "check_rb_selfmaint.jl",
                "variant_horizon.jl", "../core/circuit.jl", "../core/dc.jl", "dc_lean_body.sh", "../formal/LabCircuit.lean",
                "../formal/SelfMaintenance.lean"]
    ff = joinpath(LAB, "experiments", "freeze-rb-selfmaint.txt")
    isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    names = [strip(r[2]) for r in rows]
    for fn in REQUIRED; fn in names || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); got = split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1]
        h == got ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
if get(ENV, "SKIPLEAN", "0") != "1"
    lean_ok = success(`sh $(joinpath(LAB, "experiments", "dc_lean_body.sh")) $(get(ENV, "GEN", "rb"))`)
    lean_ok ? println("GATE Lean checkDC identical to Julia (formal/gen/lean-output-body.txt)") : fail("Lean checkDC differs from Julia")
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
cnt(p, xs = ev) = count(p, xs)
println("branch points $(length(ev)) in $(length(runs)) runs (:std $(cnt(e -> e["arm"] == "std")), :swap $(cnt(e -> e["arm"] == "swap")))")
rp1 = all(e -> e["conf_X"] == 0, ev); println("RP1 no confirmation in X: ", v(rp1), " (X confirmations $(sum(e -> e["conf_X"], ev)))")
rp1 || println("  L9 map refuted: every b1/b1p and every T resting on it is undetermined")
println("RP2 original kappa never empty in X: ", v(!any(e -> e["kappa_ever_empty_X"], ev)), " ($(cnt(e -> e["kappa_ever_empty_X"])) points with it empty)")
println("RP3 original (a) fails everywhere: ", v(all(e -> e["a"] == "fails" && e["clauses"]["self"] == false, ev)), " (a: $(sort([(x, cnt(e -> e["a"] == x)) for x in unique([e["a"] for e in ev])])), T holds $(cnt(e -> e["T"] == "holds")))")
println("RP4 b1p holds everywhere, LSH2 map unbroken on kappa_prec: ", v(all(e -> e["b1p"] == "holds", ev) && !any(e -> e["kp_inc_X"], ev)), " (b1p: $(sort([(x, cnt(e -> e["b1p"] == x)) for x in unique([e["b1p"] for e in ev])])), q increases $(cnt(e -> e["kp_inc_X"])))")
println("RP5 X dies by t+H: ", v(all(e -> e["death_X"] !== nothing, ev)), " ($(cnt(e -> e["death_X"] === nothing)) X branches alive)")
# codex I-R 6: RP6 is refuted only by Y dying before X; a point with both alive at t+H is undetermined for the order
rp6bad = cnt(e -> e["death_Y"] !== nothing && (e["death_X"] === nothing || e["death_Y"] < e["death_X"]))
rp6und = cnt(e -> e["death_X"] === nothing && e["death_Y"] === nothing)
# codex I-R 2 #4: undetermined while any point has no order
println("RP6 Y dies no earlier than X: ", rp6bad > 0 ? "外れ" : rp6und > 0 ? "未判定（順序の決まらない点が残る）" : "的中", " (Y earlier $rp6bad, both alive (undetermined) $rp6und, Y later $(cnt(e -> e["death_X"] !== nothing && (e["death_Y"] === nothing || e["death_Y"] > e["death_X"]))), same $(cnt(e -> e["death_X"] !== nothing && e["death_Y"] == e["death_X"])))")
stdr = [x for x in runs if x["arm"] == "std"]; stde = [e for e in ev if e["arm"] == "std"]
println("RP7 :std all die before H, b2 fails: ", v(all(x -> x["death_main"] !== nothing && x["death_main"] < 392, stdr) && all(e -> e["b2"] == "fails", stde)), " (:std runs dead $(cnt(x -> x["death_main"] !== nothing, stdr))/$(length(stdr)), deaths $(sort(unique([x["death_main"] for x in stdr]; ), by = string)), b2 fails $(cnt(e -> e["b2"] == "fails", stde))/$(length(stde)))")
swr = [x for x in runs if x["arm"] == "swap"]; swe = [e for e in ev if e["arm"] == "swap"]
ap = isempty(swe) ? NaN : cnt(e -> e["a_prec"] == "holds", swe) / length(swe)
alive = [x for x in swr if x["alive_at_H"]]
# codex I-R 7: no :swap run alive at H -> the second half has nothing to judge (not a hit)
println("RP8 :swap a_prec >= 50% and T_prec in every run alive at H: ", isempty(alive) ? "未判定（H で生きる走りなし）" : v(ap >= 0.5 && all(x -> any(e -> e["T_prec"] == "holds", x["events"]), alive)), " (a_prec $(round(ap; digits = 3)), runs alive $(length(alive))/$(length(swr)), with T_prec $(cnt(x -> any(e -> e["T_prec"] == "holds", x["events"]), alive)))")
println("RP9 T_prec_core = T_prec: ", v(all(e -> e["T_prec_core"] == e["T_prec"], ev)), " (points where they differ: $([(e["t"], e["T_prec"], e["T_prec_core"]) for e in ev if e["T_prec_core"] != e["T_prec"]]))")
for arm in ("std", "swap"), k in ("a", "a_prec", "b1", "b1p", "b2", "b3", "T", "T_prec", "T_prec_core")
    es = [e for e in ev if e["arm"] == arm]
    println("  $arm $k: ", sort([(x, cnt(e -> e[k] == x, es)) for x in unique([e[k] for e in es])]))
end
for arm in ("std", "swap")
    rs = [x for x in runs if x["arm"] == arm]; a = Dict(k => sum(x -> x["acts"][k], rs) for k in ("m0", "patch", "none"))
    es = [e for e in ev if e["arm"] == arm]
    println("  $arm acts per living update $a  m0 acts in X $(sum(e -> e["m0acts_X"], es; init = 0)) in Y $(sum(e -> e["m0acts_Y"], es; init = 0))")
end
