# One life with death as an absorbing state (S48, discussion/specs/S48-one-life.md r2; formal/OneLife.lean).
# The state of one life on the path raised with the body (body_org_run "ORG", RAISE "body"): circuit state, wiring,
# perm, noise state (an integer), the material world (with its port), pools, step t, dead, death. One step is
# onelife_step(state, drive) -> (state, error); the drive is the pair of scheduled yields in {0..5}^2. Each law (L2,
# L2+SF) has its own step method with its constants closed in the body. The living step keeps the order and the
# floating-point arithmetic of body_org_run (core/body_org.jl:85-141). Diagnostics (win, form, logv, sums) are not kept.
# Standalone: includes LabCore from outside (core/LabCore.jl is not changed).

isdefined(Main, :LabCore) || include(joinpath(@__DIR__, "LabCore.jl"))
using .LabCore
import .LabCore: CState, Pend, Circuit, World, Port, port_take!, port_give!, state_int32
using SHA

struct LawL2 end     # bin3 + IDLE + GATE
struct LawL2SF end   # L2 + SEDFADE

struct OneLife{L}
    circuit::CState
    b::Circuit
    perm::Vector{Int}
    noise::Int                    # Mulberry state as the JavaScript int32 (state_int32)
    w::World
    pool::Vector{Float64}
    t::Int
    dead::Bool
    death::Union{Nothing,Int}
end

# Birth (body_org.jl:67-74 with cond "ORG", RAISE "body", no DROPR, no EXTRA). perm is not aliased with b.perm
# (the existing run aliases them; nothing changes perm on this path, REVR is not used).
function onelife_birth(seed::Integer, law)
    L = law isa Type ? law : typeof(law)
    (L === LawL2 || L === LawL2SF) || error("unknown law $law")
    w = make_world(; reservoir = 300.0); seed!(w, 12, 12, 1)
    pool = [0.0, 0.0]
    perm = collect(1:length(FEATURES))
    b = newborn(false; perm = copy(perm), extra = Int[])
    circuit = init(b); noise = Mulberry(seed)
    return OneLife{L}(circuit, b, perm, state_int32(noise), w, pool, 0, false, nothing)
end

_drive_ok(g) = (g isa Union{Tuple,AbstractVector}) && length(g) == 2 && all(x -> x isa Integer && 0 <= x <= 5, g)
_empty_body(s::OneLife) = all(==(0), s.w.C)
# Detection at the start of the step: dead is set, death = t, nothing else changes (t does not advance).
_detect(s::OneLife{L}) where {L} = (c = deepcopy(s); OneLife{L}(c.circuit, c.b, c.perm, c.noise, c.w, c.pool, c.t, true, c.t))

# The living step of body_org_run (cond "ORG", PER/READCUR/REVR/DROPR/SEEN off), on a deep copy of the input.
function _live(s::OneLife{L}, g, U::Float64, MCOST::Float64, KC::Float64, contrast::Symbol, idle_first::Bool,
               core_gate::Bool, sed_fade::Bool) where {L}
    c = deepcopy(s)
    circuit = c.circuit; b = c.b; w = c.w; pool = c.pool; noise = Mulberry(c.noise)
    y = [min(5.0, floor(r / U + 1e-9)) for r in pool]
    body = [i for i in eachindex(w.C) if w.C[i] != 0]
    out = step!(circuit, b, [y[1], y[2], 0.0]; noise = noise, contrast = contrast, idle_first = idle_first, core_gate = core_gate,
                seen_both = false, sed_fade = sed_fade)
    acting = [b.patch[m] for m in out.acting if b.patch[m] <= 2]; d = out.d
    nk = count(k -> circuit.q[k] >= 1 || circuit.sg[k] >= 1, eachindex(circuit.q))
    cost = KC * nk; paid = 0.0
    for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
    port_give!(w.port, paid)
    if !isempty(acting)
        for k in 1:2
            if d[k] > 0
                take = min(pool[k], d[k] * U); pool[k] -= take
                for i in body; w.A[i] += take / length(body); end
            end
        end
        cost = MCOST * length(acting); paid = 0.0
        for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
        port_give!(w.port, paid)
    end
    for k in 1:2
        pool[k] += port_take!(w.port, Float64(g[k]) * U); over = pool[k] - 50 * U
        if over > 0; pool[k] -= over; port_give!(w.port, over); end
    end
    step!(w, ())
    return OneLife{L}(circuit, b, c.perm, state_int32(noise), w, pool, c.t + 1, false, nothing)
