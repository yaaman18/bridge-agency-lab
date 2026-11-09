# S36 (spec discussion/specs/S36-body-transplant.md r1): transplants on the raised circuits of RB (S34/S35). At the trial's
# start the raised circuit's per-edge state (q, sg, h, cOn, cOff, lastC) of the edges into m1 and m2 is replaced:
# T0 self (control), T1 recipient :std <- donor :swap, T1r recipient :swap <- donor :std, T2 receptor-pair permutation on
# :std (r1<->r2, r3<->r4, r7<->r8; each edge's whole state moves together), T2r the same on :swap. Per-unit fields (active,
# lastM, off), the cores' loops, m0's and rb's edges are not touched. Writes results-transplant.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(431:440, ",")), ","))
const H = 392
const FIELDS = (:q, :sg, :h, :cOn, :cOff, :lastC)
const PI = Dict("r1" => "r2", "r2" => "r1", "r3" => "r4", "r4" => "r3", "r7" => "r8", "r8" => "r7")

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)
targets(b) = [k for m in (LC.unit(b, "m1"), LC.unit(b, "m2")) for k in b.ins[m]]
edge_of(b, a, c) = only([k for k in eachindex(b.edges) if b.names[b.edges[k][1]] == a && b.names[b.edges[k][2]] == c])
getf(c, f, k) = (v = getfield(c, f); v === nothing ? nothing : v[k])
setf!(c, f, k, x) = (v = getfield(c, f); v === nothing || (v[k] = x))

"""Recipient s with the per-edge state of the edges into m1, m2 taken from the donor's raised circuit."""
function transplant(s, donor)
    s.b.edges == donor.b.edges || error("different wirings")
    t = deepcopy(s)
    for k in targets(s.b), f in FIELDS; setf!(t.raised, f, k, getf(donor.raised, f, k)); end
    t
end
"""The receptor-pair permutation: new state (r, m) = old state (PI(r), m) for m in m1, m2; other edges unchanged."""
function permute(s)
    t = deepcopy(s); b = s.b
    for m in ("m1", "m2"), (r, r2) in PI
        k = edge_of(b, r, m); k2 = edge_of(b, r2, m)
        for f in FIELDS; setf!(t.raised, f, k, getf(s.raised, f, k2)); end
    end
    t
end
# Structural equality, recursing into structs and arrays (isequal on a mutable struct such as Mulberry or Pend compares
# identity, as in S30). I-R 2026-11-09 #4: compares every field of the organism except the per-trial side table.
deq(a, b) = typeof(a) == typeof(b) && (a isa AbstractArray ? (size(a) == size(b) && all(deq(x, y) for (x, y) in zip(a, b))) :
    a isa AbstractDict ? (keys(a) == keys(b) && all(deq(a[k], b[k]) for k in keys(a))) :
    (isstructtype(typeof(a)) && !(a isa Number || a isa AbstractString || a isa Symbol || a isa Tuple)) ? all(f -> deq(getfield(a, f), getfield(b, f)), fieldnames(typeof(a))) :
    isequal(a, b))
state_eq(a, b) = all(f -> f == :side || deq(getfield(a, f), getfield(b, f)), fieldnames(typeof(a)))
# I-R #3: the maps themselves, edge by edge and field by field, so that an identity map cannot pass.
other_eq(t, s, ks) = all(f -> f == :raised || f == :side || deq(getfield(t, f), getfield(s, f)), fieldnames(typeof(t))) &&
    all(f -> f in FIELDS ? all(k -> k in ks || deq(getf(t.raised, f, k), getf(s.raised, f, k)), eachindex(s.b.edges)) : deq(getfield(t.raised, f), getfield(s.raised, f)), fieldnames(typeof(t.raised)))
function permute_map_ok(s)
    t = permute(s); b = s.b; ks = Int[]
    ok = all(("m1", "m2")) do m
        all(PI) do (r, r2)
            k = edge_of(b, r, m); push!(ks, k); all(f -> deq(getf(t.raised, f, k), getf(s.raised, f, edge_of(b, r2, m))), FIELDS)
        end
    end
    ok && length(ks) == 12 && other_eq(t, s, ks)
end
transplant_map_ok(s, d) = (t = transplant(s, d); ks = targets(s.b);
    all(k -> all(f -> deq(getf(t.raised, f, k), getf(d.raised, f, k)), FIELDS), ks) && other_eq(t, s, ks))

