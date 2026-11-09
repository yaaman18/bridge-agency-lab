# S1 (spec discussion/specs/S1-body-history.md, r3): compare the histories of body_org's circuit under the same birth state B
# (= (b, c, nz) just before step 1) with the declared difference in the nursery script only (:std vs :swap), the old rule
# (contrast = nothing, idle_first = false, every other optional rule default). Writes experiments/results-h-body-swap.json.
# Usage: cd experiments && julia --project=.. h_body_swap.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, SHA
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, ".."))
include(joinpath(@__DIR__, "curricula.jl"))

# S1-2: serialization of B, whose bytes are those of string((b, c, nz)). Every value is preceded by a 1-byte type tag
# (Bool before Int; Int64, Float64, UInt32, Int32, UInt8 each with its own tag, so no value is converted to another type);
# numbers are reinterpret(UInt8, [x]) in their own type (Mulberry's s is UInt32); arrays and strings put their length
# (UInt64, LE) before their elements; arrays, tuples and structs put the type as String(type) (length + UTF-8; for a tuple
# it is a prefix of the values). Nothing has its own tag. Fields in fieldnames order.
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
        push!(out, TAG_ARRAY); _str!(out, string(typeof(x))); _len!(out, ndims(x)); for d in size(x); _len!(out, d); end   # shape (codex I-R 6)
        for v in x; _ser!(out, v); end
    elseif isstructtype(typeof(x))
        push!(out, TAG_STRUCT); _str!(out, string(typeof(x)))
        for f in fieldnames(typeof(x)); _ser!(out, getfield(x, f)); end
    else
        error("h_body_swap: no tag for value of type $(typeof(x))")
    end
    return out
end
serialize_B(b, c, nz) = _ser!(UInt8[], (b, c, nz))
hash_B(bytes) = bytes2hex(sha256(bytes))

# S1-1b: the two arms share no mutable object (rewritten by claude-lab 2026-11-06 after codex I-R 1-3).
#  - Every object reachable from an arm's (b, c, nz) is visited, through mutable and immutable structs, tuples and arrays
#    of any eltype, with no depth limit (a visited set of mutable objects stops cycles; immutable values cannot form one).
#  - A mutable object is a mutable struct or an array (strings are excluded: ismutabletype(String) is true in Julia, but a
#    String cannot be rewritten). Each arm gives the set of objectids of its mutable objects; the arms share an object
#    iff the two sets intersect. Aliasing inside one arm is therefore not counted.
is_mut_obj(x) = !(x isa AbstractString) && (x isa AbstractArray || ismutabletype(typeof(x)))
function _collect!(ids::Dict{UInt,String}, x, path)
    if is_mut_obj(x)
        id = objectid(x)
        haskey(ids, id) && return ids
        ids[id] = path
    end
    if x isa AbstractArray
        isbitstype(eltype(x)) || for (i, v) in enumerate(x); _collect!(ids, v, "$path[$i]"); end
    elseif x isa Tuple
        for (i, v) in enumerate(x); _collect!(ids, v, "$path[$i]"); end
    elseif !(x isa AbstractString) && isstructtype(typeof(x)) && !isbitstype(typeof(x))
        for f in fieldnames(typeof(x)); isdefined(x, f) && _collect!(ids, getfield(x, f), "$path.$f"); end
    end
    ids
end
mutable_ids(arm) = (ids = Dict{UInt,String}(); for r in (:b, :c, :nz); _collect!(ids, getfield(arm, r), "$r"); end; ids)
"""Paths (in arm A) of the mutable objects that both arms reach."""
function shared_paths(A, B)
    ia = mutable_ids(A); ib = mutable_ids(B)
    sort([ia[id] for id in intersect(keys(ia), keys(ib))])
end

acting_patch(o, b) = [m for m in o.acting if b.patch[m] <= 2]

# An arm at B: b, c, nz built from the seed, not stepped. The hash is taken just before step 1.
function arm_start(seed)
    b = LC.newborn(false); c = LC.init(b); nz = LC.Mulberry(seed)
    B = serialize_B(b, c, nz)
    (b = b, c = c, nz = nz, B = B, hash = hash_B(B))
end

# The procedure of eval_body_bin3.jl raise(seed; contrast = nothing, idle = false, cur = :std), on an arm already at B.
function run_arm(arm, cur)
    b, c, nz = arm.b, arm.c, arm.nz
    script = curriculum(cur)
    acts = Dict("m1" => 0, "m2" => 0)
    for (i, y) in enumerate(script)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = nothing, idle_first = false)
        i > 400 || continue
        for m in acting_patch(o, b); acts[b.names[m]] += 1; end
    end
    conf_in(m) = [b.names[a] for (k, (a, cc, _)) in enumerate(b.edges) if cc == LC.unit(b, m) && b.kind[a] == 'R' && c.q[k] >= 1]
    (hash = arm.hash, after_bytes = serialize_B(b, c, nz), after = hash_B(serialize_B(b, c, nz)), acts = acts,
     conf = Dict("m1" => conf_in("m1"), "m2" => conf_in("m2")), script = script)
