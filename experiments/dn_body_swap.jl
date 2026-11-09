# S2 (spec discussion/specs/S2-body-dn.md, r2): the same contract as S1 (the same birth state B, the same law, the nursery
# script the only declared difference) with the two arms (:std vs :swap) carried into the same body stage, measuring D and N
# (AGENCY-001) with AS.evaluate and the old rule (contrast = nothing, idle_first = false, core_gate = false),
# structure = :constituents, H = 294, 392, 588. Writes experiments/results-dn-body-swap.json (RULE=old, the default) or
# experiments/results-dn-body-swap-current.json (RULE=current: bin3 + idle_first + core gate, spec S3 r2 S3-1).
# Usage: cd experiments && julia --project=.. dn_body_swap.jl; RULE=current SEEDS=1 HORIZONS=392 for a short run.
include(joinpath(@__DIR__, "variant_horizon.jl"))   # LabBodyAgency; its own runs are under PROGRAM_FILE (not run here)
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const ASC = LBA.AS
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

# S1-2 serialization, copied from experiments/h_body_swap.jl (_ser!, _len!, _str!, the tags): every value is preceded by a
# 1-byte type tag (Bool before Int); numbers are reinterpret(UInt8, [x]) in their own type; arrays and strings put their
# length (UInt64, LE) before their elements; arrays, tuples and structs put the type as String(type); Nothing has its own
# tag. Fields in fieldnames order.
const TAG_NOTHING = 0x00; const TAG_INT64 = 0x01; const TAG_FLOAT64 = 0x02; const TAG_BOOL = 0x03; const TAG_CHAR = 0x04
const TAG_STRING = 0x05; const TAG_ARRAY = 0x06; const TAG_STRUCT = 0x07; const TAG_TUPLE = 0x08
const TAG_UINT32 = 0x09; const TAG_INT32 = 0x0a; const TAG_UINT8 = 0x0b
function _len!(out::Vector{UInt8}, n)
    append!(out, reinterpret(UInt8, [UInt64(n)])); return out
end
function _str!(out::Vector{UInt8}, s)
    u = codeunits(s); _len!(out, length(u)); append!(out, u); return out
end
function _ser!(out::Vector{UInt8}, x)
    if x === nothing
        push!(out, TAG_NOTHING)
    elseif x isa Bool
        push!(out, TAG_BOOL); push!(out, UInt8(x))
    elseif x isa Int64
        push!(out, TAG_INT64); append!(out, reinterpret(UInt8, [x]))
    elseif x isa Float64
        push!(out, TAG_FLOAT64); append!(out, reinterpret(UInt8, [x]))
    elseif x isa UInt32
        push!(out, TAG_UINT32); append!(out, reinterpret(UInt8, [x]))
    elseif x isa Int32
        push!(out, TAG_INT32); append!(out, reinterpret(UInt8, [x]))
    elseif x isa UInt8
        push!(out, TAG_UINT8); append!(out, reinterpret(UInt8, [x]))
    elseif x isa Char
        push!(out, TAG_CHAR); append!(out, reinterpret(UInt8, [UInt32(x)]))
    elseif x isa AbstractString
        push!(out, TAG_STRING); _str!(out, String(x))
    elseif x isa Tuple
        push!(out, TAG_TUPLE); _str!(out, string(typeof(x)))
        for v in x; _ser!(out, v); end
    elseif x isa AbstractArray
        push!(out, TAG_ARRAY); _str!(out, string(typeof(x))); _len!(out, ndims(x)); for d in size(x); _len!(out, d); end
        for v in x; _ser!(out, v); end
    elseif isstructtype(typeof(x))
        push!(out, TAG_STRUCT); _str!(out, string(typeof(x)))
        for f in fieldnames(typeof(x)); _ser!(out, getfield(x, f)); end
    else
        error("dn_body_swap: no tag for value of type $(typeof(x))")
    end
    return out
end

const RULE = get(ENV, "RULE", "old")
# S4-2: RULE=sf uses the seeds 21..30 by default (kept apart from 1..20, used to choose KC); old/current keep 1..10.
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", RULE == "sf" ? join(21:30, ",") : "1,2,3,4,5,6,7,8,9,10"), ","))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "294,392,588"), ","))
# S3-1: RULE = old (the rule of S2: contrast nothing, idle_first false, core_gate false) or current (bin3 + idle_first + core
# gate, the default of variant_horizon.jl). The same rule goes to the BodyOrg and to S1's procedure (grow_arm).
# S4-1: RULE = sf is current plus sed_fade = true and the BodyOrg's KC_trial = 0.0015 (the trials only; no upkeep while raised).
const ORULE = RULE in ("current", "sf") ? (contrast = :bin3, idle_first = true, core_gate = true) :
              RULE == "old" ? (contrast = nothing, idle_first = false, core_gate = false) :
              error("dn_body_swap: RULE must be old, current or sf, got $RULE")
