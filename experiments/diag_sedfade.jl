# Item 84 (reported without prediction, read only). (1) The confident receptor inputs at step 800 of the raising with the
# body, with and without sed_fade (as eval_readcur.jl). (2) The load the random world allows: GREEDY charged L per step
# (KC = L / 4), seeds 1-10. Usage: julia --project=.. diag_sedfade.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore
const LC = LabCore
fn(b, u) = b.names[u] * "(" * LC.FEATURES[b.perm[b.feat[u]]][1] * ")"
for sf in (false, true), seed in 1:10
    o = (U = 0.02, MCOST = 0.004, STEPS = 800, FEED = true, RAISE = "body", KC = 0.002, CONTRAST = "bin3", IDLE = true, GATE = true, SEDFADE = sf)
    snap = Ref{Any}(nothing)
    LC.body_org_run("ORG", seed, merge(o, (ON_STEP = x -> x.t == 799 && (snap[] = deepcopy((b = x.b, c = x.circuit))),)))
    b = snap[].b; c = snap[].c
    conf(m) = [fn(b, a) for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    sed(m) = [fn(b, a) for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] == 0 && c.sg[k] >= 1]
    println(sf ? "fade " : "plain", " seed ", lpad(seed, 2), "  m1 <- ", join(conf("m1"), " "), " | sed ", join(sed("m1"), " "), "   m2 <- ", join(conf("m2"), " "), " | sed ", join(sed("m2"), " "))
end
println()
for L in (0.008, 0.010, 0.012, 0.014, 0.016, 0.0186, 0.026)
    alive = 0; ds = Int[]
    for seed in 1:10
        r = LC.body_org_run("GREEDY", seed, (U = 0.02, MCOST = 0.004, STEPS = 10000, FEED = true, SCHED = "random", SCHEDSEED = seed, PHASE = (seed - 1) * 100, KC = L / 4))
        r["death"] === nothing ? (alive += 1) : push!(ds, r["death"])
    end
    println("GREEDY load $L/step: survived $alive/10  deaths $ds")
end
