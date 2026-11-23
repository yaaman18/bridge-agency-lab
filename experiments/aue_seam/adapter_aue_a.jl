# AUE-A adapter: wraps unmodified core/LabCore.jl (OneLife L2) into AUESeamBed.
# core/ is strictly read-only.

module AdapterAUEA

using SHA
using Printf
using ..AUESeamBed
using ..LabCore

export AUEAAdapter, AUEAState, make_aue_a_initial_state, make_aue_a_inputs

mutable struct AUEAState
    w::LabCore.World
    pool::Vector{Float64}
    perm::Vector{Int}
    b::LabCore.Circuit
    circuit::LabCore.CState
    noise::LabCore.Mulberry
    t::Int
    alive::Bool
    death::Union{Nothing,Int}
    nActs::Int
    moved::Float64
    spent::Float64
    upkeep::Float64
    emit_spore_at::Union{Nothing,Int}
    spore_id::String
end

struct AUEAAdapter <: AbstractSpeciesAdapter
    spec::SpeciesSpec
    U::Float64
    MCOST::Float64
    KC::Float64
    organ_type::String
    inject_undeclared_port::Bool
    inject_ops_override::Union{Nothing,Int}
    inject_free_dormancy::Bool
end

function AUEAAdapter(
    spec_path::AbstractString = joinpath(@__DIR__, "species_aue_a.toml");
    U::Float64 = 0.02,
    MCOST::Float64 = 0.004,
    KC::Float64 = 0.004,
    organ_type::String = "L2_circuit_bin3",
    inject_undeclared_port::Bool = false,
    inject_ops_override::Union{Nothing,Int} = nothing,
    inject_free_dormancy::Bool = false,
)
    spec = load_species_spec(spec_path)
    AUEAAdapter(spec, U, MCOST, KC, organ_type, inject_undeclared_port, inject_ops_override, inject_free_dormancy)
end

AUESeamBed.species_spec(a::AUEAAdapter) = a.spec

function make_aue_a_initial_state(
    seed::Integer;
    reservoir::Float64 = 300.0,
    emit_spore_at::Union{Nothing,Int} = nothing,
    spore_id::String = "spore-a-1",
)::AUEAState
    w = LabCore.make_world(; reservoir = reservoir)
    LabCore.seed!(w, 12, 12, 1)
    pool = [0.0, 0.0]
    perm = collect(1:length(LabCore.FEATURES))
    b = LabCore.newborn(false; perm = perm)
    circuit = LabCore.init(b)
    noise = LabCore.Mulberry(seed)
    for y in LabCore.BO_CUR
        LabCore.step!(circuit, b, [y[1], y[2], 0.0];
                      noise = noise, contrast = :bin3, idle_first = true,
                      core_gate = true, seen_both = false, sed_fade = false)
    end
    AUEAState(w, pool, perm, b, circuit, noise, 0, true, nothing, 0, 0.0, 0.0, 0.0, emit_spore_at, spore_id)
end

function make_aue_a_inputs(steps::Int; schedule_fn = LabCore.bo_season, event_ref_prefix::Union{Nothing,String} = nothing)::Vector{StampedInput}
    out = Vector{StampedInput}(undef, steps)
    for t in 0:steps-1
        g = schedule_fn(t)
        refs = event_ref_prefix === nothing ? Tuple{String,Float64}[] :
               [("$(event_ref_prefix)-$(t)", Float64(g[1] + g[2]))]
        out[t + 1] = StampedInput(t, Dict{String,Any}("g1" => Float64(g[1]), "g2" => Float64(g[2])), refs)
    end
    out
end

function AUESeamBed.state_digest(::AUEAAdapter, st::AUEAState)::String
    io = IOBuffer()
    write(io, Int64(st.t), UInt8(st.alive ? 1 : 0))
    write(io, st.pool[1], st.pool[2], st.w.port.reservoir, st.w.port.inflow, st.w.port.outflow)
    write(io, st.w.A)
    write(io, st.w.B)
    write(io, st.w.C)
    write(io, st.circuit.q)
    write(io, st.circuit.sg)
    write(io, st.circuit.h)
    write(io, st.noise.s)
    bytes2hex(sha256(take!(io)))
