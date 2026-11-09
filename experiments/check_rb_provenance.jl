# S41 check (spec discussion/specs/S41-rb-provenance.md r2): gates first (no verdicts if one fails), then PV1-PV4 and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-provenance.json")))
SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(481:490, ",")), ",")))
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
# codex I-R 2 #3, #4: the distinct zeroings are (seed, schedule, edge, where the zeroing happened: the main run's update, shared by
# every branch, or this Z branch's update); a target without a zeroing (Z0) counts once per (seed, schedule, edge)
dkey(t) = (t["seed"], t["schedule"], t["edge"], t["zeroing_loc"])
function distinct(xs)
    g = Dict{Any,Set{String}}(); for t in xs; push!(get!(g, dkey(t), Set{String}()), t["class"]); end
    [(k..., only(v)) for (k, v) in g if length(v) == 1]
end
classes_unique(xs) = (g = Dict{Any,Set{String}}(); for t in xs; push!(get!(g, dkey(t), Set{String}()), t["class"]); end; all(v -> length(v) == 1, values(g)))
ok = true; fail(m) = (println("GATE FAIL ", m); global ok = false)
gate(name, b) = b ? println("GATE ok  $name") : fail(name)
gate("rule rb", r["rule"] == "rb"); gate("H 392, W 15", r["H"] == 392 && r["W"] == 15); gate("seeds", r["seeds"] == SEEDS); gate("arm swap", r["arm"] == "swap")
kk = [(x["seed"], x["schedule"]) for x in r["runs"]]
gate("combinations (seed x schedule, each once)", sort(kk) == sort([(s, c) for s in SEEDS for c in SCHEDULES]) && allunique(kk))
T = [merge(t, Dict("seed" => x["seed"], "schedule" => x["schedule"])) for x in r["runs"] for t in x["targets"]]
gate("targets present", !isempty(T))
gate("attribution unit tests (real update, perturbed q caught, W, W then D, D, W at q = 0)", all(values(r["attribution_unit"])))
gate("target fields", all(t -> all(k -> haskey(t, k), ("class", "q_start", "attribution_ok", "zeroed_at", "zeroing_loc", "edge", "core", "conf_zero", "tau")), T))
gate("one class per distinct zeroing (seed, schedule, edge, place)", classes_unique(T))
if get(ENV, "SKIPFREEZE", "0") != "1"
    REQUIRED = ["predictions-rb-provenance.md", "../discussion/specs/S41-rb-provenance.md", "provenance.jl", "check_rb_provenance.jl", "variant_horizon.jl", "../core/circuit.jl"]
    ff = joinpath(LAB, "experiments", "freeze-rb-provenance.txt"); isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    for fn in REQUIRED; fn in [strip(q[2]) for q in rows] || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); h == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1] ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
DIS = "zeroed by D while m* did not act"
ev = sum(x -> x["n_events"], r["runs"]); println("events $ev, targets $(length(T)) (distinct (seed, schedule, edge, zeroing) $(length(distinct(T))))")
println("PV1 attribution matches everywhere: ", v(all(t -> t["attribution_ok"], T)), " ($(count(t -> !t["attribution_ok"], T)) targets with a mismatch)")
P = [t for t in T if t["q_start"] > 0]; Pd = distinct(P)
f1 = isempty(P) ? NaN : count(t -> t["class"] == DIS, P) / length(P); f2 = isempty(Pd) ? NaN : count(d -> d[5] == DIS, Pd) / length(Pd)
println("PV2 initially positive -> zeroed by D while m* did not act >= 90%: ", isempty(P) ? "未判定（対象なし）" : v(f1 >= 0.9 && f2 >= 0.9),
        " (occurrences $(count(t -> t["class"] == DIS, P))/$(length(P)) = $(round(f1; digits = 3)), distinct $(count(d -> d[5] == DIS, Pd))/$(length(Pd)) = $(round(f2; digits = 3)))")
Zt = [t for t in T if t["q_start"] == 0]
println("PV3 initially zero -> Z0: ", isempty(Zt) ? "未判定（対象なし）" : v(all(t -> startswith(t["class"], "Z0"), Zt)), " ($(count(t -> startswith(t["class"], "Z0"), Zt))/$(length(Zt)))")
# codex I-R 2 #2: W found -> miss; no W but some target undetermined -> undetermined; all classified and no W -> hit
nW = count(t -> occursin("W", t["class"]), T); nU = count(t -> t["class"] == "undetermined", T)
println("PV4 no zeroing by W: ", nW > 0 ? "外れ" : nU > 0 ? "未判定（分類できない対象が残る）" : "的中", " (W $nW, undetermined $nU)")
tab(xs, f) = (d = Dict{Any,Int}(); for x in xs; d[f(x)] = get(d, f(x), 0) + 1; end; sort(collect(d), by = z -> -z[2]))
println("  classes (occurrences): ", tab(T, t -> t["class"]))
println("  classes (distinct): ", tab(distinct(T), d -> d[5]))
for (lab, xs) in (("conf(m*) = 0", [t for t in T if t["conf_zero"]]), ("0 < conf(m*) < conf(m0)", [t for t in T if !t["conf_zero"]]), ("core edges", [t for t in T if t["core"]]))
    println("  $lab: $(length(xs)) targets, distinct $(length(distinct(xs))); ", tab(xs, t -> t["class"]))
end
println("  by edge (distinct): ", tab(distinct(T), d -> (d[3], d[5])))
println("  by seed (distinct, initially positive, D while not acting / all): ", sort([(s, count(d -> d[1] == s && d[5] == DIS, Pd), count(d -> d[1] == s, Pd)) for s in SEEDS]))
gaps = [t["zeroed_at"] - t["last_act_before_zeroing"] for t in T if t["class"] == DIS && t["last_act_before_zeroing"] !== nothing]
nact = count(t -> t["class"] == DIS && t["last_act_before_zeroing"] === nothing, T)
println("  D zeroings while m* did not act: updates since m*'s last act median $(isempty(gaps) ? "-" : sort(gaps)[cld(length(gaps), 2)]) (n $(length(gaps))); m* never acted in the trial before the zeroing: $nact")
