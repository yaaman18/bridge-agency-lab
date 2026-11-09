# S44 checker (spec discussion/specs/S44-g1-school.md r3): gates, negative controls, the sha of the frozen files, GQ1-GQ5.
# Usage: julia --project=.. check_g1_school.jl   (smoke: PRED=smoke IN=results-g1-school-smoke.json)
using JSON, SHA
const DIR = @__DIR__
const PRED = get(ENV, "PRED", "main")
const IN = get(ENV, "IN", joinpath(DIR, PRED == "smoke" ? "results-g1-school-smoke.json" : "results-g1-school.json"))
const FREEZE = joinpath(DIR, PRED == "smoke" ? "freeze-g1-school-smoke.txt" : "freeze-g1-school.txt")
const L52 = [5.0, 2.0]; const L25 = [2.0, 5.0]
gates = Tuple{String,Bool}[]
gate(name, ok) = (push!(gates, (name, ok)); println("GATE ", ok ? "ok  " : "FAIL", " ", name))

# ---------------------------------------------------------------- pure functions under test (the same as in the spec §3)
"""M1 (spec §3): q vectors (r1, r2, r7, r8) into m1 and m2."""
function rtype(m1, m2)
    cross = m1[2] > m1[1] && m1[4] > m1[3] && m2[1] > m2[2] && m2[3] > m2[4]
    nocross = m1[1] > m1[2] && m1[3] > m1[4] && m2[2] > m2[1] && m2[4] > m2[3]
    cross && nocross && error("both types")
    cross ? "cross" : nocross ? "nocross" : "other"
end
"""pi check: a permutation of the original labels (14 of [5,2], 13 of [2,5], 27 in all)."""
perm_ok(p) = length(p) == 27 && count(==(L52), p) == 14 && count(==(L25), p) == 13
"""GQ3 on a table of rows (seed, tail, d per schedule): per tail group #(+1) > #(-1); an empty group -> undecided;
a missing schedule -> error (the gate drops it before the judgment)."""
function gq3(rows; nsched = 4)
    any(r -> length(r.d) != nsched, rows) && error("missing schedule")
    out = Dict{String,Any}()
    for g in ("52", "25")
        ds = reduce(vcat, [r.d for r in rows if r.tail == g]; init = Int[])
        out[g] = isempty(ds) ? nothing : (plus = count(==(1), ds), minus = count(==(-1), ds), zero = count(==(0), ds))
    end
    v = any(isnothing, values(out)) ? "判定不能" : all(x -> x.plus > x.minus, values(out)) ? "的中" : "外れ"
    (verdict = v, groups = out)
end

# ---------------------------------------------------------------- negative controls of the pure functions
G0std = ([0, 2, 0, 2], [4, 0, 4, 0]); G0swap = ([4, 0, 4, 0], [0, 2, 0, 2])
gate("M1 (d): the G0 examples cross / nocross, an equality -> other, mixed directions without equality -> other",
     rtype(G0std...) == "cross" && rtype(G0swap...) == "nocross" && rtype([0, 2, 0, 0], [4, 0, 4, 0]) == "other" &&
     rtype([0, 2, 1, 0], [4, 0, 4, 0]) == "other" && rtype([4, 0, 0, 2], [0, 2, 0, 2]) == "other")
mk(tail, d) = (tail = tail, d = d)
t_ok = gq3([mk("52", [1, 1, 0, 1]), mk("25", [1, 0, 1, -1])]).verdict == "的中"
t_zero = gq3([mk("52", [0, 0, 0, 0]), mk("25", [0, 0, 0, 0])]).verdict == "外れ"
t_empty = gq3([mk("52", [1, 1, 1, 1])]).verdict == "判定不能"
t_tie = gq3([mk("52", [1, -1, 0, 0]), mk("25", [1, 1, 1, 1])]).verdict == "外れ"
t_miss = try gq3([mk("52", [1, 1, 1])]); false catch; true end
gate("GQ3 (c): +1 majority -> 的中, all 0 -> 外れ, one group empty -> 判定不能, tie -> 外れ, a missing schedule -> dropped",
     t_ok && t_zero && t_empty && t_tie && t_miss)

# ---------------------------------------------------------------- the sha of the frozen files
for l in readlines(FREEZE)
    (startswith(l, "#") || isempty(strip(l))) && continue
    h, f = split(l; limit = 2); f = strip(f)
    gate("freeze sha $(f)", bytes2hex(sha256(read(joinpath(DIR, f)))) == h)
end

# ---------------------------------------------------------------- gates on the results
R = JSON.parsefile(IN); runs = R["runs"]; seeds = [r["seed"] for r in runs]
gate("identity: pi = nothing gives the shared curriculum and org (both arms)", all(values(R["gate_identity"])))
gate("pi check on every seed", all(r -> perm_ok(r["perm"]), runs))
gate("pi check (b) negative: one label changed fails", !perm_ok(vcat(runs[1]["perm"][1:26], [L52 == runs[1]["perm"][27] ? L25 : L52])))
same_pi(r) = r["arms"]["std"]["perm_used"] == r["perm"] && r["arms"]["swap"]["perm_used"] == r["perm"]
gate("the same pi for both arms of every seed", all(same_pi, runs))
bad = deepcopy(runs[1]); bad["arms"]["swap"]["perm_used"] = reverse(bad["perm"])
gate("same-pi (a) negative: a different pi on one arm fails", !same_pi(bad) || bad["perm"] == reverse(bad["perm"]))
gate("tail recorded as the 27th label", all(r -> r["tail"] == (r["perm"][27] == L52 ? "52" : "25"), runs))
scheds = sort(collect(keys(runs[1]["arms"]["std"]["trials"])))
gate("4 schedules on every arm and seed", length(scheds) == 4 && all(r -> all(a -> sort(collect(keys(r["arms"][a]["trials"]))) == scheds, ("std", "swap")), runs))
gate("M1 recomputed from the recorded q", all(r -> all(a -> rtype(r["arms"][a]["q_m1"], r["arms"][a]["q_m2"]) == r["arms"][a]["type"], ("std", "swap")), runs))
allg = all(last, gates)

