# S28 evaluation of predictions-yoke12.md (C0, YP1-YP3) from results-yoke12.json.
using JSON, Statistics
d = JSON.parsefile(joinpath(@__DIR__, get(ENV, "IN", "results-yoke12.json"))); P = d["points"]
ex = Dict(r => count(x -> get(x, "excluded", "") == r, P) for r in unique([get(x, "excluded", "") for x in P]))
println("points $(length(P)); point exclusions ", ex, "; C0 ", all(x -> get(x, "C0", true), P))
for c in ("Y1", "Y2")
    has = [x for x in P if haskey(x, c)]
    exc = count(x -> haskey(x[c], "excluded"), has)
    u = [x for x in has if !haskey(x[c], "excluded") && !x[c]["deadW"]]
    dw = count(x -> !haskey(x[c], "excluded") && x[c]["deadW"], has)
    isempty(u) && (println("$c not evaluable"); continue)
    d1 = count(x -> x[c]["div"] > 0, u) / length(u)
    sm = count(x -> x[c]["bodyW"] < x["N"]["bodyW"], u); eq = count(x -> x[c]["bodyW"] == x["N"]["bodyW"], u)
    sv = count(x -> x[c]["aliveH"], u) / length(u)
    println("$c: usable $(length(u)) (excluded $exc, died in W $dw) | YP1 div>0 $(round(d1; digits = 3)) $(d1 >= 0.5 ? "hit" : "miss") | ",
            "YP2 body smaller than N $sm/$(length(u)) (equal $eq, larger $(length(u) - sm - eq)) $(c == "Y1" ? (sm > length(u) / 2 ? "hit" : "miss") : "(no prediction)") | YP3 alive at t+H $(round(sv; digits = 3)) $(sv >= 0.9 ? "hit" : "miss") | median div $(median([x[c]["div"] for x in u])) | N alive at t+H among them $(count(x -> x["N"]["aliveH"], u))")
    for arm in ("std", "swap"), sch in unique([x["schedule"] for x in u])
        v = [x for x in u if x["arm"] == arm && x["schedule"] == sch]
        isempty(v) || println("   $arm $(rpad(sch, 11)) n $(length(v)) div>0 $(count(x -> x[c]["div"] > 0, v)) body< $(count(x -> x[c]["bodyW"] < x["N"]["bodyW"], v)) alive $(count(x -> x[c]["aliveH"], v))")
    end
end