const REC = Ref{Any}(nothing); const PRE = Ref{Any}(nothing)
LBA.CLAMP[] = (st, y) -> (REC[] === nothing || (S = REC[].s.side[st]; PRE[] = (rb = S.c.active[LC.unit(REC[].s.b, "rb")], Q = LBA.body_quantity(S.w))); (y, nothing))
LBA.ON_STEP[] = (st, o, c, y) -> (REC[] === nothing || push!(REC[].steps, (w = (a = [REC[].s.b.names[m] for m in o.acting]; isempty(a) ? "none" : only(a)), d = collect(o.d), rb = PRE[].rb, Q = PRE[].Q)))
function trial(s, p, sch)
    st = AS.initial_state(s, p); REC[] = (s = s, steps = Any[]); death = nothing
    for t in 1:H; AS.step!(st, s, p, sch, Set{Int}()); (isempty(LBA.body_sites(s.side[st].w)) && death === nothing) && (death = t); end
    x = REC[].steps; REC[] = nothing; delete!(s.side, st)
    on = [z for z in x if z.rb]; off = [z for z in x if !z.rb]
    Dict("death" => death, "intake_steps" => count(z -> any(>(0), z.d), x), "living" => length(x),
         "m0_on" => count(z -> z.w == "m0", on), "n_on" => length(on), "m0_off" => count(z -> z.w == "m0", off), "n_off" => length(off),
         "first32" => [z.w for z in x[1:min(32, end)]], "record" => [(z.w, z.d, z.Q) for z in x])
end

res = Dict{String,Any}("spec" => "discussion/specs/S36-body-transplant.md r1", "seeds" => SEEDS, "H" => H, "runs" => Any[])
su = LBA.setup_with(H); p = su.params
ref_std = org(first(SEEDS), su, :std); ref_swp = org(first(SEEDS), su, :swap)
res["G_permute_involution"] = state_eq(permute(permute(ref_std)), ref_std)
res["G_self_transplant_state"] = state_eq(transplant(ref_std, ref_std), ref_std)
res["G_permute_map"] = permute_map_ok(ref_std) && permute_map_ok(ref_swp)
res["G_transplant_map"] = transplant_map_ok(ref_std, ref_swp) && transplant_map_ok(ref_swp, ref_std)
res["G_interventions_change_state"] = !state_eq(permute(ref_std), ref_std) && !state_eq(permute(ref_swp), ref_swp) && !state_eq(transplant(ref_std, ref_swp), ref_std)
res["schedules"] = [sch.name for sch in su.survival]
# I-R 2 #3: deq on Pend, same content in distinct objects is equal, a different E or R is not
res["G_deq_pend"] = deq([LC.Pend(1, [1, 2], [3])], [LC.Pend(1, [1, 2], [3])]) && !deq([LC.Pend(1, [1, 2], [3])], [LC.Pend(1, [1, 9], [3])]) &&
    !deq([LC.Pend(1, [1, 2], [3])], [LC.Pend(1, [1, 2], [4])]) && !isequal([LC.Pend(1, [1, 2], [3])], [LC.Pend(1, [1, 2], [3])])
for seed in SEEDS
    sStd = org(seed, su, :std); sSwp = org(seed, su, :swap)
    same_circuit = deq(sStd.raised, ref_std.raised) && deq(sSwp.raised, ref_swp.raised)   # I-R 2 #3: structural (Pend is mutable)
    variants = (("base_std", sStd), ("T0_std", transplant(sStd, sStd)), ("T1_std<-swap", transplant(sStd, sSwp)), ("T2_std", permute(sStd)),
                ("base_swap", sSwp), ("T0_swap", transplant(sSwp, sSwp)), ("T1r_swap<-std", transplant(sSwp, sStd)), ("T2r_swap", permute(sSwp)))
    for sch in su.survival, (name, s) in variants
        x = trial(s, p, sch)
        push!(res["runs"], merge(x, Dict("seed" => seed, "schedule" => sch.name, "variant" => name, "same_circuit_as_first_seed" => same_circuit)))
    end
    println("seed=$seed same circuit $same_circuit  deaths ", Dict(v => [r["death"] for r in res["runs"] if r["seed"] == seed && r["variant"] == v] for v in ("base_std", "T1_std<-swap", "T2_std", "base_swap", "T1r_swap<-std", "T2r_swap")))
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-transplant.json"))
write(out, JSON.json(res)); println("written ", out)
