# S39 check (spec discussion/specs/S39-rb-envresp.md r1): gates first (no verdicts if one fails), then EV1-EV5 and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-envresp.json")))
SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(461:470, ",")), ",")))   # SEEDS only for the smoke test
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
ok = true; fail(m) = (println("GATE FAIL ", m); global ok = false)
gate(name, b) = b ? println("GATE ok  $name") : fail(name)   # codex I-R 2 #6: every gate prints its success
gate("rule rb", r["rule"] == "rb"); gate("H 392", r["H"] == 392); gate("seeds", r["seeds"] == SEEDS); gate("arms std, swap", r["arms"] == ["std", "swap"])
gate("no named runs", isempty(r["named"]))
kk = [(x["seed"], x["arm"], x["schedule"]) for x in r["runs"]]
gate("combinations (seed x arm x schedule, each once)", sort(kk) == sort([(s, a, c) for s in SEEDS for a in ("std", "swap") for c in SCHEDULES]) && allunique(kk))
gate("controls", get(r, "controls_ok", false) === true)
ev = [merge(e, Dict("arm" => x["arm"])) for x in r["runs"] for e in x["events"]]
gate("branch points present", !isempty(ev))
gate("RB fields", all(e -> all(k -> haskey(e, k), ("b_act", "b_rb", "b_act_rb", "a_prec", "R2c_act", "m0_Z", "b_act_Z", "b_act_Zrb", "rb_on_clamped")), ev))
# codex I-R 2 #3: the clamp works where it is called: rb never on after an update of a clamped branch
gate("rb clamp effective (rb on in clamped branches = 0)", all(e -> e["rb_on_clamped"] == 0, ev))
gate("clamped updates per point = 2 x 15 (not vacuous)", all(e -> get(e, "n_clamped", 0) == 30, ev))
if get(ENV, "SKIPFREEZE", "0") != "1"
    REQUIRED = ["predictions-rb-envresp.md", "../discussion/specs/S39-rb-envresp.md", "envresp.jl", "check_rb_envresp.jl", "variant_horizon.jl", "../core/circuit.jl", "../core/dc.jl"]
    ff = joinpath(LAB, "experiments", "freeze-rb-envresp.txt"); isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    for fn in REQUIRED; fn in [strip(q[2]) for q in rows] || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); h == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1] ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
cnt(p, xs = ev) = count(p, xs)
tab(k, xs) = sort([(x, cnt(e -> e[k] == x, xs)) for x in unique([e[k] for e in xs])], by = string)
sw = [e for e in ev if e["arm"] == "swap"]; sd = [e for e in ev if e["arm"] == "std"]
println("branch points $(length(ev)) in $(length(r["runs"])) runs (:std $(length(sd)), :swap $(length(sw)))")
mis = [(e["t"], m, d["mismatch"]) for e in ev for (m, d) in e["c_detail"] if !isempty(d["mismatch"])]
println("EV1 no alpha mismatch: ", v(isempty(mis)), " ($(length(mis)) mismatches)")
bd = [e for e in sw if e["b"] != "undetermined"]; f2 = isempty(bd) ? NaN : cnt(e -> e["b"] == "holds", bd) / length(bd)
println("EV2 :swap (b) holds <= 30% of determined: ", isempty(bd) ? "未判定（判定できる点なし）" : v(f2 <= 0.3), " ($(cnt(e -> e["b"] == "holds", bd))/$(length(bd)) = $(round(f2; digits = 3)))")
zn = sum(e -> e["b_act_Z"]["n"], sw; init = 0); zm = sum(e -> e["b_act_Z"]["nm0"], sw; init = 0)   # every point (codex I-R 2 #2)
println("EV3 :swap m0 >= 50% of Z counted updates: ", zn == 0 ? "未判定（数える歩なし）" : v(zm / zn >= 0.5), " ($zm/$zn)")
f4 = isempty(sw) ? NaN : cnt(e -> e["b_rb"] == e["b"], sw) / length(sw)
println("EV4 :swap b_rb = b at >= 90%: ", isempty(sw) ? "未判定" : v(f4 >= 0.9), " ($(cnt(e -> e["b_rb"] == e["b"], sw))/$(length(sw)))")
sdr = [x for x in r["runs"] if x["arm"] == "std"]
println("EV5 :std all die before H, (b) never holds: ", v(all(x -> x["death_main"] !== nothing && x["death_main"] < 392, sdr) && !any(e -> e["b"] == "holds", sd)),
        " (dead $(cnt(x -> x["death_main"] !== nothing, sdr))/$(length(sdr)), deaths $(sort(unique([x["death_main"] for x in sdr]), by = string)), b holds $(cnt(e -> e["b"] == "holds", sd)))")
for (lab, xs) in ((":std", sd), (":swap", sw)), k in ("a", "a_prec", "b", "b_act", "b_act_why", "b_Z0", "b_prime", "b_uncoupled", "need", "c", "R2c", "R2c_act", "b_rb", "b_act_rb")
    println("  $lab $k: ", tab(k, xs))
end
println("  :swap a vs a_prec differ at $(cnt(e -> e["a"] != e["a_prec"], sw)) points; rb at t+1 (N, Z): ", sort(collect(Dict(string((e["rb_t1_N"], e["rb_t1_Z"])) => cnt(f -> (f["rb_t1_N"], f["rb_t1_Z"]) == (e["rb_t1_N"], e["rb_t1_Z"]), sw) for e in sw))))
for k in ("m0_N", "m0_Z", "m0_Nrb", "m0_Zrb", "rb_on_N", "rb_on_Z"); println("  :swap $k total ", sum(e -> e[k], sw; init = 0), " over $(length(sw)) points x 15 updates"); end
for k in ("b_act_N", "b_act_Z", "b_act_Nrb", "b_act_Zrb")   # the counted updates of each branch, normal and rb clamped (codex I-R 2 #4)
    println("  :swap $k sums ", Dict(f => sum(e -> e[k][f], sw; init = 0) for f in ("n", "h", "l", "nact", "nm0", "nnone", "ndead")))
end
rbd = [(e["t"], m, d["diff"]) for e in ev for (m, d) in e["c_detail"] if d["usable"] && "rb" in d["diff"]]
println("  (c) usable events where rb differs (recorded only): $(length(rbd))")
