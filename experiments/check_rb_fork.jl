# S43 check (spec discussion/specs/S43-rb-fork.md r2): gates first (the life/death judgment tests A1–A4 among them; no verdicts if
# one fails), then FK1–FK4 and the description. PRED=smoke checks against freeze-rb-fork-smoke.txt (seed 1), else freeze-rb-fork.txt.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-fork.json")))
SMOKE = get(ENV, "PRED", "main") == "smoke"
SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", SMOKE ? "1" : join(501:510, ",")), ",")))
SCHEDULES = ["p1-high", "p2-high", "p1-then-p2", "p2-then-p1"]
const L = 160
ok = true; fail(m) = (println("GATE FAIL ", m); global ok = false)
gate(name, b) = b ? println("GATE ok  $name") : fail(name)
gate("rule rb", r["rule"] == "rb"); gate("H 392, L 160", r["H"] == 392 && r["L"] == L); gate("seeds", r["seeds"] == SEEDS); gate("arm swap", r["arm"] == "swap")
kk = [(x["seed"], x["schedule"]) for x in r["runs"]]
gate("combinations (seed x schedule, each once)", sort(kk) == sort([(s, c) for s in SEEDS for c in SCHEDULES]) && allunique(kk))
E = [merge(e, Dict("seed" => x["seed"], "schedule" => x["schedule"])) for x in r["runs"] for e in x["events"]]
B = [e for e in E if e["mstar"] !== nothing]
gate("branches present", !isempty(B))
# ---- the life/death judgment (user 2026-11-09; codex V1 1–4)
chk(c) = c["a1"] && c["a1_vanish_then_dead"] && c["a2"]
gate("A1/A2 on the main runs (dead set <=> no body site before a live update; the last site removed -> dead at the next update; a dead update: no act, no circuit update, q only by B7, sg and lastM kept, no unit on, never undead)",
     all(x -> chk(x["main_checks"]), r["runs"]))
gate("A1/A2 on every branch, actual and m* silenced", all(e -> chk(e["checks_A"]) && chk(e["checks_NM"]), B))
# codex I-R 1 #1: required for every combination with a live branch point (none only where the main run gave no point)
NT = [x["negtests"] for x in r["runs"] if x["negtests"] !== nothing]
# codex I-R 2 #2: eligible = a branch point whose next state is alive; a combination with none is "not verified" (reported, not a pass)
gate("A3 present for every combination with an eligible point", all(x -> (x["n_eligible_A3"] == 0) == (x["negtests"] === nothing), r["runs"]))
gate("B7 flag unit tests (built q: decay update, other update; wrong: no decay, decay off period, below zero, extra)", all(values(r["q_b7_unit"])))
gate("A3 negative tests ((a) all sites emptied -> dead, (b) one site below THETA_EXIST with no free matter -> removed by the world, dead at the next update, (c) a copy known alive -> alive and equal to the run; after the death in (b), 16 dead updates pass A1/A2 (n_dead 16) with B7 exercised twice; the checker catches a corrupted dead update: clock, q, act, undead)",
     !isempty(NT) && all(t -> all(values(t)), NT))
gate("A4 the protocol's survives agrees with ours (not dead at H and a non-sensor unit on in each step of the alive window)",
     all(x -> x["A4"]["protocol_survives"] == x["A4"]["ours_alive_as_protocol"], r["runs"]))
if get(ENV, "SKIPFREEZE", "0") != "1"
    PF = SMOKE ? "predictions-rb-fork-smoke.md" : "predictions-rb-fork.md"
    REQUIRED = [PF, "../discussion/specs/S43-rb-fork.md", "fork.jl", "check_rb_fork.jl", "variant_horizon.jl", "../core/circuit.jl", "../core/matter.jl"]
    ff = joinpath(LAB, "experiments", SMOKE ? "freeze-rb-fork-smoke.txt" : "freeze-rb-fork.txt"); isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    for fn in REQUIRED; fn in [strip(q[2]) for q in rows] || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); h == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1] ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