# S4-1: sf (false and 0.0 for old/current, so their records stay as they were)
const SEDFADE = RULE == "sf"
const KCTRIAL = RULE == "sf" ? 0.0015 : 0.0
# S3-1: the rule in use is written under "rules" (RULE=old keeps the S2 record byte for byte, so no "rule" key there;
# the current record adds "rule" => "current"; S4-1: the sf record adds rule, sed_fade and KC_trial).
const RULES = merge((contrast = ORULE.contrast, idle_first = ORULE.idle_first, core_gate = ORULE.core_gate,
               structure = :constituents, cur = :std, seed_steps = 800),
              RULE == "current" ? (rule = RULE,) :
              RULE == "sf" ? (rule = RULE, sed_fade = SEDFADE, KC_trial = KCTRIAL) : (;))
const OUTFILE = RULE == "current" ? "results-dn-body-swap-current.json" :
                RULE == "sf" ? "results-dn-body-swap-sf.json" : "results-dn-body-swap.json"

# S1 procedure, on a fresh circuit: b = newborn(false), c = init(b), nz = Mulberry(seed), then 800 steps of curriculum(cur)
# under the selected rule (S4-1: with sed_fade in sf); the serialization of (b, c, nz) after the 800 steps.
function grow_arm(seed, cur)
    b = LC.newborn(false); c = LC.init(b); nz = LC.Mulberry(seed)
    for y in LBA.curriculum(cur)
        LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = ORULE.contrast, idle_first = ORULE.idle_first, core_gate = ORULE.core_gate,
                 sed_fade = SEDFADE)
    end
    (b = b, c = c, nz = nz)
end

# S4-1: sf builds the BodyOrg with sed_fade = true and KC_trial = 0.0015 (both recorded under "rules"); the sed_fade is read
# back off each BodyOrg for both arms (S4-1 check).
# S2-1: the BodyOrg's raised and noise against S1's c and nz (byte-equal), and every other field of BodyOrg compared
# between the two arms (the side is empty before the evaluation and is never serialized; it is checked empty separately).
org_field_names() = [f for f in fieldnames(LBA.BodyOrg) if f ∉ (:raised, :noise, :side)]
org_field_bytes(s, f) = (x = getfield(s, f); try _ser!(UInt8[], (x,)) catch; _ser!(UInt8[], string(x)) end)

# S2-2: the start of the body stage, the parts formed by the raising excluded: the world w and the pool of s.side[st] (the
# setup su is one shared object for both arms, so it is the same by construction; its bytes are recorded once).
side_bytes(s, st) = (S = s.side[st]; (w = _ser!(UInt8[], S.w), pool = _ser!(UInt8[], S.pool)))
"""The side entries kept by the BodyOrg (AS.evaluate/initial_state may leave one)."""
all_side_bytes(s) = [(w = _ser!(UInt8[], S.w), pool = _ser!(UInt8[], S.pool)) for S in values(s.side)]

# S2-4 / S2-5: the observations of AS.evaluate for one arm, and the reading of N (T empty = the guard; otherwise tested).
function observe(s, su)
    r = ASC.evaluate(s, su)
    T = r.value_tracking
    nclass = isempty(T) ? "guard_false" : (r.value_needed ? "tested_true" : "tested_false")
    (; choices = Dict(k => join(v, ",") for (k, v) in r.choices), differentiated = r.differentiated,
       value_tracking = sort(T), value_needed = r.value_needed, N = nclass,
       survival = Dict(k => (v ? 1 : 0) for (k, v) in r.survival),
       survival_without_tracking = Dict(k => (v ? 1 : 0) for (k, v) in r.survival_without_tracking),
       alive_somewhere = r.alive_somewhere, value_tracking_measured = sort(r.value_tracking_measured),
       core = sort(r.core), core_enables_action = r.core_enables_action, agency = r.agency)
end
# the parts of su that AS.evaluate reads (templates hold substrates with UInt64 keys, for which S1's tag set has no tag)
su_bytes(su) = _ser!(UInt8[], (su.params, su.choice_params, su.survival, su.choice, su.choice_window))
function fresh(seed, H, su; cur = :std)
    s = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0,
                    idle_first = ORULE.idle_first, contrast = ORULE.contrast, cur = cur, core_gate = ORULE.core_gate,
                    sed_fade = SEDFADE, KC_trial = KCTRIAL)
    st = ASC.initial_state(s, su.choice_params)
    (s = s, st = st, side = side_bytes(s, st))
end

