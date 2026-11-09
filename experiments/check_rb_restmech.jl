# S40 check (spec discussion/specs/S40-rb-restmech.md r1): gates first (no verdicts if one fails), then RM1-RM5 and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-restmech.json")))
SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(471:480, ",")), ",")))
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
ok = true; fail(m) = (println("GATE FAIL ", m); global ok = false)
gate(name, b) = b ? println("GATE ok  $name") : fail(name)
gate("rule rb", r["rule"] == "rb"); gate("H 392, W 15", r["H"] == 392 && r["W"] == 15); gate("seeds", r["seeds"] == SEEDS); gate("arm swap", r["arm"] == "swap")
kk = [(x["seed"], x["schedule"]) for x in r["runs"]]
gate("combinations (seed x schedule, each once)", sort(kk) == sort([(s, c) for s in SEEDS for c in SCHEDULES]) && allunique(kk))
ev = [e for x in r["runs"] for e in x["events"]]
gate("branch points present", !isempty(ev))
gate("15 records per branch", all(e -> all(b -> length(e[b]) == 15, ("N", "Z", "ZM")), ev))
gate("state comparator detects each one-sided change (negative controls)", all(values(r["states_equal_negtests"])))
gate("tie12 from the decision rule (m1-m2 tie true, m1-m0 tie false)", all(values(r["tie12_unit"])))
if get(ENV, "SKIPFREEZE", "0") != "1"
    REQUIRED = ["predictions-rb-restmech.md", "../discussion/specs/S40-rb-restmech.md", "restmech.jl", "check_rb_restmech.jl", "variant_horizon.jl", "../core/circuit.jl"]
    ff = joinpath(LAB, "experiments", "freeze-rb-restmech.txt"); isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    for fn in REQUIRED; fn in [strip(q[2]) for q in rows] || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); h == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1] ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
recs = [d for e in ev for b in ("N", "Z", "ZM") for d in e[b] if d["act"] != "dead"]
println("branch points $(length(ev)), recorded updates $(length(recs))")
println("RM1 mu wiring and involution: ", v(r["mu_wiring_ok"] && all(x -> x["involution_ok"], r["runs"])))
eq = [q for x in r["runs"] for q in x["equiv"]]; eqn = [q for q in eq if !q["tie"]]
println("RM2 equivariance outside patch-number ties: ", v(all(q -> q["same"], eqn)), " ($(count(q -> q["same"], eqn))/$(length(eqn)); with a tie $(length(eq) - length(eqn)), of which equal $(count(q -> q["tie"] && q["same"], eq)))")
mu(a) = a == "m1" ? "m2" : a == "m2" ? "m1" : a
function rm3(e)
    for i in 1:15
        n, z = e["N"][i], e["ZM"][i]
        if (n["act"] != "dead" && n["tie_by_patch"]) || (z["act"] != "dead" && z["tie_by_patch"]); return (ok = true, broke = true); end
        mu(n["act"]) == z["act"] || return (ok = false, broke = false)
    end
    (ok = count(d -> d["act"] == "m0", e["N"]) == count(d -> d["act"] == "m0", e["ZM"]), broke = false)
end
r3 = [rm3(e) for e in ev]
println("RM3 ZM = mu(N) up to the first symmetry break: ", v(all(x -> x.ok, r3)), " (points $(length(r3)), broken by a patch-number tie $(count(x -> x.broke, r3)), mismatches $(count(x -> !x.ok, r3)))")
println("RM4 decision self-check: ", v(all(d -> d["selfcheck"], recs)), " ($(count(d -> !d["selfcheck"], recs)) failures)")
hi(d) = d["y"][1] > d["y"][2] ? "m1" : d["y"][2] > d["y"][1] ? "m2" : nothing
zw = [d for e in ev for d in e["Z"] if d["act"] == "m0" && any(m -> m in ("m1", "m2"), d["cand"])]
# codex I-R 2 #5: both parts are the prediction: the conf deficit and the choice decided by key (not by a tie on key)
def = [d for d in zw if hi(d) !== nothing && d["conf"][hi(d)] < d["conf"]["m0"] && d["how"] in ("key", "idle, then key")]
println("RM5 Z m0 wins: newly high motor's conf < m0's and decided by key at >= 90%: ", isempty(zw) ? "未判定（対象の歩なし）" : v(length(def) / length(zw) >= 0.9),
        " ($(length(def))/$(length(zw)); conf deficit alone $(count(d -> hi(d) !== nothing && d["conf"][hi(d)] < d["conf"]["m0"], zw)))")
using Printf
for b in ("N", "Z", "ZM")
    ds = [d for e in ev for d in e[b]]
    hw = Dict{String,Int}(); for d in ds; d["act"] == "m0" && (hw[d["how"]] = get(hw, d["how"], 0) + 1); end
    println("  $b: m0 $(count(d -> d["act"] == "m0", ds)) patch $(count(d -> d["act"] in ("m1", "m2"), ds)) none $(count(d -> d["act"] == "none", ds)) dead $(count(d -> d["act"] == "dead", ds)) of $(length(ds)); m0 wins by: $(sort(collect(hw), by = x -> -x[2]))")
end
cs = [(hi(d) === nothing ? "-" : string(d["conf"][hi(d)]), string(d["conf"]["m0"]), hi(d) !== nothing && hi(d) in d["cand"]) for d in zw]
tab = Dict{Any,Int}(); for c in cs; tab[c] = get(tab, c, 0) + 1; end
println("  Z m0 wins (conf of the newly high motor, conf of m0, that motor a candidate): ", sort(collect(tab), by = x -> -x[2]))
