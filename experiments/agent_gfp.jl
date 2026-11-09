# S27 (spec discussion/specs/S27-body-gfp.md r1, gaps G9): agent2.jl (S17) with the structural value counted on kappa and on the
# window's greatest fixed point (core/dc.jl nu_fin, Lean Window.nuFin / agentOfGfp). S17: one contract (the survival schedules): base trial B1 = p1-high, comparison
# B2 = p2-high, window w = updates 33..64 of B1, T_struct = receptors with structural value > 0 in w, tab over the 4 survival schedules
# with T_struct silenced from update 1. Writes formal/gen/AgentBody2.lean and experiments/results-agent2.json. Derived from agent.jl (S15).
# Predictions: predictions-agent2.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON, SHA
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(321:330, ",")), ","))
const H = parse(Int, get(ENV, "H", "392"))   # S24: the horizon from ENV (default 392 unchanged)
const WIN = 33:64
const MODE = get(ENV, "VALUE", "gfp"); MODE in ("gfp", "kappa") || error("VALUE")

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
statehash(c) = bytes2hex(sha256(string(Tuple(isdefined(c, f) ? getfield(c, f) : nothing for f in fieldnames(typeof(c))))))

"""A survival trial = AS.run_trajectory on params (the trajectory of AS.survives): the DC records of the living updates, the
survival (AS.alive), the acting patch motors and the receptors on through WIN."""
function survtrial(s, p, sch)
    recs = LC.DCStep[]
    SINK[] = (st_, o, c, y) -> push!(recs, LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world"))
    traj = AS.run_trajectory(s, p, sch)
    SINK[] = nothing
    chosen = Set{Int}(m for t in WIN for m in keys(s.motors) if traj[t+1].active[m])
    on = Dict(r => all(t -> traj[t+1].active[r], WIN) for r in eachindex(s.names) if s.b.kind[r] == 'R')
    (recs = recs, survived = AS.alive(traj, s, p), choice = chosen, on = on)
end

kindnum(k) = k == 'R' ? 0 : k == 'C' ? 1 : 2
blist(x) = "#[" * join(string.(x), ", ") * "]"

su = LBA.setup_with(H); p, pc = su.params, su.choice_params
B1s, B2s = su.survival[1], su.survival[2]; @assert B1s.name == "p1-high" && B2s.name == "p2-high"
res = Dict{String,Any}("spec" => "discussion/specs/S27-body-gfp.md r1", "rule" => "sf", "seeds" => SEEDS, "H" => H, "objects" => Any[])
io = IOBuffer(); io2 = IOBuffer(); B0 = Ref{Any}(nothing); nagent = 0; nobj = 0
for seed in SEEDS, arm in (:std, :swap)
    s = org(seed, su, arm); B0[] === nothing && (B0[] = s.b); @assert s.b.edges == B0[].edges
    hraised = statehash(s.raised)
    T1, T2 = survtrial(s, p, B1s), survtrial(s, p, B2s)
    length(T1.recs) >= 64 || error("B1 died before 64")
    w = LC.dc_window(s.b, T1.recs[33:64]); dc = LC.check_dc(s.b, w)
    kap = Set(k for k in eachindex(s.edges) if w.kept[k] && s.b.kind[s.edges[k][1]] != 'R')
    nuv = LC.nu_fin(s.b, w); gfp = Set(findall(nuv))
    nuphi = MODE == "gfp" ? gfp : kap
    value(e) = count(k -> w.via[e, k] && k in nuphi, eachindex(s.edges))
    vk(e) = LC.value_kappa(s.b, w, e); vg(e) = LC.value_gfp(s.b, w, nuv, e)
    recs = [e for e in eachindex(s.names) if s.b.kind[e] == 'R']
    Ts = Set(e for e in recs if value(e) > 0)
    tab = [(AS.survives(s, p, x), isempty(Ts) ? AS.survives(s, p, x) : AS.survives(s, p, x; silenced = Ts)) for x in su.survival]
    traj_ok = T1.survived == tab[1][1] && T2.survived == tab[2][1]
    prov = hraised == statehash(s.raised)
    r = AS.evaluate(s, su)
    why = Dict(e => (T1.on[e] && T2.on[e]) ? "on through the window in both" : (!T1.on[e] && !T2.on[e]) ? "on through the window in neither" : "" for e in recs)
    attrib = Dict(e => why[e] != "" ? nothing : (T1.on[e] ? Set(T1.choice) : Set(T2.choice)) for e in recs)
    for e in recs; attrib[e] !== nothing && isempty(attrib[e]) && (why[e] = "attributed set empty"; attrib[e] = nothing); end
    att = [e for e in recs if attrib[e] !== nothing]
    wit = nothing
    for e1 in att, e2 in att
        e1 < e2 && value(e1) != value(e2) && attrib[e1] != attrib[e2] && (wit = (e1, e2); break)
    end
    needed = any(i -> tab[i][1] && !tab[i][2], eachindex(tab)) && all(i -> !tab[i][2] || tab[i][1], eachindex(tab))
    build = dc.dc && wit !== nothing && needed && prov && traj_ok
    obj = Dict{String,Any}("seed" => seed, "arm" => String(arm), "provenance_same" => prov, "trajectory_matches_tab" => traj_ok, "survived_B1_B2" => [T1.survived, T2.survived], "T_struct" => [s.names[e] for e in Ts], "unattributable" => Dict(s.names[e] => why[e] for e in recs if why[e] != ""), "raised_hash" => hraised,
        "tool_L2" => r.agency, "tool" => Dict("core" => r.core, "hinge" => r.core_enables_action, "alive" => r.alive_somewhere, "differentiated" => r.differentiated, "needed" => r.value_needed, "T" => r.value_tracking),
        "dc" => Dict(string(k) => getfield(dc, k) for k in keys(dc)), "choice_B1" => [s.names[m] for m in T1.choice], "choice_B2" => [s.names[m] for m in T2.choice],
        "attributable" => [s.names[e] for e in att], "values" => Dict(s.names[e] => value(e) for e in recs), "witness" => wit === nothing ? nothing : [s.names[wit[1]], s.names[wit[2]]],
        "tab" => [[a, b] for (a, b) in tab], "mode" => MODE, "kappa" => sort([s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]] for k in kap]), "nu_fin" => sort([s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]] for k in gfp]), "kappa_sub_nu" => issubset(kap, gfp), "nu_has_receptor_edge" => any(k -> s.b.kind[s.edges[k][1]] == 'R', gfp), "value_kappa" => Dict(s.names[e] => vk(e) for e in recs), "value_gfp" => Dict(s.names[e] => vg(e) for e in recs), "gfp_ge_kappa" => all(e -> vg(e) >= vk(e), recs), "nu_bits" => collect(nuv), "needed_julia" => needed, "builds" => build, "r7_r8_attributable" => attrib[LC.unit(s.b, "r7")] !== nothing && attrib[LC.unit(s.b, "r8")] !== nothing)
    push!(res["objects"], obj)
    # C1 (S27): every window, Lean's nuFin against Julia's nu_fin
    global nobj += 1; j = nobj; nU0 = length(s.names); nK0 = length(s.edges)
    println(io2, "-- window $j: seed $seed arm $arm")
    println(io2, "def nw$j : Window net where")
    println(io2, "  kept := fun k => $(blist(w.kept))[k.val]!")
    println(io2, "  on := fun u => $(blist(w.on))[u.val]!")
    println(io2, "  reproduced := fun m k => $(blist(vec(permutedims(w.reproduced))))[m.val * $nK0 + k.val]!")
    println(io2, "  affects := fun m e => $(blist(vec(permutedims(w.affects))))[m.val * $nU0 + e.val]!")
    println(io2, "  reproducedVia := fun e k => $(blist(vec(permutedims(w.via))))[e.val * $nK0 + k.val]!")
    println(io2, "#eval decide (nw$j.nuFin = Finset.univ.filter fun k : Fin net.nK => ($(blist(nuv)) : Array Bool)[k.val]! = true)\n")
    if build
        global nagent += 1; i = nagent; nU = length(s.names); nK = length(s.edges)
        println(io, "-- object $i: seed $seed arm $arm, value mode $MODE, T_struct $(sort([s.names[e] for e in Ts])) silenced from update 1 in tab; window = updates 33..64 of B1 (p1-high); act from B1/B2; tab over the 4 survival schedules with T_struct silenced; raised state sha256 $hraised (same in C1, C2 and the survival table)")
        println(io, "def w$i : Window net where")
        println(io, "  kept := fun k => $(blist(w.kept))[k.val]!")
        println(io, "  on := fun u => $(blist(w.on))[u.val]!")
        println(io, "  reproduced := fun m k => $(blist(vec(permutedims(w.reproduced))))[m.val * $nK + k.val]!")
        println(io, "  affects := fun m e => $(blist(vec(permutedims(w.affects))))[m.val * $nU + e.val]!")
        println(io, "  reproducedVia := fun e k => $(blist(vec(permutedims(w.via))))[e.val * $nK + k.val]!")
        actT = [[haskey(attrib, u) && attrib[u] !== nothing && m in attrib[u] for m in 1:nU] for u in 1:nU]
        println(io, "def actT$i : Array (Array Bool) := #[" * join([blist(row) for row in actT], ", ") * "]")
        println(io, "def act$i : Fin net.nU → Set (Fin net.nU) := fun e => {m | (actT$i[e.val]!)[m.val]! = true}")
        println(io, "def tab$i : Fin 4 → Variant → Bool := fun j v => match v with | .intact => $(blist([a for (a, _) in tab]))[j.val]! | .ablated => $(blist([b for (_, b) in tab]))[j.val]!")
        e1, e2 = wit; m = first(setdiff(union(attrib[e1], attrib[e2]), intersect(attrib[e1], attrib[e2])))
        a, b = m in attrib[e1] ? (e1, e2) : (e2, e1)   # m is in act a and not in act b
        println(io, "set_option maxRecDepth 100000 in")
        println(io, "def agent$i := $(MODE == "gfp" ? "agentOfGfp" : "agentOf") w$i act$i (by decide)")
        x = "(⟨$(m-1), by decide⟩ : Fin net.nU)"   # act a ≠ act b: x ∈ act a and x ∉ act b
        println(io, "  ⟨⟨$(a-1), by decide⟩, ⟨$(b-1), by decide⟩, by decide,")
        println(io, "   fun h => (show $x ∉ act$i ⟨$(b-1), by decide⟩ from by show ¬ (_ = true); decide) (h ▸ (show $x ∈ act$i ⟨$(a-1), by decide⟩ from by show _ = true; decide))⟩")
        println(io, "  tab$i (by decide)\n")
        obj["lean_index"] = i
    end
    println("seed=$seed $arm prov=$prov toolL2=$(r.agency) dc=$(dc.dc) $(dc) witness=$(obj["witness"]) needed=$needed builds=$build values r7=$(value(LC.unit(s.b, "r7"))) r8=$(value(LC.unit(s.b, "r8"))) B1=$(obj["choice_B1"]) B2=$(obj["choice_B2"]) Ts=$(obj["T_struct"]) traj=$traj_ok")