# negative controls (seed 1, H = 392); they show the checks work, not that the contract is complete
function negative_control(seed, H)
    su = LBA.setup_with(H)
    out = Dict{String,Any}()
    # (i) the world of one arm's body start, w.C[1] + 1: S2-2 must detect it
    A = fresh(seed, H, su; cur = :std); W = fresh(seed, H, su; cur = :swap)
    W.s.side[W.st].w.C[1] += 1
    a = side_bytes(A.s, A.st); w = side_bytes(W.s, W.st)
    out["i_world_shift"] = Dict("detected" => !(a.w == w.w && a.pool == w.pool), "world_equal" => a.w == w.w, "pool_equal" => a.pool == w.pool)
    # (ii) MCOST of one arm changed (and the BodyOrg rebuilt): S2-1's field comparison must detect it
    A = fresh(seed, H, su; cur = :std); W = fresh(seed, H, su; cur = :swap)
    S = W.s; Wc = LBA.BodyOrg(S.names, S.edges, S.motors, S.b, S.raised, S.noise, S.structure, S.abundant_r0, S.U, S.MCOST + 0.001,
                              S.idle_first, S.contrast, S.core_gate, S.seen_both, S.sed_fade, S.grow, S.KC, S.PER, S.w0, S.pool0, IdDict())
    fields = [String(f) for f in org_field_names() if org_field_bytes(A.s, f) != org_field_bytes(Wc, f)]
    out["ii_mcost"] = Dict("detected" => !isempty(fields), "fields_differ" => fields)
    # (iii) nothing done: still equal
    A = fresh(seed, H, su; cur = :std); W = fresh(seed, H, su; cur = :swap)
    a = side_bytes(A.s, A.st); w = side_bytes(W.s, W.st)
    out["iii_clean"] = Dict("equal" => a.w == w.w && a.pool == w.pool)
    out["detected"] = out["i_world_shift"]["detected"] && out["ii_mcost"]["detected"] && out["iii_clean"]["equal"]
    out
end

res = Dict{String,Any}()
res["spec"] = "discussion/specs/S2-body-dn.md r2"
res["rules"] = RULES
res["horizons"] = HS
res["seeds"] = SEEDS
res["templates_sha256"] = ASC.load_templates().sha256
res["runs"] = Any[]
const SU = Dict(H => LBA.setup_with(H) for H in HS)
for H in HS
    su = SU[H]
    for seed in SEEDS
        # S2-1: the two BodyOrgs (the selected rule) and S1's procedure
        stdo = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0,
                           idle_first = ORULE.idle_first, contrast = ORULE.contrast, cur = :std, core_gate = ORULE.core_gate,
                           sed_fade = SEDFADE, KC_trial = KCTRIAL)
        swao = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0,
                           idle_first = ORULE.idle_first, contrast = ORULE.contrast, cur = :swap, core_gate = ORULE.core_gate,
                           sed_fade = SEDFADE, KC_trial = KCTRIAL)
        gs = grow_arm(seed, :std); gw = grow_arm(seed, :swap)   # S1's b, c and nz after 800 steps under the selected rule, each arm
        s1_std = _ser!(UInt8[], (gs.b, gs.c, gs.nz)); s1_swap = _ser!(UInt8[], (gw.b, gw.c, gw.nz))
        raised_std = _ser!(UInt8[], stdo.raised); raised_swap = _ser!(UInt8[], swao.raised)
        noise_std = _ser!(UInt8[], stdo.noise); noise_swap = _ser!(UInt8[], swao.noise)
        fields_differ = [String(f) for f in org_field_names() if org_field_bytes(stdo, f) != org_field_bytes(swao, f)]
        S21 = (raised_equal = raised_std == raised_swap, noise_equal = noise_std == noise_swap,
               std_matches_s1 = _ser!(UInt8[], (stdo.b, stdo.raised, stdo.noise)) == s1_std,
               swap_matches_s1 = _ser!(UInt8[], (swao.b, swao.raised, swao.noise)) == s1_swap,
               fields_differ, fields_equal = isempty(fields_differ), side_empty = isempty(all_side_bytes(stdo)) && isempty(all_side_bytes(swao)))
        # S2-1: each arm's raised and noise are S1's c and nz grown "from the same seed and arm" (so :std and :swap differ
        # exactly where S1's histories differ); the other fields must not differ between the arms (codex S-R 1), but the
        # circuit b is the same object S1 stepped, so it is compared under fields_differ too.
        S21 = merge(S21, (; ok = S21.std_matches_s1 && S21.swap_matches_s1 && S21.fields_equal && S21.side_empty))
        # S2-2: a fresh BodyOrg of each arm, the body started, the start compared (w, pool); su is shared and serialized once
        A = fresh(seed, H, su; cur = :std); W = fresh(seed, H, su; cur = :swap)
        S22 = (world_equal = A.side.w == W.side.w, pool_equal = A.side.pool == W.side.pool,
               su_serialized = su_bytes(su))
        # su: both arms get the same object, so it is compared to a fresh setup_with(H) (the template bytes beside it)
        su_fresh = LBA.setup_with(H)
        S22 = merge(S22, (; su_equal = su_bytes(su) == su_bytes(su_fresh) && su.sha256 == su_fresh.sha256))
        S22 = merge(S22, (; ok = S22.world_equal && S22.pool_equal && S22.su_equal))
        # S2-4 / S2-5: evaluate each arm (std first), then rebuild and re-evaluate (S2-7: same arm twice), and the arms in
        # the other order (S2-7: std→swap vs swap→std)
        o1 = observe(A.s, su); o2 = observe(W.s, su)
        W2 = fresh(seed, H, su; cur = :swap); A2 = fresh(seed, H, su; cur = :std)
        o3 = observe(W2.s, su); o4 = observe(A2.s, su)          # swap→std
        A3 = fresh(seed, H, su; cur = :std); W3 = fresh(seed, H, su; cur = :swap)
        o5 = observe(A3.s, su); o6 = observe(W3.s, su)          # std again, rebuilt
        S27 = (; std_rebuilt_equal = o5 == o1, swap_rebuilt_equal = o6 == o2, order_swapped_equal = o4 == o1 && o3 == o2,
                ok = o5 == o1 && o6 == o2 && o4 == o1 && o3 == o2)
        push!(res["runs"], Dict("H" => H, "seed" => seed,
            "S2_1" => Dict("raised_equal" => S21.raised_equal, "noise_equal" => S21.noise_equal, "std_matches_s1" => S21.std_matches_s1,
                           "swap_matches_s1" => S21.swap_matches_s1, "fields_differ" => S21.fields_differ, "side_empty" => S21.side_empty,
                           "ok" => S21.ok),
            "S2_2" => Dict("world_equal" => S22.world_equal, "pool_equal" => S22.pool_equal,
                           "su_equal" => S22.su_equal, "su_bytes" => string(length(S22.su_serialized)), "ok" => S22.ok),
            "S2_7" => Dict("std_rebuilt_equal" => S27.std_rebuilt_equal, "swap_rebuilt_equal" => S27.swap_rebuilt_equal,
                           "order_swapped_equal" => S27.order_swapped_equal, "ok" => S27.ok),
            "obs" => Dict("std" => Dict(zip(string.(keys(o1)), Any[getfield(o1, k) for k in keys(o1)])),
                          "swap" => Dict(zip(string.(keys(o2)), Any[getfield(o2, k) for k in keys(o2)])))))
        println("H=$H seed=$seed S2-1=$(S21.ok) S2-2=$(S22.ok) S2-7=$(S27.ok) | std choices $(o1.choices) D=$(o1.differentiated) T=$(o1.value_tracking) N=$(o1.N) | swap choices $(o2.choices) D=$(o2.differentiated) T=$(o2.value_tracking) N=$(o2.N)")
    end
