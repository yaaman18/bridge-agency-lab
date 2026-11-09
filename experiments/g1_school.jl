# S44 (spec discussion/specs/S44-g1-school.md r3): the generator G1 = r5's rng Mulberry(s) and the school's label order pi_s
# (Fisher-Yates with Mulberry(1_000_003 * s)), the same pi_s for both arms. RB (fork.jl's org) raised on curriculum(arm, pi_s):
# M1 the raised type, M2 survival at H 392 for the 4 schedules, M3 paired differences, M4 SQ1 with the old rule, the counts.
# Shared files are not edited: the G1 curriculum and the RB org with it are built here (gate: pi = nothing is bit-identical
# to LBA.curriculum / LBA.BodyOrg). Writes experiments/results-g1-school.json (OUT).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const AS = LBA.AS

const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(511:540, ",")), ",")))
const H = 392
const L52 = [5.0, 2.0]; const L25 = [2.0, 5.0]

# ---------------------------------------------------------------- the school of BO_CUR[401:800]: positions and labels
const SCHOOL = LC.BO_CUR[401:800]
const STARTS = collect(1:15:400)                       # 27 blocks: 26 of 15 steps and the last of 10
const LENS = [min(15, 400 - a + 1) for a in STARTS]
const LABELS0 = [SCHOOL[a] for a in STARTS]            # the original labels ([5,2] first, alternating)
@assert all(all(SCHOOL[j] == SCHOOL[a] for j in a:a+LENS[k]-1) for (k, a) in enumerate(STARTS))
@assert count(==(L52), LABELS0) == 14 && count(==(L25), LABELS0) == 13 && length(LABELS0) == 27

"""pi_s: the labels of the 27 school blocks shuffled by Fisher-Yates with Mulberry(1_000_003 * s) (spec §0)."""
function school_perm(s::Integer)
    r = LC.Mulberry(1_000_003 * s); lab = copy(LABELS0)
    for i in 27:-1:2
        j = 1 + floor(Int, r() * i); lab[i], lab[j] = lab[j], lab[i]
    end
    lab
end
"""The school with the labels `lab` on the original positions and lengths."""
school_of(lab) = reduce(vcat, [fill(lab[k], LENS[k]) for k in eachindex(lab)])
"""curriculum(kind, pi): the nursery of LBA.curriculum(kind), the school with the labels pi (nothing = LBA.curriculum(kind))."""
curriculum_g1(kind::Symbol, perm) = perm === nothing ? LBA.curriculum(kind) : vcat(LBA.curriculum(kind)[1:400], school_of(perm))

# ---------------------------------------------------------------- the RB org (fork.jl's settings) raised on curriculum_g1
const KW = (structure = :constituents, idle_first = true, contrast = :bin3, core_gate = true, sed_fade = true, KC_trial = 0.0015,
            rest = true, rest_body = :B)
org_ref(seed, su, cur) = LBA.BodyOrg(seed; abundant_r0 = su.choice_params.resource0, cur = cur, KW...)
"""As LBA.BodyOrg's non-grow branch (variant_horizon.jl:82-86) with the curriculum replaced (perm = nothing: the same)."""
function org_g1(seed, su, cur, perm)
    b = LC.newborn(false; rest = KW.rest, rest_body = KW.rest_body); c = LC.init(b); noise = LC.Mulberry(seed)
    for y in curriculum_g1(cur, perm)
        LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = KW.contrast, idle_first = KW.idle_first, core_gate = KW.core_gate,
                 seen_both = false, sed_fade = KW.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[])
    end
    motors = Dict(LC.unit(b, "m1") => 1, LC.unit(b, "m2") => 2)
    LBA.BodyOrg(copy(b.names), copy(b.edges), motors, b, c, noise, KW.structure, su.choice_params.resource0, 0.02, 0.004, KW.idle_first,
                KW.contrast, KW.core_gate, false, KW.sed_fade, false, Float64(KW.KC_trial), nothing, nothing, Float64[], IdDict())
end

deq(a, b) = typeof(a) == typeof(b) && (a isa AbstractDict ? (keys(a) == keys(b) && all(k -> deq(a[k], b[k]), keys(a))) : a isa AbstractArray ? (size(a) == size(b) && all(deq(x, y) for (x, y) in zip(a, b))) :
    (isstructtype(typeof(a)) && !(a isa Number || a isa AbstractString || a isa Symbol || a isa Tuple)) ? all(f -> deq(getfield(a, f), getfield(b, f)), fieldnames(typeof(a))) : isequal(a, b))
