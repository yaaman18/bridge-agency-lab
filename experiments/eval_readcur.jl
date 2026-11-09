# Item 82 (user 2026-11-02 "推奨どおり1から進めて"): the control for item 81's inference 1. body_org raised with the body
# (FEED, RAISE body, KC 0.002, L2's rule), but while raised (steps 0-799) the circuit reads the scripted yields that feed the
# pools (core/body_org.jl READCUR) instead of the pools it depletes; the harvest still comes from the pools. The confident
# receptor inputs at step 800, with and without READCUR. Predictions: predictions-readcur.md. Usage: julia --project=. experiments/eval_readcur.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
fn(b, u) = b.names[u] * "(" * LC.FEATURES[b.perm[b.feat[u]]][1] * ")"
res = Dict{String,Any}()
for rc in (false, true), seed in 1:10
    o = (U = 0.02, MCOST = 0.004, STEPS = 800, FEED = true, RAISE = "body", KC = 0.002, CONTRAST = "bin3", IDLE = true, GATE = true, READCUR = rc)
    snap = Ref{Any}(nothing)
    LC.body_org_run("ORG", seed, merge(o, (ON_STEP = x -> x.t == 799 && (snap[] = deepcopy((b = x.b, c = x.circuit, nb = count(!=(0), x.w.C)))),)))
    S = snap[]; b = S.b; c = S.c
    conf(m) = [fn(b, a) for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    r = Dict("conf_m1" => conf("m1"), "conf_m2" => conf("m2"), "body" => S.nb); res["$(rc ? "readcur" : "pools") seed$seed"] = r
    println(rc ? "readcur" : "pools  ", " seed ", lpad(seed, 2), " body ", S.nb, "  m1 <- ", join(r["conf_m1"], " "), "   m2 <- ", join(r["conf_m2"], " "))
end
write(joinpath(@__DIR__, "results-readcur.json"), JSON.json(res, 2))