end
const HNC = 392
nc = negative_control(1, HNC)
res["negative_control"] = Dict("seed" => 1, "H" => HNC, nc...)
res["negative_control_detected"] = nc["detected"] === true
# S2-6 bookkeeping: the seeds that pass S2-1/S2-2/S2-7, and D / N per arm counted over those seeds only
summ = Dict{String,Any}()
for H in HS
    okruns = [x for x in res["runs"] if x["H"] == H && x["S2_1"]["ok"] && x["S2_2"]["ok"] && x["S2_7"]["ok"]]
    summ["H_$H"] = Dict("contract_seeds" => [x["seed"] for x in okruns], "excluded" => length(SEEDS) - length(okruns),
        "arms" => Dict(a => Dict("D_true" => count(x -> x["obs"][a]["differentiated"] === true, okruns),
                                 "N_guard_false" => count(x -> x["obs"][a]["N"] == "guard_false", okruns),
                                 "N_tested_false" => count(x -> x["obs"][a]["N"] == "tested_false", okruns),
                                 "N_tested_true" => count(x -> x["obs"][a]["N"] == "tested_true", okruns),
                                 "choices" => Dict{String,Int}())
                             for a in ("std", "swap")))
    for a in ("std", "swap"), x in okruns
        key = join(sort(collect(x["obs"][a]["choices"]); by = first), " ") == "" ? "" :
              join([k * "=" * v for (k, v) in sort(collect(x["obs"][a]["choices"]))], " ")
        summ["H_$H"]["arms"][a]["choices"][key] = get(summ["H_$H"]["arms"][a]["choices"], key, 0) + 1
    end
end
res["summary"] = summ
write(joinpath(LAB, "experiments", OUTFILE), JSON.json(res, 2))
println("negative control ", res["negative_control_detected"], " ", nc["i_world_shift"], " ", nc["ii_mcost"], " ", nc["iii_clean"])
println("written experiments/", OUTFILE)
