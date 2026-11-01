# The DC audit runs (predictions-dc3.md, frozen in freeze-dc3.txt: the state-dependent alpha of item 69; the runs of
# predictions-dc.md and predictions-dc2.md are kept in results-dc-v1.json and results-dc-v2.json), and the export of sample windows to Lean (formal/gen/Windows.lean)
# so that Lean's own `Window.checkDC` can be evaluated on them and compared with Julia.
# Usage: julia --project=. audit/dc_run.jl   (then sh audit/dc_lean.sh compares with Lean)
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, ".."))
parsej(s) = JSON.parse(s; dicttype = Dict{String,Any})

"""Live `steps` steps from L0, recording DC windows. With `partner = true`, a scripted partner answers every call 3
steps later (gesture kinds in rotation 1-4), and r9 is coupled through m3 (D4). Each window is judged with the
state-dependent alpha (`v`, item 69) and with the fixed alpha of item 67 (`vfix`)."""
function dc_series(L0, steps; partner = false)
    l = makelife(L0; rule = "bin3")   # the rule of the item 69 runs (the app is bin3+idle since v3.7)
    recs = LC.DCStep[]; due = Int[]; kind = 0
    for t in 1:steps
        if partner && !isempty(due) && due[1] == t
            popfirst!(due); kind = kind % 4 + 1; gesture!(l, kind)
        end
        live!(l, 1; on_step = (o, st, cond, y, ph) -> begin
            push!(recs, dc_record(l.b, o, st; partner_live = partner, y = y, phase = ph))
            (partner && o.call) && push!(due, t + 3)
        end)
    end
    out = []
    for x in DC_L:length(recs)
        w = dc_window(l.b, @view recs[x-DC_L+1:x])
        wf = dc_window(l.b, @view(recs[x-DC_L+1:x]); alpha = :fixed)
        push!(out, (x = x, v = check_dc(l.b, w), vfix = check_dc(l.b, wf), acts = !isempty(recs[x].acted), w = w))
    end
    l.b, out
end
rate(xs, f) = isempty(xs) ? NaN : count(f, xs) / length(xs)
summary(xs) = Dict("n" => length(xs), "self" => rate(xs, r -> r.v.self), "smc" => rate(xs, r -> r.v.smc),
    "act" => rate(xs, r -> r.v.act), "bound" => rate(xs, r -> r.v.bound), "dc" => rate(xs, r -> r.v.dc),
    "living" => count(r -> r.v.dc, xs), "m4b_check" => all(r -> !r.v.dc || r.acts, xs),
    "living_without_act" => count(r -> r.v.dc && !r.acts, xs))

# For comparison only: the reading before item 67 (r10/r11 as environment, reached by the call m3).
function proprio_environment(b, w)
    aff = copy(w.affects); m3 = LC.unit(b, "m3")
    for u in eachindex(b.names)
        b.kind[u] == 'R' && b.perm[b.feat[u]] in (10, 11) && (aff[m3, u] = true)
    end
    LC.DCWindow(w.kept, w.on, w.reproduced, aff, w.via)
end

saved = parsej(read(joinpath(LAB, "audit", "in", "state-v518.json"), String))
saved528 = parsej(read(joinpath(LAB, "audit", "in", "state-v528.json"), String))
b1, s1 = dc_series(deepcopy(saved), 2000)
b2, s2 = dc_series(LC.freshlife(born = 0), 2000)
b3, s3 = dc_series(deepcopy(saved), 2000; partner = true)
b4, s4 = dc_series(LC.freshlife(born = 0), 2000; partner = true)
b5, s5 = dc_series(deepcopy(saved528), 2000)
fixed(xs) = [(x = r.x, v = r.vfix, acts = r.acts) for r in xs]
before_world(xs) = [r for r in xs if r.x <= 800]; world(xs) = [r for r in xs if r.x > 800]
runs = Dict("saved_v518" => s1, "newborn" => s2, "saved_v518_partner" => s3, "newborn_partner" => s4, "saved_v528" => s5,
    "newborn_before_world" => before_world(s2), "newborn_world" => world(s2),
    "newborn_partner_before_world" => before_world(s4), "newborn_partner_world" => world(s4))
res = Dict{String,Any}("L" => DC_L, "alpha" => "state (item 69)",
    "state" => Dict(k => summary(xs) for (k, xs) in runs), "fixed" => Dict(k => summary(fixed(xs)) for (k, xs) in runs))
v(k, f) = res["state"][k][f]; vf(k, f) = res["fixed"][k][f]
pc(x) = string(round(100x; digits = 1), "%")
verdicts = [
    ("DQ7", v("newborn_before_world", "living") == 0, "newborn before the world: DC $(v("newborn_before_world", "living"))/$(v("newborn_before_world", "n"))"),
    ("DQ8", v("newborn", "dc") < vf("newborn", "dc"), "newborn DC $(pc(v("newborn", "dc"))) vs fixed $(pc(vf("newborn", "dc")))"),
    ("DQ9", v("saved_v518", "smc") > vf("saved_v518", "smc"), "saved v518 hSMC $(pc(v("saved_v518", "smc"))) vs fixed $(pc(vf("saved_v518", "smc")))"),
    ("DQ10", v("saved_v518", "dc") >= 0.10, "saved v518 DC $(pc(v("saved_v518", "dc"))) ($(v("saved_v518", "living"))/$(v("saved_v518", "n")))"),
    ("DQ11", v("newborn_world", "dc") >= vf("newborn_world", "dc"), "newborn world DC $(pc(v("newborn_world", "dc"))) vs fixed $(pc(vf("newborn_world", "dc")))"),
    ("DQ12", all(k -> v(k, "m4b_check"), keys(runs)), "M4b in every run: " * join(["$k=$(v(k, "m4b_check"))" for k in sort(collect(keys(runs)))], ", "))]
