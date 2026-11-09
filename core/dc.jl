# DC of the circuit at each occurrence (canonical, after the proofs of formal/LabCircuit.lean, 2026-10-31).
# Implements `Window` and `Window.ElemDC` of the Lean file exactly; `elemDC_iff_fields` proves that ElemDC is the four
# fields of ERIEC.DC for these relations, and `dc_of_check` that a true check gives a DC certificate.
# Choices (decided by the user 2026-10-31 as recommended, formal/README.md):
#   D1 the organization layer's circuit; D2 the occurrence is a step of the common tick (assumption SHARED-TICK), the
#   window is L = smax * decay = 32 steps ending there; D3 kappa = edges with confidence >= 1 whose source is not a
#   receptor (sediment is not counted); D4 alpha declared from the world's rules (below), epsilon = coupled receptors
#   that are on (noise and clock are not coupled); the partner's gesture r9 is coupled to the call only while the
#   partner is live. D4 revised 2026-10-31 (user, item 67): the proprioceptive receptors r10/r11 read the circuit's own
#   pending calls, a state of the unity itself (internal correlation, not the medium), so no act reaches them as
#   environment and they are not in epsilon.
#   D4 revised again 2026-11-01 (user, item 69): alpha depends on the medium's state at the occurrence (Lean
#   `gatedAffects`, `labGate`): m1/m2 reach their declared features only in the world phase while their patch yields
#   (an act then takes a positive share, `allocate`: offer > 0, and the pool R decreases; the nursery and school yields
#   are scripted and no act changes them); m3 reaches r9 only while the partner is live. `alpha = :fixed` gives the
#   reading of item 67 for comparison.
# Read-only: the record is taken from step!'s outputs and the state after the step; nothing is written back.

const DC_L = P_SMAX * P_DECAY   # 32

# D4: features each motor's acts reach in the medium (feature indices of FEATURES): m1 acts on patch 1 (y1>=3, y1==0,
# y1>y2, y2>y1), m2 on patch 2 (y2>=3, y2==0, y1>y2, y2>y1), m3 (the call) on the partner's gesture while a live partner
# answers. (Until item 67 m3 also reached waiting / not waiting, features 10, 11; they are internal now.)
const ALPHA_FEATURES = Dict("m1" => [1, 3, 7, 8], "m2" => [2, 4, 7, 8], "m3" => Int[], "m0" => Int[])   # S33: m0 (rest) reaches nothing
const PARTNER_FEATURE = 9

struct DCStep
    kept::Vector{Bool}
    on::Vector{Bool}
    acted::Vector{Int}                   # motors that acted
    repro::Vector{Tuple{Int,Int}}        # (motor, edge): edge confirmed with that motor's answered act
    via::Vector{Tuple{Int,Int}}          # (receptor, edge): edge confirmed with an answered act that receptor drove
    partner_live::Bool
    in_world::Bool                       # the world phase (acts change the pools)
    ypos::NTuple{2,Bool}                 # y1 > 0, y2 > 0 at the step
end

"""The record of one step (o = step!'s result, st = the state after the step, y the yields the step read, phase the
life phase "nursery" / "school" / "world")."""
function dc_record(b::Circuit, o, st::CState; partner_live::Bool = false, y, phase::AbstractString)
    repro = Tuple{Int,Int}[]; via = Tuple{Int,Int}[]
    onpatch = [m for m in o.acting if b.patch[m] <= 2]
    if o.gate
        drivers = [b.edges[k][1] for m in onpatch for k in b.ins[m] if b.kind[b.edges[k][1]] == 'R' && o.drove[k]]
        for k in eachindex(b.edges)
            o.confirmed_patch[k] || continue
            for m in onpatch; push!(repro, (m, k)); end
            for e in drivers; push!(via, (e, k)); end
        end
    end
    if o.answered_call !== nothing
        m3 = findfirst(u -> b.patch[u] == 3, eachindex(b.patch))
        drivers = [b.edges[k][1] for k in o.answered_call.R]
        for k in o.call_confirmed
            push!(repro, (m3, k))
            for e in drivers; push!(via, (e, k)); end
        end
    end
    DCStep([q >= 1 for q in st.q], copy(st.active), copy(o.acting), unique(repro), unique(via), partner_live,
           phase == "world", (y[1] > 0, y[2] > 0))
end

"""Lean `labGate`: is motor `m`'s gate open at the step `r`?"""
function lab_gate(b::Circuit, r::DCStep, m::Int)
    p = b.patch[m]
    p == 1 ? (r.in_world && r.ypos[1]) : p == 2 ? (r.in_world && r.ypos[2]) : p == 3 ? r.partner_live : false
end

"""The window ending at record `x` (the last DC_L records), as the Lean `Window` (1-based indices). `alpha = :state`
(D4, item 69) gates each motor's declared reach by the medium's state at the occurrence; `:fixed` is item 67's."""
struct DCWindow
    kept::Vector{Bool}
    on::Vector{Bool}
    reproduced::BitMatrix     # [motor, edge]
    affects::BitMatrix        # [motor, receptor]
    via::BitMatrix            # [receptor, edge]
