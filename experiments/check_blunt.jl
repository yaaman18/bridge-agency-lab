# S31: reads results-blunt-sf.json and results-blunt-sfd.json, computes the per-type statistics of spec §2 and the
# predictions BP1-BP4 of predictions-blunt.md, and the controls C0-C2. Writes nothing; prints and exits 1 if a control fails.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
ld(c) = JSON.parsefile(joinpath(get(ENV, "RDIR", joinpath(LAB, "experiments")), "results-blunt-$c.json"))
lat(x) = x == "Inf" ? Inf : Float64(x)
lowmed(v) = isempty(v) ? NaN : sort(v)[cld(length(v), 2)]

function stats(r)
    out = Dict{String,Any}()
    for ty in ("q", "sg")
        pts = [(run["seed"], run["arm"], run["schedule"], e) for run in r["runs"] for e in run["events"] if e["type"] == ty]
        dead = count(x -> x[4]["why"] != "", pts)
        use = [x for x in pts if x[4]["why"] == ""]
        L = [lat(x[4]["latency"]) for x in use]
        out[ty] = Dict("n" => length(use), "excluded_dead" => dead, "runs" => length(unique((x[1], x[2], x[3]) for x in use)),
                       "seeds" => length(unique(x[1] for x in use)), "s" => isempty(use) ? NaN : count(isfinite, L) / length(use),
                       "med" => lowmed(L), "medN" => lowmed([lat(x[4]["latN"]) for x in use]),
                       "d_same" => count(x -> !x[4]["answer_d_differs"], use))
    end
    q, g = out["q"], out["sg"]
    und = q["n"] < 5 || g["n"] < 5 || (q["s"] == 0 && g["s"] == 0) || (isinf(q["med"]) && isinf(g["med"]))
    out["verdict"] = und ? "undetermined" : g["med"] < q["med"] ? "sg<q" : g["med"] == q["med"] ? "sg=q" : "sg>q"
    out
end

sf, sfd = ld("sf"), ld("sfd")
# gates first (codex I-R 3): no verdict is printed when a gate fails
ok = true
for (nm, r) in (("SF", sf), ("SFD", sfd))
    c = r["controls"]; println(nm, " controls ", c, " gseed ", r["gseed"], " seeds ", first(r["seeds"]), "..", last(r["seeds"]))
    global ok &= c["C0_replay_all"] && c["C0_negative_some_V_differs"] && c["C1_repeat"]
end
c2 = isequal(sfd["C2_off_run"], sf["C1_run"]); println("C2 SFD off equals SF: ", c2); ok &= c2
get(ENV, "NEGTEST", "0") == "1" && (ok = false)   # the negative test of this check: a failed gate must stop the verdicts
ok || (println("CONTROL FAILED: no verdicts"); exit(1))
A, B = stats(sf), stats(sfd)
for (nm, X) in (("SF", A), ("SFD", B))
    println(nm, " verdict ", X["verdict"])
    for ty in ("q", "sg"); println("  ", ty, " ", X[ty]); end
end
ev(v) = v == "undetermined" ? "未判定" : v in ("sg<q", "sg=q") ? "的中" : "外れ"
println("BP1 (SF  med_sg <= med_q): ", ev(A["verdict"]))
println("BP2 (SFD med_sg <= med_q): ", ev(B["verdict"]))
println("BP3 (n_sg SFD > SF): ", B["sg"]["n"] > A["sg"]["n"] ? "的中" : "外れ", " (", B["sg"]["n"], " vs ", A["sg"]["n"], ")")
println("BP4 (SF n_sg < 5): ", A["sg"]["n"] < 5 ? "的中" : "外れ", " (", A["sg"]["n"], ")")
