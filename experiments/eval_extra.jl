# Item 78 B (user 2026-11-02 "おすすめで実装していって"): more kinds of patch receptors (core/circuit.jl EXTRA_FEATURES:
# y1>=1, y2>=1, y1>=4, y2>=4, y1>=y2+2, y2>=y1+2, as r9-r14 of body_org's circuit), L2's rule (bin3 + idle_first + core
# gate). The raising: the confident receptor inputs of each motor at the end. The AGENCY-001 runs: variant_horizon.jl
# EXTRA=1 (results-horizon-extra.json); the worlds: eval_worldvar.jl EXTRA=1. Predictions: predictions-extra.md.
# Usage: julia --project=. experiments/eval_extra.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
fname(b, u) = b.names[u] * "(" * LC.FEATURES[b.perm[b.feat[u]]][1] * ")"
res = Dict{String,Any}()
for extra in (false, true), seed in 1:10
    b = LC.newborn(false; extra = extra ? collect(LC.EXTRA_FEATURES) : Int[]); c = LC.init(b); nz = LC.Mulberry(seed)
    for y in LC.BO_CUR; LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = :bin3, idle_first = true, core_gate = true); end
    conf(m) = [fname(b, a) for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    r = Dict("conf_m1" => conf("m1"), "conf_m2" => conf("m2"))
    res["$(extra ? "extra" : "base") seed$seed"] = r
    println(extra ? "extra" : "base ", " seed $seed  m1 <- ", join(r["conf_m1"], " "), "   m2 <- ", join(r["conf_m2"], " "))
end
write(joinpath(@__DIR__, "results-extra.json"), JSON.json(res, 2))
