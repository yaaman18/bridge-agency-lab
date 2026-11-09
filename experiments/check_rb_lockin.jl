# S42 check (spec discussion/specs/S42-rb-lockin.md r2): gates first (no verdicts if one fails), then LK1-LK4 and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-lockin.json")))
SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(491:500, ",")), ",")))
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
ok = true; fail(m) = (println("GATE FAIL ", m); global ok = false)
gate(name, b) = b ? println("GATE ok  $name") : fail(name)
gate("rule rb", r["rule"] == "rb"); gate("H 392, L 160", r["H"] == 392 && r["L"] == 160); gate("seeds", r["seeds"] == SEEDS); gate("arm swap", r["arm"] == "swap")
kk = [(x["seed"], x["schedule"]) for x in r["runs"]]
gate("combinations (seed x schedule, each once)", sort(kk) == sort([(s, c) for s in SEEDS for c in SCHEDULES]) && allunique(kk))
E = [merge(e, Dict("seed" => x["seed"], "schedule" => x["schedule"])) for x in r["runs"] for e in x["events"]]
B = [e for e in E if e["mstar"] !== nothing]
gate("branches present", !isempty(B))
gate("decision self-check on every update", all(e -> e["selfcheck"], B))
R_all = [e for e in B if e["outcome"] == "release"]
gate("replay agrees with the recorded first act", all(e -> e["one_step"]["replay_agrees"], R_all))
# codex I-R 1 #3: a dead update on the idle_first-off side is a mechanical anomaly (the same state was alive as is)
gate("one-step comparison: the idle_first-off side is not dead", all(e -> e["one_step"]["act_idle_first_off"] != "dead", R_all))
neg = [e["one_step_t1"] for e in B if e["one_step_t1"] !== nothing]
gate("one-step comparison negative control (no idle motor at t+1: same act, replay agrees)", !isempty(neg) && all(x -> x["same"] && x["replay_agrees"], neg))
if get(ENV, "SKIPFREEZE", "0") != "1"
    REQUIRED = ["predictions-rb-lockin.md", "../discussion/specs/S42-rb-lockin.md", "lockin.jl", "check_rb_lockin.jl", "variant_horizon.jl", "../core/circuit.jl"]
    ff = joinpath(LAB, "experiments", "freeze-rb-lockin.txt"); isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    for fn in REQUIRED; fn in [strip(q[2]) for q in rows] || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); h == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1] ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
# codex I-R 1 #1: a verdict over an empty denominator is "判定不能" (not observable), not a hit and not a refutation
vn(n, b) = n == 0 ? "判定不能（分母 0）" : v(b)
frac(a, n) = n == 0 ? "0/0" : "$a/$n = $(round(a / n; digits = 3))"
M = [e for e in B if e["main_point"] && e["rest15"]]
R = [e for e in M if e["outcome"] == "release"]; D = [e for e in M if e["outcome"] == "death"]; K = [e for e in M if e["outcome"] == "lock"]
println("branches $(length(E)) (excluded y1 == y2 or dead at t+1: $(length(E) - length(B))), main points $(count(e -> e["main_point"], B)), main set (rest15) $(length(M)): release $(length(R)), death $(length(D)), lock $(length(K))")
println("LK1 no lock in the main set: ", vn(length(M), isempty(K)), " ($(length(K)))")
n101 = count(e -> e["since_lastM"] == 101, R)
lk2 = all(e -> e["flags"]["idle_mstar"], R) && n101 >= 0.9 * length(R)
println("LK2 every release with m* idle, and since_lastM == 101 >= 90%: ", vn(length(R), lk2), " (idle $(count(e -> e["flags"]["idle_mstar"], R))/$(length(R)), 101 $(frac(n101, length(R))))")
noff = count(e -> e["one_step"]["act_idle_first_off"] != e["mstar"] && !(e["mstar"] in split(e["one_step"]["act_idle_first_off"], ",")), R)
println("LK3 idle_first off -> the act is not m* >= 90%: ", vn(length(R), noff >= 0.9 * length(R)), " ($(frac(noff, length(R))))")
nans = count(e -> e["answered"] == true && e["q_up"], R)
println("LK4 every first act answered and raises an edge of m*: ", vn(length(R), nans == length(R)), " ($nans/$(length(R)))")
cnt(xs) = sort(collect(Dict(a => count(==(a), xs) for a in unique(xs))); by = string)
println("  first-act flags: how ", cnt([e["flags"]["how"] for e in R]), "; allzero_stale ", count(e -> e["flags"]["allzero_stale"], R),
        "; m0 a candidate ", count(e -> e["flags"]["m0_candidate"], R), "; key(m*) >= key(m0) ", count(e -> e["flags"]["key_mstar_ge_m0"], R))
println("  since_lastM ", cnt([e["since_lastM"] for e in R]), "; candidate at idle onset ", cnt([e["cand_at_idle_onset"] for e in R]),
        "; act with idle_first off ", cnt([e["one_step"]["act_idle_first_off"] for e in R]))
println("  act with idle_first off, the breakdown (codex I-R 1 #3: m0, none or the other motor) ", cnt([e["one_step"]["act_idle_first_off"] for e in R]))
println("  later act of m* with no idle motor (updates after the first act) ", cnt([e["later_nonidle_act"] === nothing ? nothing : e["later_nonidle_act"] - e["k"] for e in R]))
# codex I-R 1 #5: the dead update is alive_steps + 1 (dead_k); compared with k_idle_due as before / same / after
rel(e) = e["dead_k"] < e["k_idle_due"] ? "before" : e["dead_k"] == e["k_idle_due"] ? "same" : "after"
println("  deaths: (dead update, k_idle_due) ", [(e["dead_k"], e["k_idle_due"]) for e in D], "; dead update vs the idle due ", cnt(rel.(D)),
        "; candidate at idle onset (deaths after the due) ", cnt([e["cand_at_idle_onset"] for e in D if e["idle_onset_k"] !== nothing]))
println("  locks: candidate at idle onset ", cnt([e["cand_at_idle_onset"] for e in K]))
println("  m0_all15 ", count(e -> e["m0_all15"], M), "/$(length(M)); other motor's acts ", cnt([e["other_acts"] for e in M]), "; order_constant ", count(e -> e["order_constant"], B), "/$(length(B))",
        "; no act of m* in the trial before t ", count(e -> e["no_act_in_trial_before_t"], M))
println("  by seed (release, death, lock) ", [(s, count(e -> e["seed"] == s && e["outcome"] == "release", M), count(e -> e["seed"] == s && e["outcome"] == "death", M), count(e -> e["seed"] == s && e["outcome"] == "lock", M)) for s in SEEDS])
X = [e for e in B if !e["main_point"] && e["rest15"]]
println("  extension (t in 256:32:384, rest15) $(length(X)): ", cnt([e["outcome"] == "release" ? "release" * (e["flags"]["idle_mstar"] ? "/idle" : "/" * e["flags"]["how"]) : e["outcome"] for e in X]))
println("  not rest15 at the main points: ", cnt([e["outcome"] for e in B if e["main_point"] && !e["rest15"]]))