end
function dc_window(b::Circuit, recs::AbstractVector{DCStep}; alpha::Symbol = :state)
    n = length(b.names); ne = length(b.edges); last = recs[end]
    rep = falses(n, ne); via = falses(n, ne)
    for r in recs, (m, k) in r.repro; rep[m, k] = true; end
    for r in recs, (e, k) in r.via; via[e, k] = true; end
    aff = falses(n, n)
    for (mn, feats) in ALPHA_FEATURES
        m = unit(b, mn)
        m === nothing && continue   # S7 (2026-11-07): a circuit without this motor (BODY's newborn(false) has no m3) reaches nothing through it
        alpha === :state && !lab_gate(b, last, m) && continue
        for u in 1:n
            b.kind[u] == 'R' || continue
            b.feat[u] >= 1 || continue   # S34: the body receptor (feat -1) is reached by no motor (BP4 (i))
            f = b.perm[b.feat[u]]
            (f in feats || (mn == "m3" && f == PARTNER_FEATURE && last.partner_live)) && (aff[m, u] = true)
        end
    end
    DCWindow(copy(last.kept), copy(last.on), rep, aff, via)
end

# ---- Window.ElemDC of formal/LabCircuit.lean, clause by clause ----
ismotor(b, u) = b.kind[u] == 'M'
isreceptor(b, u) = b.kind[u] == 'R'
selfedge(b, k) = !isreceptor(b, b.edges[k][1])
coupled(b, w, e) = any(m -> ismotor(b, m) && w.affects[m, e], eachindex(b.names))
enables(b, w, k, m) = ismotor(b, m) && (b.edges[k][2] == m ||
    any(k2 -> w.kept[k2] && b.edges[k2][1] == b.edges[k][2] && b.edges[k2][2] == m, eachindex(b.edges)))

function elem_self(b, w)
    K = eachindex(b.edges); U = eachindex(b.names)
    all(k -> !(w.kept[k] && selfedge(b, k)) ||
        any(k2 -> w.kept[k2] && selfedge(b, k2) && any(m -> enables(b, w, k2, m) && w.reproduced[m, k], U), K), K)
end
function elem_smc(b, w)
    U = eachindex(b.names); K = eachindex(b.edges)
    all(e -> !(isreceptor(b, e) && w.on[e] && coupled(b, w, e)) ||
        any(e2 -> isreceptor(b, e2) && w.on[e2] && coupled(b, w, e2) &&
            any(m -> ismotor(b, m) && any(k -> w.kept[k] && b.edges[k][1] == e2 && b.edges[k][2] == m, K) && w.affects[m, e], U), U), U)
end
function elem_act(b, w)
    U = eachindex(b.names); K = eachindex(b.edges)
    any(m -> ismotor(b, m) &&
        any(k -> w.kept[k] && selfedge(b, k) && enables(b, w, k, m), K) &&
        any(e -> isreceptor(b, e) && w.on[e] && coupled(b, w, e) &&
            any(k -> w.kept[k] && b.edges[k][1] == e && b.edges[k][2] == m, K), U), U)
end
elem_bound(b, w) = any(k -> w.kept[k] && selfedge(b, k) && ismotor(b, b.edges[k][2]), eachindex(b.edges))

"""The four clauses and the verdict (Lean `Window.checkDC`)."""
function check_dc(b::Circuit, w::DCWindow)
    s, m, a, d = elem_self(b, w), elem_smc(b, w), elem_act(b, w), elem_bound(b, w)
    (self = s, smc = m, act = a, bound = d, dc = s && m && a && d)
end

# ---- G9 (gaps C): νΦ of the window as the greatest fixed point (formal/LabCircuit.lean Window.phiFin / nuFin, nuFin_eq) ----
"""Φ(Y) on edge sets: the edges re-produced by a motor that some edge of Y enables (Lean `Window.phiFin`)."""
phi_fin(b, w, Y::BitVector) = BitVector([any(m -> ismotor(b, m) && w.reproduced[m, k] && any(c -> Y[c] && enables(b, w, c, m), eachindex(b.edges)), eachindex(b.names)) for k in eachindex(b.edges)])
"""νΦ by nK iterations from all edges (Lean `Window.nuFin`; equal to `Closure.nu (Phi piRel rhoRel)` by `nuFin_eq`)."""
function nu_fin(b, w)
    Y = trues(length(b.edges))
    for _ in 1:length(b.edges); Y = phi_fin(b, w, Y); end
    Y
end
"""The structural value counted on νΦ (Lean `Window.valueGfp`): |{k : via[e, k]} ∩ νΦ|."""
value_gfp(b, w, nu::BitVector, e::Int) = count(k -> w.via[e, k] && nu[k], eachindex(b.edges))
"""The structural value counted on κ (Lean `nuPhiOf` = kept self edges, used in S15/S17)."""
value_kappa(b, w, e::Int) = count(k -> w.via[e, k] && w.kept[k] && selfedge(b, k), eachindex(b.edges))