# ---------------------------------------------------------------- the predictions (spec §4; smoke and main use the same rules)
n = length(runs); frac(k, m) = m == 0 ? nothing : k / m
v(ok) = ok === nothing ? "判定不能" : ok ? "的中" : "外れ"
ty(a) = [r["arms"][a]["type"] for r in runs]
k1s = count(==("cross"), ty("std")); k1w = count(==("nocross"), ty("swap"))
println("GQ1 types: std cross $k1s/$n, swap nocross $k1w/$n: ", v(k1s >= 0.9n && k1w >= 0.9n),
        "  (std $(Dict(t => count(==(t), ty("std")) for t in unique(ty("std")))), swap $(Dict(t => count(==(t), ty("swap")) for t in unique(ty("swap")))))")
alive(a) = [r["arms"][a]["trials"][s]["alive"] for r in runs for s in scheds]
k2w = count(alive("swap")); k2s = count(!, alive("std")); m2 = 4n
println("GQ2 survival: swap alive $k2w/$m2, std dead $k2s/$m2: ", v(k2w >= 0.9m2 && k2s >= 0.9m2))
rows = [(seed = r["seed"], tail = r["tail"], d = [Int(r["arms"]["swap"]["trials"][s]["alive"]) - Int(r["arms"]["std"]["trials"][s]["alive"]) for s in scheds]) for r in runs]
g3 = gq3(rows)
println("GQ3 paired sign by tail: ", g3.verdict, "  ", g3.groups)
println("   D_s: ", [(x.seed, x.tail, sum(x.d) / 4) for x in rows])
for g in ("52", "25"); ds = [sum(x.d) / 4 for x in rows if x.tail == g]; println("   group $g: n=$(length(ds)) mean D_s=", isempty(ds) ? "-" : round(sum(ds) / length(ds); digits = 3)); end
sqw(a, m) = count(r -> (q = r["arms"][a]["sq1"]; q[m] > q[m == "m1" ? "m2" : "m1"]), runs)
k4s = sqw("std", "m2"); k4w = sqw("swap", "m1")
println("GQ4 SQ1: std m2 $k4s/$n, swap m1 $k4w/$n: ", v(k4s >= 0.9n && k4w >= 0.9n), "  ", [(r["seed"], r["arms"]["std"]["sq1"], r["arms"]["swap"]["sq1"]) for r in runs])
nr(a) = length(unique(r["arms"][a]["raise"] for r in runs))
println("GQ5 diversity of the raised circuit: std $(nr("std")), swap $(nr("swap")) (of $n): ", n < 3 ? "判定不能" : v(nr("std") >= 3 && nr("swap") >= 3))
# GQ6 (main only, added after the smoke, codex 2026-11-09 #3): seeds with M1 = other on both arms, >= 15 of the fixed seeds
k6 = count(r -> r["arms"]["std"]["type"] == "other" && r["arms"]["swap"]["type"] == "other", runs)
println("GQ6 both arms other: $k6/$n: ", PRED == "smoke" ? "（煙では問わない）" : v(k6 >= 15))
# described (codex #5): the longest run of equal labels over the 27 labels of pi_s; the number of the 8 edges r1,r2,r7,r8 -> m1,m2
# with q = 0 per arm; per seed (not 60 independent cases), and the mean per arm over the seeds in each run-length bin
longest(p) = (m = 1; c = 1; for i in 2:length(p); c = p[i] == p[i-1] ? c + 1 : 1; m = max(m, c); end; m)
nz(r, a) = count(==(0), vcat(r["arms"][a]["q_m1"], r["arms"][a]["q_m2"]))
println("described run/q0 per seed (seed, longest run, q0 std, q0 swap): ", [(r["seed"], longest(r["perm"]), nz(r, "std"), nz(r, "swap")) for r in runs])
for (lo, hi) in ((1, 2), (3, 3), (4, 27))
    rs = [r for r in runs if lo <= longest(r["perm"]) <= hi]
    println("   longest run $lo-$hi: seeds $(length(rs)), mean q0 std ", isempty(rs) ? "判定不能" : round(sum(nz(r, "std") for r in rs) / length(rs); digits = 2),
            " swap ", isempty(rs) ? "判定不能" : round(sum(nz(r, "swap") for r in rs) / length(rs); digits = 2))
end
# descriptions
ntr(a) = length(unique((s, r["arms"][a]["trials"][s]["traj"]) for r in runs for s in scheds))
println("described: trajectories without r5 std $(ntr("std"))/$m2 swap $(ntr("swap"))/$m2; types std $(length(unique(ty("std")))) swap $(length(unique(ty("swap")))); ",
        "pi $(length(unique(r["perm"] for r in runs)))/$n; tail 52 $(count(r -> r["tail"] == "52", runs)) 25 $(count(r -> r["tail"] == "25", runs)); ",
        "pairs with the contrast (std cross & swap nocross) $(count(r -> r["arms"]["std"]["type"] == "cross" && r["arms"]["swap"]["type"] == "nocross", runs))/$n")
println("all gates: ", allg ? "ok" : "FAIL")
allg || exit(1)