vn(n, b) = n == 0 ? "判定不能（分母 0）" : v(b)
frac(a, n) = n == 0 ? "0/0" : "$a/$n = $(round(a / n; digits = 3))"
cnt(xs) = sort(collect(Dict(a => count(==(a), xs) for a in unique(xs))); by = string)
M = [e for e in B if e["main_point"] && e["rest15"]]
println("branches $(length(E)) (excluded or dead at t+1: $(length(E) - length(B))), main set (t+L<=H, rest15) $(length(M)): ", cnt([e["outcome"] for e in M]))
# FK1: NM equals the actual branch after every update before m*'s first act (the whole branch if m* never acts)
nd = count(e -> e["diverged_before_first_act"] || e["eq_upto"] != e["eq_required"], M)
println("FK1 NM equal to the actual branch before m*'s first act: ", vn(length(M), nd == 0), " ($nd diverged)")
# FK2 H-fork: death if T_NM <= k_idle_due, release if T_NM > k_idle_due and k_idle_due <= L, otherwise lock (T_NM > L: censored)
pred(e) = e["dead_NM"] !== nothing && e["dead_NM"] <= e["k_idle_due"] ? "death" : e["k_idle_due"] <= L ? "release" : "lock"
mm = [e for e in M if pred(e) != e["outcome"]]
println("FK2 H-fork (T_NM vs k_idle_due) matches the outcome: ", vn(length(M), isempty(mm)), " ($(length(mm)) mismatches", isempty(mm) ? "" : ": " * join(["s$(e["seed"]) $(e["schedule"]) t$(e["t"]) pred $(pred(e)) got $(e["outcome"])" for e in mm[1:min(5, end)]], "; "), ")")
# FK3 H-Q: Q_t orders T_NM (censored T = L + 1; pairs with both censored left out; equal T not discordant)
T(e) = e["dead_NM"] === nothing ? L + 1 : e["dead_NM"]
np = 0; ndis = 0
for i in eachindex(M), j in eachindex(M)
    a, b = M[i], M[j]
    a["Q_t"] > b["Q_t"] || continue
    (T(a) == L + 1 && T(b) == L + 1) && continue
    global np += 1; T(a) < T(b) && (global ndis += 1)
end
println("FK3 Q_t orders T_NM, discordant pairs <= 10%: ", vn(np, ndis <= 0.1 * np), " ($(frac(ndis, np)))")
# FK4: the same (Q_t, k_idle_due) with different outcomes (exact equality of the stored values)
# codex I-R 1 #5: the denominator is the groups with two or more branches (a single branch cannot show different outcomes)
g = Dict{Any,Vector{String}}(); for e in M; push!(get!(g, (e["Q_t"], e["k_idle_due"]), String[]), e["outcome"]); end
g2 = [v for v in values(g) if length(v) >= 2]
nmix = count(v -> length(unique(v)) > 1, g2)
println("FK4 no (Q_t, k_idle_due) group with different outcomes: ", vn(length(g2), nmix == 0), " ($nmix of $(length(g2)) groups with >= 2 branches; $(length(g)) groups in all)")
println("  T_NM: ", cnt([e["dead_NM"] === nothing ? "censored > L" : "dead" for e in M]), "; NM at the due (win, act) ", cnt([e["NM_after_due"] === nothing ? nothing : (e["NM_after_due"]["win"], e["NM_after_due"]["act"]) for e in M]))
println("  deaths (dead_A, k_idle_due, Q_t, sites_t, minB_t) ", [(e["dead_A"], e["k_idle_due"], round(e["Q_t"]; digits = 3), e["sites_t"], round(e["minB_t"]; digits = 3)) for e in M if e["outcome"] == "death"])
println("  releases: T_NM - k_idle_due ", cnt([e["dead_NM"] === nothing ? "censored" : e["dead_NM"] - e["k_idle_due"] for e in M if e["outcome"] == "release"]))
println("  the other motor in NM (acts, answered, offered intake) ", cnt([(e["other_NM"]["acts"], e["other_NM"]["answered"]) for e in M]))
println("  A4 by combination (protocol survives, ours dead at H, ours window) ", [(x["seed"], x["schedule"], x["A4"]["protocol_survives"], x["A4"]["ours_dead_at_H"], x["A4"]["ours_window"]) for x in r["runs"]])
println("  A3 not verified (no eligible point): ", [(x["seed"], x["schedule"], x["n_snaps"]) for x in r["runs"] if x["n_eligible_A3"] == 0])
println("  regrowth after death (sites reappearing) main ", sum(x -> x["main_checks"]["regrowth"], r["runs"]), ", branches ", sum(e -> e["checks_A"]["regrowth"] + e["checks_NM"]["regrowth"], B))
println("  by seed (release, death, lock) ", [(s, count(e -> e["seed"] == s && e["outcome"] == "release", M), count(e -> e["seed"] == s && e["outcome"] == "death", M), count(e -> e["seed"] == s && e["outcome"] == "lock", M)) for s in SEEDS])