end

function AUESeamBed.step_species(a::AUEAAdapter, st::AUEAState, si::StampedInput, ::Budget)
    U = a.U
    MCOST = a.MCOST
    KC = a.KC
    g1 = Float64(si.ports["g1"])
    g2 = Float64(si.ports["g2"])
    g = [g1, g2]

    w = st.w
    pool = st.pool
    y = [min(5.0, floor(r / U + 1e-9)) for r in pool]
    body = [i for i in eachindex(w.C) if w.C[i] != 0]
    if st.alive && isempty(body)
        st.alive = false
        st.death = st.t
    end

    acting = Int[]
    d = [0.0, 0.0]
    t_upkeep = 0.0
    t_spent = 0.0

    if st.alive
        out = LabCore.step!(st.circuit, st.b, [y[1], y[2], 0.0];
                            noise = st.noise, contrast = :bin3, idle_first = true,
                            core_gate = true, seen_both = false, sed_fade = false)
        acting = [st.b.patch[m] for m in out.acting if st.b.patch[m] <= 2]
        d = out.d

        if KC != 0.0
            nk = count(k -> st.circuit.q[k] >= 1 || st.circuit.sg[k] >= 1, eachindex(st.circuit.q))
            cost = KC * nk
            paid = 0.0
            for i in body
                m = min(w.B[i], cost / length(body))
                w.B[i] -= m
                paid += m
            end
            LabCore.port_give!(w.port, paid)
            st.upkeep += paid
            t_upkeep = paid
        end

        if !isempty(acting)
            for k in 1:2
                if d[k] > 0
                    take = min(pool[k], d[k] * U)
                    pool[k] -= take
                    for i in body
                        w.A[i] += take / length(body)
                    end
                    st.moved += take
                end
            end
            cost = MCOST * length(acting)
            paid = 0.0
            for i in body
                m = min(w.B[i], cost / length(body))
                w.B[i] -= m
                paid += m
            end
            LabCore.port_give!(w.port, paid)
            st.spent += paid
            st.nActs += length(acting)
            t_spent = paid
        end
    end

    for k in 1:2
        tk = LabCore.port_take!(w.port, g[k] * U)
        pool[k] += tk
        over = pool[k] - 50 * U
        if over > 0
            pool[k] -= over
            LabCore.port_give!(w.port, over)
        end
    end
    LabCore.step!(w, ())

    nconst = LabCore.nconstituents(w)
    # Check death status cleanly on current body before incrementing step
    alive_post = st.alive && nconst > 0

    spore_req = (st.emit_spore_at !== nothing && si.step == st.emit_spore_at) ? st.spore_id : nothing
    dorm_paid = 0.0
    if spore_req !== nothing
        dorm_paid = a.inject_free_dormancy ? 0.0 : a.spec.dormancy_upkeep_rate
    elseif st.emit_spore_at !== nothing && si.step > st.emit_spore_at
        dorm_paid = a.inject_free_dormancy ? 0.0 : a.spec.dormancy_upkeep_rate
    end

    ports_out = Dict{String,Any}(
        "act_patch_1" => (1 in acting ? 1 : 0),
        "act_patch_2" => (2 in acting ? 1 : 0),
        "alive" => alive_post,
        "constituents" => nconst,
    )
    if a.inject_undeclared_port
        ports_out["secret_sidechannel"] = 1
    end

    ops = a.inject_ops_override === nothing ? 128 : a.inject_ops_override
    st.t += 1
    if !alive_post && st.alive
        st.alive = false
        st.death = st.t
    end

    return (st, DeclaredOutput(ports_out, a.organ_type), StepCost(ops, t_upkeep, t_spent, dorm_paid), alive_post, spore_req)
end

end # module AdapterAUEA
