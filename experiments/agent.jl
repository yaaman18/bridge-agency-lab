# S15 (spec discussion/specs/S15-body-agent.md r1): on one raised object, the choice trials C1, C2 (with DC records) and the
# survival table; the tool's L2 components; the structural value of LabCircuit (kappa); act fixed before the run; and the
# Lean file formal/gen/AgentBody.lean that builds `agentOf` for every object whose checks pass. Writes experiments/results-agent.json.
# Predictions: predictions-agent.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON, SHA
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(71:80, ",")), ","))
const H = 392
const WIN = 5:15

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
statehash(c) = bytes2hex(sha256(string(Tuple(isdefined(c, f) ? getfield(c, f) : nothing for f in fieldnames(typeof(c))))))

"""A choice trial on schedule `sch` (choice_params): DC records of updates 1..32, the choice set over WIN (AS.choice's
definition), the receptors on through WIN, and the hash of the start state."""
function trial(s, pc, sch)
    st = AS.initial_state(s, pc); S = s.side[st]; h0 = statehash(S.c)
    recs = LC.DCStep[]; chosen = Set{Int}(); on = Dict(r => true for r in eachindex(s.names) if s.b.kind[r] == 'R')
    SINK[] = (st_, o, c, y) -> st_ === st && length(recs) < 32 && push!(recs, LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world"))
    for t in 1:32
        AS.step!(st, s, pc, sch, Set{Int}())
        if t in WIN
            for m in keys(s.motors); st.active[m] && push!(chosen, m); end
            for r in keys(on); st.active[r] || (on[r] = false); end
        end
    end
    SINK[] = nothing; delete!(s.side, st)
    (h0 = h0, recs = recs, choice = chosen, on = on)
end

"""POSTHOC=1 (not the frozen contract, a check of the Lean path): the window w is updates 33..64 of the survival schedule p1-high
(params, not abundant), from the same raised object."""
const POSTHOC = get(ENV, "POSTHOC", "0") == "1"
function survwindow(s, p, sch)
    st = AS.initial_state(s, p); recs = LC.DCStep[]
    SINK[] = (st_, o, c, y) -> st_ === st && push!(recs, LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world"))
    for t in 1:64; AS.step!(st, s, p, sch, Set{Int}()); end
    SINK[] = nothing; delete!(s.side, st)
    length(recs) >= 64 ? recs[33:64] : nothing
end

kindnum(k) = k == 'R' ? 0 : k == 'C' ? 1 : 2
blist(x) = "#[" * join(string.(x), ", ") * "]"

su = LBA.setup_with(H); p, pc = su.params, su.choice_params; c1, c2 = su.choice
println("choice schedules: ", c1, " ", c2)
res = Dict{String,Any}("spec" => "discussion/specs/S15-body-agent.md r1", "rule" => "sf", "seeds" => SEEDS, "H" => H, "objects" => Any[])
io = IOBuffer(); B0 = Ref{Any}(nothing); nagent = 0
for seed in SEEDS, arm in (:std, :swap)
    s = org(seed, su, arm); B0[] === nothing && (B0[] = s.b); @assert s.b.edges == B0[].edges
    hraised = statehash(s.raised)
    T1, T2 = trial(s, pc, c1), trial(s, pc, c2)
    r = AS.evaluate(s, su)
    T = Set(findall(n -> n in r.value_tracking, s.names))
    tab = [(AS.survives(s, p, x), isempty(T) ? AS.survives(s, p, x) : AS.survives(s, p, x; silenced = T)) for x in su.survival]
    prov = hraised == T1.h0 == T2.h0 == statehash(s.raised)   # the survival trials also start from s.raised (initial_state copies it)
    wr = POSTHOC ? survwindow(s, p, su.survival[1]) : T1.recs
    w = LC.dc_window(s.b, wr); dc = LC.check_dc(s.b, w)
    # structural value of LabCircuit: |contributionOf w e ∩ nuPhiOf w|, nuPhiOf = kept self edges
    nuphi = Set(k for k in eachindex(s.edges) if w.kept[k] && s.b.kind[s.edges[k][1]] != 'R')
    value(e) = count(k -> w.via[e, k] && k in nuphi, eachindex(s.edges))
    recs = [e for e in eachindex(s.names) if s.b.kind[e] == 'R']
    attrib = Dict(e => (T1.on[e] && !T2.on[e]) ? Set(T1.choice) : (T2.on[e] && !T1.on[e]) ? Set(T2.choice) : nothing for e in recs)
    att = [e for e in recs if attrib[e] !== nothing]
    wit = nothing
    for e1 in att, e2 in att
        e1 < e2 && value(e1) != value(e2) && attrib[e1] != attrib[e2] && (wit = (e1, e2); break)
    end
    needed = any(i -> tab[i][1] && !tab[i][2], eachindex(tab)) && all(i -> !tab[i][2] || tab[i][1], eachindex(tab))
    build = dc.dc && wit !== nothing && needed && prov
    obj = Dict{String,Any}("seed" => seed, "arm" => String(arm), "provenance_same" => prov, "raised_hash" => hraised,
        "tool_L2" => r.agency, "tool" => Dict("core" => r.core, "hinge" => r.core_enables_action, "alive" => r.alive_somewhere, "differentiated" => r.differentiated, "needed" => r.value_needed, "T" => r.value_tracking),
        "dc" => Dict(string(k) => getfield(dc, k) for k in keys(dc)), "choice_C1" => [s.names[m] for m in T1.choice], "choice_C2" => [s.names[m] for m in T2.choice],
        "attributable" => [s.names[e] for e in att], "values" => Dict(s.names[e] => value(e) for e in recs), "witness" => wit === nothing ? nothing : [s.names[wit[1]], s.names[wit[2]]],
        "tab" => [[a, b] for (a, b) in tab], "needed_julia" => needed, "builds" => build, "r7_r8_attributable" => attrib[LC.unit(s.b, "r7")] !== nothing && attrib[LC.unit(s.b, "r8")] !== nothing)
    push!(res["objects"], obj)
    if build
        global nagent += 1; i = nagent; nU = length(s.names); nK = length(s.edges)
        println(io, "-- object $i: seed $seed arm $arm, window = $(POSTHOC ? "updates 33..64 of the survival schedule p1-high (post hoc, not the frozen contract)" : "updates 1..32 of the choice trial C1 $(c1.name)"); raised state sha256 $hraised (same in C1, C2 and the survival table)")
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
        println(io, "def agent$i := agentOf w$i act$i (by decide)")
        x = "(⟨$(m-1), by decide⟩ : Fin net.nU)"   # act a ≠ act b: x ∈ act a and x ∉ act b
        println(io, "  ⟨⟨$(a-1), by decide⟩, ⟨$(b-1), by decide⟩, by decide,")
        println(io, "   fun h => (show $x ∉ act$i ⟨$(b-1), by decide⟩ from by show ¬ (_ = true); decide) (h ▸ (show $x ∈ act$i ⟨$(a-1), by decide⟩ from by show _ = true; decide))⟩")
        println(io, "  tab$i (by decide)\n")
        obj["lean_index"] = i
    end
    println("seed=$seed $arm prov=$prov toolL2=$(r.agency) dc=$(dc.dc) $(dc) witness=$(obj["witness"]) needed=$needed builds=$build values r7=$(value(LC.unit(s.b, "r7"))) r8=$(value(LC.unit(s.b, "r8"))) C1=$(obj["choice_C1"]) C2=$(obj["choice_C2"])")
end
b = B0[]; hdr = IOBuffer()
println(hdr, "-- Generated by experiments/agent.jl (S15): Agent values built from BODY runs with LabCircuit's agentOf.")
println(hdr, "-- A definition below type-checks only if checkDC, the ValueDifferentiated witness and checkValueNeeded hold for the given data.")
println(hdr, "import LabCircuit\nopen BridgeLab ERIEC.Agency\n")
println(hdr, "def kindOf : Nat → Kind\n  | 0 => .receptor\n  | 1 => .core\n  | _ => .motor\n")
println(hdr, "def net : Net where\n  nU := $(length(b.names))\n  nK := $(length(b.edges))")
println(hdr, "  kind := fun u => kindOf ($(blist([kindnum(k) for k in b.kind]))[u.val]!)")
println(hdr, "  src := fun k => ⟨$(blist([e[1]-1 for e in b.edges]))[k.val]! % $(length(b.names)), Nat.mod_lt _ (by decide)⟩")
println(hdr, "  dst := fun k => ⟨$(blist([e[2]-1 for e in b.edges]))[k.val]! % $(length(b.names)), Nat.mod_lt _ (by decide)⟩\n")
write(joinpath(LAB, "formal", "gen", POSTHOC ? "AgentBody-posthoc.lean" : "AgentBody.lean"), String(take!(hdr)) * String(take!(io)))
res["agents_built_in_julia"] = nagent
res["posthoc_window_from_survival_p1_high"] = POSTHOC
write(joinpath(LAB, "experiments", POSTHOC ? "results-agent-posthoc.json" : "results-agent.json"), JSON.json(res, 2))
println("objects $(length(res["objects"])), Agent definitions written: $nagent (formal/gen/AgentBody.lean)")
