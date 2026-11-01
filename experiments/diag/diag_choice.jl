# Diagnosis (read-only, no rule changed) of item 70's L2 failure: why body_org's raised circuit picks m2 in both
# frozen choice schedules, and why the app's being is biased to m1. Usage: julia --project=. experiments/diag/diag_choice.jl
include(joinpath(@__DIR__, "..", "..", "core", "LabCore.jl"))
using .LabCore, JSON; const LC = LabCore
fname(b, u) = b.kind[u] == 'R' ? b.names[u] * "(" * LC.FEATURES[b.perm[b.feat[u]]][1] * ")" : b.names[u]
function edges_into(b, st, m)
    [(fname(b, a), st.q[k], st.sg[k]) for (k, (a, c, _)) in enumerate(b.edges) if c == m && (st.q[k] > 0 || st.sg[k] > 0)]
end
"""Recompute step!'s choice inputs (conf, habit, total) for the motors before calling it (same formulas, read-only)."""
function why(b, st, y; contrast)
    n = length(b.names); old = st.active; ys = Float64[y[1], y[2], 0, isempty(st.pend) ? 0 : 1]
    prev = st.prev === nothing ? old : st.prev
    onset = [b.kind[u] == 'R' && old[u] && !prev[u] for u in 1:n]
    idle(u) = contrast in (:learn3, :bin3, :donly) && b.kind[u] == 'M' && b.patch[u] <= 2 && st.lastM !== nothing && st.t + 1 - st.lastM[u] > LC.FORGET
    stale = [b.kind[u] != 'R' && !isempty(b.ins[u]) && (idle(u) || all(k -> st.q[k] == 0 && st.sg[k] == 0, b.ins[u])) for u in 1:n]
    tot = zeros(Int, n); conf = zeros(Int, n); hab = zeros(Int, n); src = [String[] for _ in 1:n]
    for (k, (a, c, w)) in enumerate(b.edges)
        if (st.q[k] >= 1 || st.sg[k] >= 1 || stale[c] || (onset[a] && st.q[k] == 0 && st.sg[k] == 0 && st.h[k] == 0)) && old[a]
            tot[c] += w; st.q[k] >= 1 ? (conf[c] += w) : st.sg[k] >= 1 ? (hab[c] += w) : nothing
            b.kind[c] == 'M' && push!(src[c], b.names[a] * (st.q[k] >= 1 ? "q" : st.sg[k] >= 1 ? "s" : stale[c] ? "~" : "o"))
        end
    end
    Dict(b.names[m] => (conf = conf[m], habit = hab[m], total = tot[m], from = join(src[m], " "), was_on = old[m])
         for m in 1:n if b.kind[m] == 'M' && b.patch[m] <= 2)
end

println("== A. body_org's raised circuit (B1 of item 70, seed 1) in the frozen choice schedules")
b = LC.newborn(false); c0 = LC.init(b); nz0 = LC.Mulberry(1)
answered_poor = [0, 0]   # during raising: acts on the poorer patch (both positive), answered / all
for y in LC.BO_CUR
    o = LC.step!(c0, b, [y[1], y[2], 0.0]; noise = nz0, contrast = nothing)
    if y[1] > 0 && y[2] > 0 && y[1] != y[2]
        poor = y[1] < y[2] ? 1 : 2
        for m in o.acting
            b.patch[m] == poor && (answered_poor[2] += 1; o.answered[m] && (answered_poor[1] += 1))
        end
    end
end
println("raising (school, both patches positive): acts on the poorer patch answered ", answered_poor[1], "/", answered_poor[2])
for m in ("m1", "m2"); println("edges into $m after raising (name, q, sediment): ", edges_into(b, c0, LC.unit(b, m))); end
println("last motor on at the end of raising: ", [b.names[u] for u in eachindex(b.names) if b.kind[u] == 'M' && c0.active[u]])
for (name, y) in (("c1-better", [5.0, 4.0]), ("c2-better", [4.0, 5.0]))
    c = deepcopy(c0); nz = deepcopy(nz0); println("-- $name y = $y")
    for t in 1:16
        w = why(b, c, y; contrast = nothing)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = nothing)
        on = [fname(b, u) for u in eachindex(b.names) if b.kind[u] == 'R' && c.active[u]]
        (t <= 3 || t in (5, 10, 15)) && println("  t=$t acting=", [b.names[m] for m in o.acting], " m1=", w["m1"], " m2=", w["m2"], (t == 1 ? "  receptors on: $(join(on, " "))" : ""))
    end
end

println("\n== B. the app's being (db v528) in the world phase, steps where both patches yield")
saved = JSON.parse(read(joinpath(@__DIR__, "..", "..", "audit", "in", "state-v528.json"), String); dicttype = Dict{String,Any})
l = LC.makelife(saved; rule = "bin3"); bb = l.b
for m in ("m1", "m2"); println("edges into $m (name, q, sediment): ", edges_into(bb, l.st, LC.unit(bb, m))); end
stats = Dict{String,Int}(); reasons = Dict{String,Int}(); poor_ans = [0, 0]
live!(l, 2000; on_step = (o, st, cond, y, ph) -> begin
    (ph == "world" && y[1] > 0 && y[2] > 0) || return
    k = join(sort([bb.names[m] for m in o.acting if bb.patch[m] <= 2]), "+"); k = isempty(k) ? "none" : k
    rel = y[1] > y[2] ? "y1>y2" : y[1] < y[2] ? "y1<y2" : "y1=y2"; stats["$rel -> $k"] = get(stats, "$rel -> $k", 0) + 1
    if y[1] != y[2]
        poor = y[1] < y[2] ? 1 : 2
        for m in o.acting; bb.patch[m] == poor && (poor_ans[2] += 1; o.answered[m] && (poor_ans[1] += 1)); end
    end
end)
println("both patches yield (2000 steps): ", sort(collect(stats)))
println("acts on the poorer patch answered ", poor_ans[1], "/", poor_ans[2])

println("\n== C. the same window (steps 5-15) with one patch empty: [5,0] and [0,5] (diagnostic only, not AGENCY-001's schedules)")
function window_choice(b, c0, nz0, y; contrast)
    c = deepcopy(c0); nz = deepcopy(nz0); seen = Set{String}()
    for t in 1:16
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = contrast)
        t >= 5 && t <= 15 && foreach(m -> b.patch[m] <= 2 && push!(seen, b.names[m]), o.acting)
    end
    sort(collect(seen))
end
for y in ([5.0, 4.0], [4.0, 5.0], [5.0, 0.0], [0.0, 5.0])
    println("body_org raised circuit y=$y: ", window_choice(b, c0, nz0, y; contrast = nothing),
            "   app being v528 (rule bin3) y=$y: ", window_choice(LC.makelife(deepcopy(saved); rule = "bin3").b, LC.makelife(deepcopy(saved); rule = "bin3").st, LC.Mulberry(1), y; contrast = :bin3))
end
