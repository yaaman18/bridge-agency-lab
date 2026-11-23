# AUE-B adapter: wraps unmodified experiments/nesting_cpc_c/NestingCPCC.jl (S61c CPC pruning) into AUESeamBed (r2).
# Canonical little-endian (`htol`) row-major serialization (including full theta matrices) for cross-language parity.
# NestingCPCC.jl and bed.jl are both strictly unmodified.

module AdapterAUEB

using SHA
using ..AUESeamBed
using ..NestingCPCC

export AUEBAdapter, AUEBState, make_aue_b_initial_state, make_aue_b_inputs, canonical_aue_b_digest

mutable struct AUEBState
    sys::NestingCPCC.System
    emit_spore_at::Union{Nothing,Int}
    spore_id::String
    spores_active::Int
end

struct AUEBAdapter <: AbstractSpeciesAdapter
    spec::SpeciesSpec
    organ_type::String
    inject_ops_override::Union{Nothing,Int}
end

function AUEBAdapter(
    spec_path::AbstractString = joinpath(@__DIR__, "species_aue_b.toml");
    organ_type::String = "cpc_local_link_pruning",
    inject_ops_override::Union{Nothing,Int} = nothing,
)
    spec = load_species_spec(spec_path)
    AUEBAdapter(spec, organ_type, inject_ops_override)
end

AUESeamBed.species_spec(a::AUEBAdapter) = a.spec

function make_aue_b_initial_state(
    config::Symbol,
    seed::Integer;
    emit_spore_at::Union{Nothing,Int} = nothing,
    spore_id::String = "spore-b-1",
)
    tape, thetas = NestingCPCC.make_tape(seed)
    sys = NestingCPCC.init_system(config, thetas)
    st = AUEBState(sys, emit_spore_at, spore_id, 0)
    inputs = make_aue_b_inputs(tape)
    return st, inputs, tape, thetas
end

function make_aue_b_inputs(tape::Vector{NestingCPCC.TapeStep})::Vector{StampedInput}
    out = Vector{StampedInput}(undef, length(tape))
    for (k, ts) in enumerate(tape)
        out[k] = StampedInput(k, Dict{String,Any}(
            "x" => ts.x,
            "h" => ts.h,
            "r" => ts.r,
            "t_abs" => k,
        ))
    end
    out
end

function _write_le(io::IO, x::Float64)
    write(io, htol(reinterpret(UInt64, x)))
end
function _write_le(io::IO, x::Int)
    write(io, htol(Int64(x)))
end

# Canonical little-endian row-major digest covering ALL fields including every module's 4x4 theta matrix & grant_cache
function canonical_aue_b_digest(s::NestingCPCC.System)::String
    io = IOBuffer()
    write(io, UInt8(s.alive ? 1 : 0))
    _write_le(io, s.R); _write_le(io, s.D); _write_le(io, s.h_ema)
    _write_le(io, s.next_id); _write_le(io, s.ctx); _write_le(io, s.step)
    _write_le(io, length(s.mods))
    for m in s.mods
        _write_le(io, m.id); _write_le(io, m.u); _write_le(io, m.born)
        # Explicit row-major order (r = 1..4, c = 1..4) for Rust compatibility
        for r in 1:size(m.theta, 1), c in 1:size(m.theta, 2)
            _write_le(io, m.theta[r, c])
        end
    end
    _write_le(io, length(s.grant_cache))
    for v in s.grant_cache
        _write_le(io, v)
    end
    bytes2hex(sha256(take!(io)))
end

function AUESeamBed.state_digest(::AUEBAdapter, st::AUEBState)::String
    canonical_aue_b_digest(st.sys)
end

function AUESeamBed.step_species(a::AUEBAdapter, st::AUEBState, si::StampedInput, ::Budget)
    x = Int(si.ports["x"])
    h = Float64(si.ports["h"])
    r = UInt64(si.ports["r"])
    t_abs = Int(si.ports["t_abs"])
    ts = NestingCPCC.TapeStep(x, h, r)

    n_pre = length(st.sys.mods)
    rec = NestingCPCC.step!(st.sys, ts, t_abs)

    upkeep_paid = rec.alive_pre ? max(0.0, NestingCPCC.C_MOD * n_pre - rec.deficit) : 0.0
    act_cost = rec.births > 0 ? NestingCPCC.C_SPLIT * rec.births : 0.0
    ops = a.inject_ops_override === nothing ? (64 * max(1, n_pre)) : a.inject_ops_override

    spore_req = (st.emit_spore_at !== nothing && si.step == st.emit_spore_at) ? st.spore_id : nothing
    if spore_req !== nothing
        st.spores_active += 1
    end
    dorm_paid = st.spores_active * a.spec.dormancy_upkeep_rate

    ports_out = Dict{String,Any}(
        "n_mods" => length(st.sys.mods),
        "alive" => rec.alive_post,
        "pruned" => rec.pruned,
        "births" => rec.births,
        "deficit" => rec.deficit,
    )

    return (st, DeclaredOutput(ports_out, a.organ_type), StepCost(ops, upkeep_paid, act_cost, dorm_paid), rec.alive_post, spore_req)
end

end # module AdapterAUEB
