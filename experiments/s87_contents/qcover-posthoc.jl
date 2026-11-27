# post-hoc description (not a prediction): is the flipped example's key present in Q, per group?
include(joinpath(ENV["HOME"], "bridge-agency-lab", "experiments", "s87_contents", "contents.jl"))
using Statistics
LV = lives83()
acc = Dict(g => (inQ = 0, n = 0, mult = Int[], actshare = Float64[], segnew = 0) for g in GR87)
nkQ = Int[]
for x in LV
    F = field87(x); qk = qkeys(F); cnt = Dict{Int,Int}(); for k in qk; cnt[k] = get(cnt, k, 0) + 1; end
    push!(nkQ, length(cnt))
    O = origins84(x)
    for g in GR87, t0 in O[(g, 200)]
        s = t0 + 1; s <= F.N || continue
        k = F.K[s]; m = get(cnt, k, 0)
        a = acc[g]; acc[g] = (inQ = a.inQ + (m > 0), n = a.n + 1, mult = push!(a.mult, m), actshare = a.actshare, segnew = a.segnew)
    end
end
println("distinct keys in Q per life: median ", median(nkQ), " of NK=", NK)
for g in GR87; a = acc[g]
    println("h=200 group $g: origins $(a.n), flipped key in Q $(a.inQ) ($(round(a.inQ/a.n, digits=3))), Q multiplicity q1/med/q3 ", quantile(a.mult, [0.25, 0.5, 0.75]))
end
