# Item 72 (user 2026-11-01 "推奨どおりでいい、固定化を解く規則変更から進めて"): the idle-first choice (core/circuit.jl
# step!(...; idle_first = true), formal/LabCircuit.lean IdleFirst) against the old rule. Predictions:
# experiments/predictions-idle.md (freeze-idle.txt). The horizon variant with the new rule is a separate run:
# IDLE=1 HORIZONS=60,294,392,588 OUT=experiments/results-horizon-idle.json julia --project=. experiments/variant_horizon.jl
# Usage: julia --project=. experiments/eval_idle.jl   (writes results-idle.json and formal/gen/IdleChoices.lean, and
# compares Lean's IdleFirst.pick with the Julia choices; needs formal/.olean/LabCircuit.olean, sh audit/dc_lean.sh)
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, ".."))
parsej(s) = JSON.parse(s; dicttype = Dict{String,Any})
choices = []   # two-candidate choices made with idle_first, for Lean

"""The app's being for `steps` steps from L0 (no partner), with or without the idle-first choice: DC windows (state
alpha, item 69) and what the motors did while both patches yield."""
function app_run(L0, steps; idle)
    l = makelife(L0; rule = idle ? "bin3+idle" : "bin3"); b = l.b; m1 = LC.unit(b, "m1"); m2 = LC.unit(b, "m2")
    rm2 = [k for (k, (a, c, _)) in enumerate(b.edges) if c == m2 && b.kind[a] == 'R']
    recs = LC.DCStep[]; both = Dict{String,Int}(); ever_r2m2 = 0; forced = 0; m2_free_poorer1 = 0
    r2 = findfirst(u -> b.kind[u] == 'R' && LC.FEATURES[b.perm[b.feat[u]]][1] == "y2>=3", eachindex(b.names))
    kr2m2 = findfirst(e -> e[1] == r2 && e[2] == m2, b.edges)
    bothsteps = Int[]
    live!(l, steps; on_step = (o, st, cond, y, ph) -> begin
        push!(recs, dc_record(b, o, st; partner_live = false, y = y, phase = ph))
        ever_r2m2 = max(ever_r2m2, st.q[kr2m2])
        if o.choice !== nothing
            o.choice.pref != o.choice.win && (forced += 1)
            length(choices) < 400 && push!(choices, (m1 = m1, c = o.choice))
        end
        if ph == "world" && y[1] > 0 && y[2] > 0
            push!(bothsteps, length(recs))
            k = join(sort([b.names[m] for m in o.acting if b.patch[m] <= 2]), "+"); k = isempty(k) ? "none" : k
            rel = y[1] > y[2] ? "y1>y2" : y[1] < y[2] ? "y1<y2" : "y1=y2"; both["$rel -> $k"] = get(both, "$rel -> $k", 0) + 1
            free = o.choice === nothing || o.choice.pref == o.choice.win
            (y[2] > y[1] && m2 in o.acting && free) && (m2_free_poorer1 += 1)
        end
    end)
    ws = [(x = x, v = check_dc(b, dc_window(b, @view recs[x-DC_L+1:x])), acts = !isempty(recs[x].acted)) for x in DC_L:length(recs)]
    rate(xs, f) = isempty(xs) ? NaN : count(f, xs) / length(xs)
    bs = Set(bothsteps); wb = [w for w in ws if w.x in bs]; ww = [w for w in ws if w.x > 800]
    conf_in(m) = [b.names[a] for (k, (a, c, _)) in enumerate(b.edges) if c == m && b.kind[a] == 'R' && l.st.q[k] >= 1]
    Dict("dc" => rate(ws, w -> w.v.dc), "smc" => rate(ws, w -> w.v.smc), "living" => count(w -> w.v.dc, ws), "n" => length(ws),
         "smc_both" => rate(wb, w -> w.v.smc), "n_both" => length(wb), "smc_fail_both" => count(w -> !w.v.smc, wb),
         "dc_world" => rate(ww, w -> w.v.dc), "smc_world" => rate(ww, w -> w.v.smc), "n_world" => length(ww),
         "m4b" => all(w -> !w.v.dc || w.acts, ws), "both" => both, "forced" => forced, "m2_free_when_y2_gt_y1" => m2_free_poorer1,
         "max_q_r2_m2" => ever_r2m2, "conf_receptors_into_m1_end" => conf_in(m1), "conf_receptors_into_m2_end" => conf_in(m2))
end