end

# One step (S48 §3.2 order): (1) dead: returned as it is, the drive is not read; (2) every site empty: detection;
# (3) a drive out of {0..5}^2: error, the state unchanged; (4) the living step. Returns (state, error).
function onelife_step(s::OneLife{LawL2}, g)
    s.dead && return (deepcopy(s), false)
    _empty_body(s) && return (_detect(s), false)
    _drive_ok(g) || return (deepcopy(s), true)
    return (_live(s, g, 0.02, 0.004, 0.002, :bin3, true, true, false), false)
end
function onelife_step(s::OneLife{LawL2SF}, g)
    s.dead && return (deepcopy(s), false)
    _empty_body(s) && return (_detect(s), false)
    _drive_ok(g) || return (deepcopy(s), true)
    return (_live(s, g, 0.02, 0.004, 0.002, :bin3, true, true, true), false)
end

# Read-only: the patch acts of the last living step (the acting patch motors, in unit order = out.acting).
onelife_acts(s::OneLife) = [s.b.patch[m] for m in eachindex(s.b.names) if s.b.kind[m] == 'M' && s.circuit.active[m] && s.b.patch[m] <= 2]

# --- serialization (part of save/load) ---
# Every component in a fixed order, little-endian; an optional field carries a tag byte (0 nothing, 1 value).
_enc(io::IO, x::Bool) = write(io, UInt8(x))
_enc(io::IO, x::Union{Int64,Float64,UInt8,UInt32}) = write(io, htol(x))
_enc(io::IO, x::Char) = write(io, htol(reinterpret(UInt32, x)))
_enc(io::IO, x::String) = (_enc(io, Int64(ncodeunits(x))); write(io, codeunits(x)))
const _BITS = Union{Int64,Float64,UInt8,UInt32}
_enc(io::IO, x::Vector) = (_enc(io, Int64(length(x))); for e in x; _enc(io, e); end)
_enc(io::IO, x::Matrix) = (_enc(io, Int64(size(x, 1))); _enc(io, Int64(size(x, 2))); for e in x; _enc(io, e); end)
# Arrays of bit types in one write (the bytes of the element loop above on a little-endian host, checked at save).
_enc(io::IO, x::Vector{T}) where {T<:_BITS} = (_enc(io, Int64(length(x))); write(io, x))
_enc(io::IO, x::Matrix{T}) where {T<:_BITS} = (_enc(io, Int64(size(x, 1))); _enc(io, Int64(size(x, 2))); write(io, x))
_enc(io::IO, x::Union{Tuple,NamedTuple}) = for e in x; _enc(io, e); end
function _enc(io::IO, x::Union{CState,Pend,Circuit,World,Port,OneLife})
    for f in fieldnames(typeof(x))
        v = getfield(x, f)
        if Nothing <: fieldtype(typeof(x), f)
            v === nothing ? write(io, 0x00) : (write(io, 0x01); _enc(io, v))
        else
            _enc(io, v)
        end
    end
end
onelife_encode(s::OneLife) = (io = IOBuffer(); _enc(io, s); take!(io))
# The six compared components of P1 (circuit, wiring, perm, noise, world, pools) as bytes.
onelife_inner_bytes(circuit, b, perm, noise::Int, w, pool) = (io = IOBuffer(); _enc(io, (circuit, b, perm, noise, w, pool)); take!(io))
onelife_inner_bytes(s::OneLife) = onelife_inner_bytes(s.circuit, s.b, s.perm, s.noise, s.w, s.pool)

_dec(io::IO, ::Type{Bool}) = (v = read(io, UInt8); v <= 0x01 || error("bad Bool"); v == 0x01)
_dec(io::IO, ::Type{T}) where {T<:Union{Int64,Float64,UInt8,UInt32}} = ltoh(read(io, T))
_dec(io::IO, ::Type{Char}) = reinterpret(Char, ltoh(read(io, UInt32)))
function _declen(io::IO)
    n = _dec(io, Int64); (0 <= n <= bytesavailable(io)) || error("bad length"); return n
