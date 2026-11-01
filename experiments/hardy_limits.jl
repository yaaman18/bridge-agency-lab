# Post hoc (not pre-registered), 2026-10-29: does the hardier agent remain precarious? Longest famine
# survived, and behaviour in the unperturbed world, at rmax 100 and 200 (variant_hardy.jl).
using AgencySubstrate
const AS = AgencySubstrate
ENV["WORLD_VARIANT"] = "variant_hardy.jl"
include(joinpath(@__DIR__, "fragility.jl"))
withr(P, r) = AS.Params(P.smax, P.decay_period, P.grow_cost, P.resource0, r, P.horizon, P.alive_window, P.strength0)
s = only(t for t in load_templates(joinpath(@__DIR__, "designs.toml")).templates if t.name == "selfloop-pair-agent").substrate
for r in (30, 100, 200)
    p = withr(load_templates().params, r)
    lim = [maximum([k for k in 1:300 if first(run_world(s, p, 1000; famine=t -> t0 <= t < t0 + k))]; init=0) for t0 in (150, 450, 750)]
    println("rmax $r: longest famine survived from t0=150/450/750: ", lim)
end
