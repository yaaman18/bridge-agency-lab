# S38 check (spec discussion/specs/S38-rb-tiesource.md r1): gates first (no verdicts if one fails), then TR1-TR4 and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rb-tiesource.json")))
SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(451:460, ",")), ",")))   # SEEDS only for the smoke test
TIES = ["1,1", "2,2", "3,3", "4,4", "5,5"]; IVS = ["J0", "J3", "J4", "J5", "J6", "J12", "J56", "J125", "J126", "J1256"]; RBC = ["normal", "rb_false"]
ok = true; fail(m) = (println("GATE FAIL ", m); global ok = false)
r["rule"] == "rb" || fail("rule"); r["H"] == 392 || fail("H"); r["seeds"] == SEEDS || fail("seeds"); r["window"] == collect(5:15) || fail("window")
sort([x["seed"] for x in r["runs"]]) == sort(SEEDS) && allunique([x["seed"] for x in r["runs"]]) || fail("seed rows")
for x in r["runs"], a in ("std", "swap")
    x["repeat_equal_$a"] === true || fail("repeat $(x["seed"]) $a")
    (sort(collect(keys(x[a]))) == sort(RBC) && all(c -> sort(collect(keys(x[a][c]))) == sort(IVS) && all(iv -> sort(collect(keys(x[a][c][iv]))) == sort(TIES), IVS), RBC)) || fail("cells $(x["seed"]) $a")
    all(c -> all(iv -> all(p -> x[a][c][iv][p]["n"] == 11 && x[a][c][iv][p]["act_m0"] + x[a][c][iv][p]["act_patch"] + x[a][c][iv][p]["act_none"] == 11, TIES), IVS), RBC) || fail("denominator $(x["seed"]) $a")
end
if get(ENV, "SKIPFREEZE", "0") != "1"
    REQUIRED = ["predictions-rb-tiesource.md", "../discussion/specs/S38-rb-tiesource.md", "tiesource_rb.jl", "check_rb_tiesource.jl", "variant_horizon.jl", "../core/circuit.jl"]
    ff = joinpath(LAB, "experiments", "freeze-rb-tiesource.txt"); isfile(ff) || fail("no freeze file")
    rows = isfile(ff) ? [split(l; limit = 2) for l in readlines(ff) if !startswith(l, "#") && !isempty(strip(l))] : []
    for fn in REQUIRED; fn in [strip(q[2]) for q in rows] || fail("freeze file lacks $fn"); end
    for (h, fn) in rows
        fn = strip(fn); h == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", fn))`, String))[1] ? println("GATE freeze sha ok  $fn") : fail("freeze sha $fn")
    end
end
get(ENV, "NEGTEST", "0") == "1" && fail("NEGTEST")
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
cells(f) = [(x, a) for x in r["runs"] for a in ("std", "swap")]
tr1 = all(((x, a),) -> all(c -> all(iv -> all(p -> x[a][c][iv][p]["acts"] == x[a][c]["J0"][p]["acts"], TIES), ("J3", "J4")), RBC), cells(0))
# codex I-R #6: TR2 is both halves, no patch act and m0 the winner at every window step
tr2 = all(((x, a),) -> all(p -> x[a]["normal"]["J0"][p]["act_patch"] == 0 && x[a]["normal"]["J0"][p]["act_m0"] == 11, TIES), cells(0))
tr2a = all(((x, a),) -> all(p -> x[a]["normal"]["J0"][p]["act_patch"] == 0, TIES), cells(0))
tr3 = all(((x, a),) -> all(c -> all(p -> x[a][c]["J1256"][p]["act_patch"] == 0, TIES), RBC), cells(0))
tr4 = all(((x, a),) -> all(p -> x[a]["rb_false"]["J56"][p]["act_patch"] == (p in ("3,3", "4,4", "5,5") ? 11 : 0), TIES), cells(0))
println("TR1 J3, J4 = J0: ", v(tr1)); println("TR2 normal J0 no patch act and m0 at every step: ", v(tr2), " (no patch act alone: $tr2a)"); println("TR3 J1256 no patch act: ", v(tr3)); println("TR4 rb_false J56 patch at k>=3 only: ", v(tr4))
for a in ("std", "swap"), c in RBC, iv in IVS
    xs = [x[a][c][iv][p] for x in r["runs"] for p in TIES]
    byp = join(["$p:" * string(sum(x[a][c][iv][p]["act_patch"] for x in r["runs"])) for p in TIES], " ")
    println("  $(rpad(a, 4)) $(rpad(c, 8)) $(rpad(iv, 5)) acts m0 $(sum(z -> z["act_m0"], xs)) patch $(sum(z -> z["act_patch"], xs)) none $(sum(z -> z["act_none"], xs))  patch by probe [$byp]  rb on $(sum(z -> z["rb_on"], xs))")
end