end

const RULES = (contrast = nothing, idle_first = false, explore = true, fail = true, memory = true, orient = true,
               core_gate = false, seen_both = false, sed_fade = false, noise = "Mulberry(seed)",
               partner = "newborn(false)", silent = "Set{Int}()", gesture = 0.0)

# Negative controls (codex I-R 3). Must be detected: a shared array at b.q0, at c.q, a shared array reached only through
# an immutable struct, and a shared object deep inside an array of references (c.pend). Must be allowed: an alias inside
# one arm only (A.c.q === A.b.q0).
struct ImmBox; v::Vector{Int}; end
function negative_control(seed)
    out = Dict{String,Any}()
    A = arm_start(seed); B = arm_start(seed); out["clean"] = shared_paths(A, B)
    A = arm_start(seed); B = arm_start(seed); B.b.q0 = A.b.q0; out["b.q0"] = shared_paths(A, B)
    A = arm_start(seed); B = arm_start(seed); B.c.q = A.c.q; out["c.q"] = shared_paths(A, B)
    v = [1, 2, 3]
    A = merge(arm_start(seed), (nz = (A0 = arm_start(seed).nz, box = ImmBox(v)),))
    B = merge(arm_start(seed), (nz = (A0 = arm_start(seed).nz, box = ImmBox(v)),))
    out["through_immutable"] = shared_paths(A, B)
    A = arm_start(seed); B = arm_start(seed); pd = LC.Pend(0, [1], [2]); push!(A.c.pend, pd); push!(B.c.pend, pd)
    out["deep_pend"] = shared_paths(A, B)
    A = arm_start(seed); B = arm_start(seed); A.c.q = A.b.q0; out["alias_in_one_arm"] = shared_paths(A, B)
    out["detected"] = isempty(out["clean"]) && !isempty(out["b.q0"]) && !isempty(out["c.q"]) &&
                      !isempty(out["through_immutable"]) && !isempty(out["deep_pend"]) && isempty(out["alias_in_one_arm"])
    out
end

res = Dict{String,Any}()
res["spec"] = "discussion/specs/S1-body-history.md r3"
res["rules"] = RULES
res["seeds"] = Int[]
nc = negative_control(1)
res["negative_control_detected"] = nc["detected"]
res["negative_control"] = Dict("seed" => 1, nc...)
for seed in 1:10
    # S1-1b: both actual arms built to B (before step 1), checked, then stepped.
    A = arm_start(seed); W = arm_start(seed)
    shared = shared_paths(A, W)
    a = run_arm(A, :std); s = run_arm(W, :swap)
    # S1-5: :std once more with the same seed
    again = run_arm(arm_start(seed), :std)
    s_diff = [i for i in 1:800 if a.script[i] != s.script[i]]
    school = [i for i in 401:800 if a.script[i] != s.script[i]]
    push!(res["seeds"], seed)
    res["seed_$seed"] = Dict(
        "B_std" => a.hash, "B_swap" => s.hash, "B_equal" => A.B == W.B,                              # S1-2
        "shared_paths" => shared, "no_shared" => isempty(shared),                                  # S1-1b
        "script_len" => Dict("std" => length(a.script), "swap" => length(s.script)),
        "script_diff" => s_diff, "school_diff" => school, "diff_in_nursery_only" => isempty(school) && !isempty(s_diff),
        "replay_std" => Dict("acts_equal" => again.acts == a.acts, "conf_equal" => again.conf == a.conf,
                             "B_after_equal" => again.after_bytes == a.after_bytes, "B_after_hash" => a.after),   # S1-5
        "school_acts" => Dict("std" => a.acts, "swap" => s.acts),                                  # S1-6 (a)
        "conf" => Dict("std" => a.conf, "swap" => s.conf),                                         # S1-6 (b)
    )
    r = res["seed_$seed"]
    println(rpad("seed $seed", 10), " B eq ", r["B_equal"], " shared ", length(shared), " sdiff ", length(s_diff),
            " school ", length(school), " replay ",
            (r["replay_std"]["acts_equal"], r["replay_std"]["conf_equal"], r["replay_std"]["B_after_equal"]),
            " acts std ", a.acts, " swap ", s.acts, " conf std ", a.conf, " swap ", s.conf)
end
write(joinpath(LAB, "experiments", "results-h-body-swap.json"), JSON.json(res, 2))
println("written experiments/results-h-body-swap.json")
