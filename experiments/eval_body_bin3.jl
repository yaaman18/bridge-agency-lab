# Item 74 (user 2026-11-02 "じゃあそれらお案で実装してみて"): (1) body_org's circuit with the app's contrast rule bin3 and the
# idle-first choice, (3) the raising with the nursery swapped (does the history decide which motor locks in?).
# Predictions: experiments/predictions-body-bin3.md (freeze-body-bin3.txt). The AGENCY-001 runs are variant_horizon.jl with
# CONTRAST=bin3 IDLE=1 and with CUR=swap. Usage: julia --project=. experiments/eval_body_bin3.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, ".."))
include(joinpath(@__DIR__, "curricula.jl"))

"""Raise body_org's circuit (B1 of item 70) and report the school part (steps 401-800, both patches positive): acts per
motor, forced choices, switches of the unforced winner, and the confident receptor inputs of each motor at the end."""
function raise(seed; contrast, idle, cur)
    b = LC.newborn(false); c = LC.init(b); nz = LC.Mulberry(seed)
    acts = Dict("m1" => 0, "m2" => 0); forced = 0; switches = 0; lastwin = 0
    for (i, y) in enumerate(curriculum(cur))
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast, idle_first = idle)
        i > 400 || continue
        isf = o.choice !== nothing && o.choice.pref != o.choice.win
        isf && (forced += 1)
        pa = [m for m in o.acting if b.patch[m] <= 2]
        for m in pa; acts[b.names[m]] += 1; end
        if length(pa) == 1 && !isf
            (lastwin != 0 && pa[1] != lastwin) && (switches += 1); lastwin = pa[1]
        end
    end
    conf_in(m) = [b.names[a] for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    Dict("school_acts" => acts, "forced" => forced, "unforced_switches" => switches, "conf_m1" => conf_in("m1"),
         "conf_m2" => conf_in("m2"), "last_on" => [b.names[u] for u in eachindex(b.names) if b.kind[u] == 'M' && c.active[u]])
end

res = Dict{String,Any}()
conds = [("old", nothing, false, :std), ("old-swap", nothing, false, :swap), ("bin3", :bin3, false, :std),
         ("bin3+idle", :bin3, true, :std), ("bin3+idle-swap", :bin3, true, :swap)]
for (name, ct, idle, cur) in conds
    rs = [raise(s; contrast = ct, idle, cur) for s in 1:10]; res["raise_$name"] = rs
    for (s, r) in enumerate(rs)
        println(rpad("raise $name", 22), " seed ", lpad(s, 2), " school ", r["school_acts"], " forced ", r["forced"], " switches ",
                r["unforced_switches"], " conf m1 ", r["conf_m1"], " m2 ", r["conf_m2"], " last on ", r["last_on"])
    end
end
o = (U = 0.02, MCOST = 0.004, STEPS = 10000)
for (name, opt) in (("bin3", (CONTRAST = "bin3",)), ("bin3+idle", (CONTRAST = "bin3", IDLE = true)))
    ds = [body_org_run("ORG", s, merge(o, opt))["death"] for s in 1:10]; res["body_org_ORG_$(name)_death"] = ds
    println("body_org ORG 10000 steps $name: survived ", count(isnothing, ds), "/10, deaths ", ds)
end
write(joinpath(LAB, "experiments", "results-body-bin3.json"), JSON.json(res, 2))
println("written experiments/results-body-bin3.json")