res["verdicts"] = [Dict("id" => a, "holds" => h, "value" => m) for (a, h, m) in verdicts]
write(joinpath(LAB, "audit", "results-dc.json"), JSON.json(res, 2))
for (a, h, m) in verdicts; println(a, " ", h ? "HOLDS" : "FAILS", " - ", m); end
println("predictions holding (DQ13 is sh audit/dc_lean.sh): ", count(x -> x[2], verdicts), "/", length(verdicts))
for k in sort(collect(keys(runs))), (lab, r) in (("state", res["state"][k]), ("fixed", res["fixed"][k]))
    println(rpad(k, 30), rpad(lab, 6), " self ", pc(r["self"]), " smc ", pc(r["smc"]), " act ", pc(r["act"]), " bound ", pc(r["bound"]), " dc ", pc(r["dc"]), " (", r["living"], "/", r["n"], ") m4b ", r["m4b_check"])
end

# ---- sample windows for Lean: real windows covering each clause true and false, and synthetic ones ----
function pick(series, n)
    chosen = Int[]
    for f in (:self, :smc, :act, :bound, :dc), val in (true, false)
        i = findfirst(r -> getfield(r.v, f) == val && !(r.x in chosen), series)
        i === nothing || push!(chosen, series[i].x)
    end
    step = max(1, length(series) ÷ n)
    for r in series[1:step:end]; length(chosen) >= n && break; r.x in chosen || push!(chosen, r.x); end
    [r for r in series if r.x in chosen]
end
samples = vcat([(b1, r) for r in pick(s1, 6)], [(b2, r) for r in pick(s2, 8)], [(b4, r) for r in pick(s4, 6)], [(b5, r) for r in pick(s5, 4)])
# synthetic windows for the implementation cross-check only: the previous reading, and 5% of entries flipped by a
# fixed generator, so that every clause is seen true and false
rng = LC.Mulberry(2026)
flip(x) = map(y -> rng() < 0.05 ? !y : y, x)
syn = []
for (bb, r) in samples
    w1 = proprio_environment(bb, r.w)
    push!(syn, (bb, (x = r.x, v = check_dc(bb, w1), w = w1)))
    w2 = LC.DCWindow(flip(r.w.kept), flip(r.w.on), BitMatrix(flip(r.w.reproduced)), r.w.affects, r.w.via)
    push!(syn, (bb, (x = r.x, v = check_dc(bb, w2), w = w2)))
end
samples = vcat(samples, syn)
kindnum(k) = k == 'R' ? 0 : k == 'C' ? 1 : 2
blist(x) = "#[" * join(string.(x), ", ") * "]"
io = IOBuffer()
println(io, "-- Generated by audit/dc_run.jl: sample windows of the DC audit, evaluated by Lean's own Window.checkDC.")
println(io, "import LabCircuit\nopen BridgeLab\n")
println(io, "def kindOf : Nat → Kind\n  | 0 => .receptor\n  | 1 => .core\n  | _ => .motor\n")
b = b1; nU = length(b.names); nK = length(b.edges)
println(io, "def net : Net where\n  nU := $nU\n  nK := $nK")
println(io, "  kind := fun u => kindOf ($(blist([kindnum(k) for k in b.kind]))[u.val]!)")
println(io, "  src := fun k => ⟨$(blist([e[1]-1 for e in b.edges]))[k.val]! % $nU, Nat.mod_lt _ (by decide)⟩")
println(io, "  dst := fun k => ⟨$(blist([e[2]-1 for e in b.edges]))[k.val]! % $nU, Nat.mod_lt _ (by decide)⟩\n")
expect = []
for (i, (bb, r)) in enumerate(samples)
    @assert bb.edges == b.edges && bb.kind == b.kind
    w = r.w
    println(io, "def w$i : Window net where")
    println(io, "  kept := fun k => $(blist(w.kept))[k.val]!")
    println(io, "  on := fun u => $(blist(w.on))[u.val]!")
    println(io, "  reproduced := fun m k => $(blist(vec(permutedims(w.reproduced))))[m.val * $nK + k.val]!")
    println(io, "  affects := fun m e => $(blist(vec(permutedims(w.affects))))[m.val * $nU + e.val]!")
    println(io, "  reproducedVia := fun e k => $(blist(vec(permutedims(w.via))))[e.val * $nK + k.val]!")
    println(io, "#eval [decide w$i.ElemSelf, decide w$i.ElemSMC, decide w$i.ElemAct, decide w$i.ElemBound, w$i.checkDC]\n")
    push!(expect, [r.v.self, r.v.smc, r.v.act, r.v.bound, r.v.dc])
end
mkpath(joinpath(LAB, "formal", "gen"))
write(joinpath(LAB, "formal", "gen", "Windows.lean"), String(take!(io)))
write(joinpath(LAB, "formal", "gen", "expected.json"), JSON.json(expect))
println("exported ", length(samples), " windows to formal/gen/Windows.lean")
