# Item 83 (report without prediction, read only): what the kept contingencies of item 83's run A are, 200 steps before
# death (seed 4 survives: step 5000). Usage: julia --project=.. diag_upkeep_kept.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore
const LC = LabCore
o0 = (U = 0.02, MCOST = 0.004, STEPS = 10000, FEED = true, SCHED = "random", RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true, KC = 0.002)
deaths = Dict(1=>4525, 2=>3272, 3=>6741, 4=>5200, 5=>4589, 6=>4223, 7=>1852, 8=>3251, 9=>1513, 10=>8821)
fn(b, u) = b.kind[u] == 'R' ? b.names[u] * "(" * LC.FEATURES[b.perm[b.feat[u]]][1] * ")" : b.names[u]
tally = Dict{String,Int}()
for seed in 1:10
    o = merge(o0, (PHASE = (seed - 1) * 100, SCHEDSEED = seed)); tt = deaths[seed] - 200
    snap = Ref{Any}(nothing); fired = Dict{Int,Int}()
    obs(x) = begin
        if tt - 300 <= x.t < tt && x.alive; for u in eachindex(x.circuit.active); x.circuit.active[u] && (fired[u] = get(fired, u, 0) + 1); end; end
        x.t == tt && (snap[] = deepcopy((b = x.b, c = x.circuit)))
    end
    LC.body_org_run("ORG", seed, merge(o, (ON_STEP = obs,)))
    b = snap[].b; c = snap[].c
    ks = [k for k in eachindex(c.q) if c.q[k] >= 1 || c.sg[k] >= 1]
    parts = String[]
    for k in ks
        a, m, _ = b.edges[k]
        cls = b.q0[k] >= 1 ? "innate" : b.kind[a] == 'R' ? (c.q[k] >= 1 ? "R->$(b.kind[m]) conf" : "R->$(b.kind[m]) sed") : "$(b.kind[a])->$(b.kind[m]) " * (c.q[k] >= 1 ? "conf" : "sed")
        tally[cls] = get(tally, cls, 0) + 1
        push!(parts, "$(fn(b,a))->$(fn(b,m)) q$(c.q[k]) s$(c.sg[k]) on$(get(fired, a, 0))")
    end
    println("seed $(lpad(seed,2)) t=$tt kept $(length(ks)): ", join(parts, ", "))
end
println("\ntally over seeds: ", sort(collect(tally); by = x -> -x[2]))