end
b = B0[]; hdr = IOBuffer()
println(hdr, "-- Generated by experiments/agent2.jl (S17): Agent values built from BODY runs with LabCircuit's agentOf.")
println(hdr, "-- A definition below type-checks only if checkDC, the ValueDifferentiated witness and checkValueNeeded hold for the given data.")
println(hdr, "import LabCircuit\nopen BridgeLab ERIEC.Agency\n")
println(hdr, "def kindOf : Nat → Kind\n  | 0 => .receptor\n  | 1 => .core\n  | _ => .motor\n")
println(hdr, "def net : Net where\n  nU := $(length(b.names))\n  nK := $(length(b.edges))")
println(hdr, "  kind := fun u => kindOf ($(blist([kindnum(k) for k in b.kind]))[u.val]!)")
println(hdr, "  src := fun k => ⟨$(blist([e[1]-1 for e in b.edges]))[k.val]! % $(length(b.names)), Nat.mod_lt _ (by decide)⟩")
println(hdr, "  dst := fun k => ⟨$(blist([e[2]-1 for e in b.edges]))[k.val]! % $(length(b.names)), Nat.mod_lt _ (by decide)⟩\n")
hdrs = String(take!(hdr)); GENN = get(ENV, "GEN", MODE == "gfp" ? "AgentBodyGfp" : "AgentBodyKappa")
write(joinpath(LAB, "formal", "gen", GENN * "-nu.lean"), hdrs * String(take!(io2)))
write(joinpath(LAB, "formal", "gen", GENN * ".lean"), hdrs * String(take!(io)))
res["agents_built_in_julia"] = nagent
write(get(ENV, "OUT", joinpath(LAB, "experiments", "results-gfp-$(MODE).json")), JSON.json(res, 2))   # S24: OUT (default unchanged)
println("objects $(length(res["objects"])), Agent definitions written: $nagent (formal/gen/$(GENN).lean)")
