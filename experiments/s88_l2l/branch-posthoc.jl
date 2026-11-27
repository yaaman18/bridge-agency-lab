# post-hoc description (codex S88 reading P2): contribution of each keeping branch to E1's paired difference. Not a prediction; frozen l2l.jl unchanged.
include(joinpath(@__DIR__, "l2l.jl"))
res = tmapv(life88, lives83())
tg = [w for r in res for w in r.rows if w.ps != 0.5 && haskey(w.out, 1000) && any(g -> w.t0 in r.O[(g, 1000)], GR88)]
d(w) = w.out[1000].DL - w.out[1000].DF
for (nm, f) in (("main keeps s", w -> w.keepM), ("twin keeps s", w -> w.keepT))
    v = filter(f, tg); println("$nm: n $(length(v)) sum $(round(sum(d, v; init = 0.0), sigdigits = 5)) mean $(round(isempty(v) ? NaN : sum(d, v) / length(v), sigdigits = 4))")
end
println("total: n $(length(tg)) sum $(round(sum(d, tg), sigdigits = 5))")