same_org(x, y) = all(f -> f == :side || deq(getfield(x, f), getfield(y, f)), fieldnames(typeof(x)))

# ---------------------------------------------------------------- M1 the raised type (spec §3)
edge_q(b, c, r, m) = (k = findfirst(e -> e[1] == LC.unit(b, r) && e[2] == LC.unit(b, m), b.edges); k === nothing ? 0 : c.q[k])
"""qv = (m1 <- r1, r2, r7, r8), (m2 <- r1, r2, r7, r8)."""
function rtype(m1, m2)
    cross = m1[2] > m1[1] && m1[4] > m1[3] && m2[1] > m2[2] && m2[3] > m2[4]
    nocross = m1[1] > m1[2] && m1[3] > m1[4] && m2[2] > m2[1] && m2[4] > m2[3]
    @assert !(cross && nocross)
    cross ? "cross" : nocross ? "nocross" : "other"
end
qvec(s) = ([edge_q(s.b, s.raised, r, "m1") for r in ("r1", "r2", "r7", "r8")], [edge_q(s.b, s.raised, r, "m2") for r in ("r1", "r2", "r7", "r8")])

# ---------------------------------------------------------------- M2 survival and the r5-free trajectory
function trial(s, p, sch)
    st = AS.initial_state(s, p); S = s.side[st]; R5 = LC.unit(s.b, "r5"); tr = Vector{Vector{Bool}}()
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        push!(tr, [st.active[u] for u in eachindex(st.active) if u != R5])
    end
    (alive = !st.dead, traj = string(hash(tr)), Q_H = LBA.body_quantity(S.w))
end

# ---------------------------------------------------------------- M4 SQ1: the old rule (eval_body_bin3.jl raise, contrast nothing, idle off)
function sq1(seed, cur, perm)
    b = LC.newborn(false); c = LC.init(b); nz = LC.Mulberry(seed); acts = Dict("m1" => 0, "m2" => 0)
    for (i, y) in enumerate(curriculum_g1(cur, perm))
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = nothing, idle_first = false)
        i > 400 || continue
        for m in o.acting; b.patch[m] <= 2 && (acts[b.names[m]] += 1); end
    end
    acts
end

# ---------------------------------------------------------------- run
su = LBA.setup_with(H); p = su.params
gate_id = Dict{String,Any}()
for cur in (:std, :swap)   # gate: pi = nothing is the shared curriculum and org, bit for bit (seed 1)
    gate_id["curriculum_$cur"] = curriculum_g1(cur, nothing) == LBA.curriculum(cur) && curriculum_g1(cur, LABELS0) == LBA.curriculum(cur)
    gate_id["org_$cur"] = same_org(org_g1(1, su, cur, nothing), org_ref(1, su, cur))
end
res = Dict{String,Any}("spec" => "discussion/specs/S44-g1-school.md r3", "seeds" => SEEDS, "H" => H, "gate_identity" => gate_id,
                       "labels0" => LABELS0, "lens" => LENS, "runs" => Any[])
println("identity gate ", gate_id)
for seed in SEEDS
    perm = school_perm(seed)
    row = Dict{String,Any}("seed" => seed, "perm" => perm, "tail" => perm[end] == L52 ? "52" : "25", "arms" => Dict{String,Any}())
    for cur in (:std, :swap)
        s = org_g1(seed, su, cur, perm); m1, m2 = qvec(s)
        tr = Dict(sch.name => (x = trial(s, p, sch); Dict("alive" => x.alive, "traj" => x.traj, "Q_H" => x.Q_H)) for sch in su.survival)
        row["arms"][String(cur)] = Dict("perm_used" => perm, "q_m1" => m1, "q_m2" => m2, "type" => rtype(m1, m2),
            "raise" => string(hash((s.raised.q, s.raised.sg, s.raised.lastM))), "trials" => tr, "sq1" => sq1(seed, cur, perm))
    end
    push!(res["runs"], row)
    a = row["arms"]
    println("seed=$seed tail=$(row["tail"]) std $(a["std"]["type"]) $(count(v -> v["alive"], values(a["std"]["trials"])))/4 sq1 $(a["std"]["sq1"])",
            " | swap $(a["swap"]["type"]) $(count(v -> v["alive"], values(a["swap"]["trials"])))/4 sq1 $(a["swap"]["sq1"])")
end
out = get(ENV, "OUT", joinpath(@__DIR__, "results-g1-school.json"))
write(out, JSON.json(res)); println("written ", out)