end
_dec(io::IO, ::Type{String}) = String(read(io, _declen(io)))
_dec(io::IO, ::Type{Vector{T}}) where {T} = (n = _declen(io); T[_dec(io, T) for _ in 1:n])
function _dec(io::IO, ::Type{Vector{T}}) where {T<:_BITS}
    n = _declen(io); n * sizeof(T) <= bytesavailable(io) || error("bad length")
    v = Vector{T}(undef, n); read!(io, v); return v
end
function _dec(io::IO, ::Type{Matrix{T}}) where {T<:_BITS}
    r = _dec(io, Int64); c = _dec(io, Int64)
    (0 <= r && 0 <= c && r * c * sizeof(T) <= bytesavailable(io)) || error("bad size")
    m = Matrix{T}(undef, r, c); read!(io, m); return m
end
_dec(io::IO, ::Type{T}) where {T<:Tuple} = Tuple(_dec(io, ft) for ft in fieldtypes(T))
_dec(io::IO, ::Type{T}) where {T<:NamedTuple} = T(Tuple(_dec(io, ft) for ft in fieldtypes(T)))
function _dec(io::IO, ::Type{T}) where {T<:Union{CState,Pend,Circuit,World,Port,OneLife}}
    vals = Any[]
    for ft in fieldtypes(T)
        if Nothing <: ft
            tag = read(io, UInt8)
            tag <= 0x01 || error("bad tag")
            push!(vals, tag == 0x00 ? nothing : _dec(io, Base.typesplit(ft, Nothing)))
        else
            push!(vals, _dec(io, ft))
        end
    end
    return T(vals...)
end
# Inverse of onelife_encode for the law L; trailing bytes are an error.
function onelife_decode(::Type{L}, bytes::Vector{UInt8}) where {L}
    io = IOBuffer(bytes); s = _dec(io, OneLife{L}); eof(io) || error("trailing bytes"); return s
end

# Save / load (S48 §3.4). Bytes: "OLIF", format version (UInt32), law identity (32 bytes), body length (Int64), body
# (onelife_encode), SHA-256 of everything before it (32 bytes). The check value detects accidental corruption only.
# The law identity is the SHA-256 of the law's name and numbers; a load refuses another law's save.
const ONELIFE_FORMAT = UInt32(1)
const LAW_L2 = "L2 U=0.02 MCOST=0.004 KC=0.002 CONTRAST=bin3 IDLE=true GATE=true SEENBOTH=false SEDFADE=false"
const LAW_L2SF = "L2+SF U=0.02 MCOST=0.004 KC=0.002 CONTRAST=bin3 IDLE=true GATE=true SEENBOTH=false SEDFADE=true"
_lawid(::Type{LawL2}) = sha256(LAW_L2)
_lawid(::Type{LawL2SF}) = sha256(LAW_L2SF)
function onelife_save(s::OneLife{L}) where {L}
    ENDIAN_BOM == 0x04030201 || error("little-endian host required")
    body = onelife_encode(s)
    io = IOBuffer(); write(io, b"OLIF"); write(io, htol(ONELIFE_FORMAT)); write(io, _lawid(L)); write(io, htol(Int64(length(body)))); write(io, body)
    head = take!(io)
    return vcat(head, sha256(head))
end
# Any mismatch is an error (an exception); no state is returned or made in its place.
function _load(::Type{L}, bytes::Vector{UInt8}) where {L}
    n = length(bytes)
    n >= 80 || error("onelife_load: too short")
    sha256(view(bytes, 1:n-32)) == bytes[n-31:n] || error("onelife_load: check value mismatch")
    bytes[1:4] == b"OLIF" || error("onelife_load: not a OneLife save")
    ltoh(reinterpret(UInt32, bytes[5:8])[1]) == ONELIFE_FORMAT || error("onelife_load: format version")
    bytes[9:40] == _lawid(L) || error("onelife_load: another law")
    ltoh(reinterpret(Int64, bytes[41:48])[1]) == n - 80 || error("onelife_load: body length")
    return onelife_decode(L, bytes[49:n-32])
end
onelife_load_L2(bytes::Vector{UInt8}) = _load(LawL2, bytes)
onelife_load_L2SF(bytes::Vector{UInt8}) = _load(LawL2SF, bytes)
# --- end of serialization ---