"""body_org's circuit raised on the curriculum (B1 of item 70) with or without idle_first: who acts in the school part
(both patches positive) and the confident receptor inputs of each motor at the end."""
function raise(seed; idle)
    b = LC.newborn(false); c = LC.init(b); nz = LC.Mulberry(seed); acts = Dict("m1" => 0, "m2" => 0); forced = 0
    for (i, y) in enumerate(LC.BO_CUR)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = nothing, idle_first = idle)
        if o.choice !== nothing
            o.choice.pref != o.choice.win && (forced += 1)
            (idle && length(choices) < 800) && push!(choices, (m1 = LC.unit(b, "m1"), c = o.choice))
        end
        i > 400 && for m in o.acting; b.patch[m] <= 2 && (acts[b.names[m]] += 1); end
    end
    conf_in(m) = [b.names[a] for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    Dict("school_acts" => acts, "forced" => forced, "conf_m1" => conf_in("m1"), "conf_m2" => conf_in("m2"),
         "last_on" => [b.names[u] for u in eachindex(b.names) if b.kind[u] == 'M' && c.active[u]])
end

saved528 = parsej(read(joinpath(LAB, "audit", "in", "state-v528.json"), String))
res = Dict{String,Any}()
for (name, L0) in (("saved_v528", saved528), ("newborn", nothing)), idle in (false, true)
    r = app_run(L0 === nothing ? LC.freshlife(born = 0) : deepcopy(L0), 2000; idle)
    res["app_$(name)_$(idle ? "idle" : "old")"] = r
    println(rpad("app $name $(idle ? "idle" : "old")", 26), " DC ", round(100r["dc"]; digits = 1), "% hSMC ", round(100r["smc"]; digits = 1),
        "% hSMC(both yield) ", round(100r["smc_both"]; digits = 1), "% (fail ", r["smc_fail_both"], "/", r["n_both"], ") world DC ",
        round(100r["dc_world"]; digits = 1), "% M4b ", r["m4b"], " forced ", r["forced"], " m2 free y2>y1 ", r["m2_free_when_y2_gt_y1"],
        " max q r2->m2 ", r["max_q_r2_m2"], "\n    both: ", r["both"], "\n    conf R->m1 ", r["conf_receptors_into_m1_end"], " R->m2 ", r["conf_receptors_into_m2_end"])
end
for idle in (false, true), seed in 1:10
    r = raise(seed; idle); res["raise_$(seed)_$(idle ? "idle" : "old")"] = r
    println("raise seed $seed $(idle ? "idle" : "old ") school acts ", r["school_acts"], " forced ", r["forced"], " conf m1 ", r["conf_m1"], " m2 ", r["conf_m2"], " last on ", r["last_on"])
end
o = (U = 0.02, MCOST = 0.004, STEPS = 10000)
for idle in (false, true)
    ds = [body_org_run("ORG", s, merge(o, (IDLE = idle,)))["death"] for s in 1:10]
    res["body_org_ORG_$(idle ? "idle" : "old")_death"] = ds
    println("body_org ORG 10000 steps $(idle ? "idle" : "old"): survived ", count(isnothing, ds), "/10, deaths ", ds)
end

# Lean: IdleFirst.pick on the recorded two-candidate choices
io = IOBuffer(); expect = Bool[]; branch = Dict("one idle" => 0, "both idle" => 0, "neither" => 0)
println(io, "-- Generated by experiments/eval_idle.jl: two-candidate choices of core/circuit.jl with idle_first, by Lean's IdleFirst.pick.")
println(io, "import LabCircuit\nopen BridgeLab\n")
for x in choices
    c = x.c; length(c.cand) == 2 || continue
    i1 = findfirst(==(x.m1), c.cand); i1 === nothing && continue
    l1 = c.last[i1]; l2 = c.last[3-i1]
    id1 = c.now - l1 > LC.FORGET; id2 = c.now - l2 > LC.FORGET
    branch[id1 != id2 ? "one idle" : id1 ? "both idle" : "neither"] += 1
    println(io, "#eval IdleFirst.pick $(LC.FORGET) $(c.now) $l1 $l2 $(c.pref == x.m1)")
    push!(expect, c.win == x.m1)
end
write(joinpath(LAB, "formal", "gen", "IdleChoices.lean"), String(take!(io)))
bp = joinpath(homedir(), "bridge-protocol"); ol = joinpath(LAB, "formal", ".olean")
out = cd(bp) do
    read(`lake env sh -c "LEAN_PATH=\"\$LEAN_PATH:$ol\" lean \"$(joinpath(LAB, "formal", "gen", "IdleChoices.lean"))\""`, String)
end
got = [l == "true" for l in split(strip(out), "\n")]
res["lean"] = Dict("n" => length(got), "identical" => got == expect, "branches" => branch)
println("Lean IdleFirst.pick on $(length(got)) choices: ", got == expect ? "identical to Julia" : "DIFFERENT from Julia", " ", branch)
write(joinpath(LAB, "experiments", "results-idle.json"), JSON.json(res, 2))
println("written experiments/results-idle.json")
