# D6 lab variant (user 2026-11-01, "じゃあ次はD6の作業をやってください", after approving the recommendation): AGENCY-001's
# criteria (bridge-protocol tools/AgencySubstrate criteria.jl, unchanged, called as they are) on body_org, the circuit on
# the material body (D1), with horizons taken from the system's own time scales instead of the frozen 60 steps.
# Nothing in ~/bridge-protocol is changed. Predictions: experiments/predictions-horizon.md (frozen-horizon.txt).
# IDLE=1 (item 72): the circuit with the idle-first choice (core/circuit.jl), predictions-idle.md.
#
# Adapter choices (all derived from D1/D6 of formal/README.md and reported with the results):
#   B1 system = body_org of stage 42 as reproduced by core/check/reproduce_body_org.jl (U = 0.02, MCOST = 0.004, the
#      circuit newborn(false) raised on the curriculum before the body, rule of stage 42, noise seed = the run's seed);
#      the world is seed!(w, 12, 12, 1); each trajectory starts from a fresh copy of the raised circuit and the body.
#   B2 schedules = the frozen schedules of templates.toml, given as the growth of body_org's pools (g_k * U per step, in
#      place of the seasons); the yields the circuit reads are body_org's y_k = min(5, floor(R_k / U)).
#   B3 death = material death (the body has no constituent; A-gen, not AgencySubstrate's resource rule: X2).
#   B4 abundance (the runs with choice_params, where AgencySubstrate's resource cannot run out) = harvesting is not
#      needed: the circuit reads the schedule's yields directly, the body is fed P_CAPACITY * U of free matter per step
#      from the reservoir whatever the circuit does, and acts move no matter (MCOST is still paid).
#   B5 ablation = source silencing (LabCore.step!'s sil; a silenced motor does not act, so it digests nothing).
#   B6 structure (the strength vector the L3 criteria read):
#      :constituents = 1 for each site of a constituent of the body (D1: L3 on the material constituents); the
#        protocol's self-repair is defined on the connections of core units, so L3R does not apply to it;
#      :q = the circuit's confidences (D3, sediment not counted: X1), for reference (not the D1 system of L3).
#   B7 a dead system: the circuit stops; its confidences decay by 1 every decay_period (as AgencySubstrate); the world
#      goes on.
#   H horizons: 60 (frozen; L2 is decided before measuring there, shown as not measurable), 392 = 2 x 196 (the body's
#      starvation time without the circuit, item 66; main), 294 and 588 (sensitivity, declared in advance). Only the
#      horizon is changed; alive_window, choice_window, switch_at and the schedules are the frozen ones.
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON

module LabBodyAgency

using AgencySubstrate
const AS = AgencySubstrate
import ..LabCore
const LC = LabCore

struct BodyOrg
    names::Vector{String}
    edges::Vector{NTuple{3,Int}}
    motors::Dict{Int,Int}
    b::LC.Circuit
    raised::LC.CState
    noise::LC.Mulberry
    structure::Symbol
    abundant_r0::Int
    U::Float64
    MCOST::Float64
    idle_first::Bool
    side::IdDict{Any,Any}
end

"""The circuit of body_org (B1) raised on the curriculum with noise seed `seed`."""
function BodyOrg(seed::Integer; structure::Symbol = :constituents, abundant_r0::Integer, U = 0.02, MCOST = 0.004, idle_first = false)
    b = LC.newborn(false); c = LC.init(b); noise = LC.Mulberry(seed)
    for y in LC.BO_CUR; LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = nothing, idle_first); end
    motors = Dict(LC.unit(b, "m1") => 1, LC.unit(b, "m2") => 2)
    BodyOrg(copy(b.names), copy(b.edges), motors, b, c, noise, structure, abundant_r0, U, MCOST, idle_first, IdDict())
end

AS.nunits(s::BodyOrg) = length(s.names)
AS.is_sensor(s::BodyOrg, u::Int) = s.b.kind[u] == 'R'

body_sites(w) = [i for i in eachindex(w.C) if w.C[i] != 0]
strength(s::BodyOrg, c, w) = s.structure == :q ? copy(c.q) : Int[w.C[i] != 0 ? 1 : 0 for i in eachindex(w.C)]

function AS.initial_state(s::BodyOrg, p::AS.Params)
    c = deepcopy(s.raised); w = LC.make_world(; reservoir = 300.0); LC.seed!(w, 12, 12, 1)
    st = AS.State(copy(c.active), strength(s, c, w), 0, 0, false)
    s.side[st] = (c = c, w = w, noise = deepcopy(s.noise), pool = [0.0, 0.0])
    st
end

function pay!(w, body, cost)
    paid = 0.0
    for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
    LC.port_give!(w.port, paid)
end

function AS.step!(st::AS.State, s::BodyOrg, p::AS.Params, sch::AS.Schedule, silenced::Set{Int})
    S = s.side[st]; c, w, pool = S.c, S.w, S.pool
    abundant = p.resource0 == s.abundant_r0
    t = st.t
    body = body_sites(w)
    if !st.dead && isempty(body)
        st.dead = true
    end
    if st.dead
        (t + 1) % p.decay_period == 0 && (c.q .= max.(c.q .- 1, 0))     # B7
        c.active .= false
    else
        g = [Float64(AS.yield_of(sch, 1, t)), Float64(AS.yield_of(sch, 2, t))]
        y = abundant ? g : [min(5.0, floor(r / s.U + 1e-9)) for r in pool]
        o = LC.step!(c, s.b, [y[1], y[2], 0.0]; noise = S.noise, contrast = nothing, sil = silenced, idle_first = s.idle_first)
        acting = [s.b.patch[m] for m in o.acting if s.b.patch[m] <= 2]
        if abundant                                                      # B4
            feed = LC.port_take!(w.port, LC.P_CAPACITY * s.U)
            for i in body; w.A[i] += feed / length(body); end
        else
            for k in 1:2
                if o.d[k] > 0
                    take = min(pool[k], o.d[k] * s.U); pool[k] -= take
                    for i in body; w.A[i] += take / length(body); end
                end
            end
        end
        isempty(acting) || pay!(w, body, s.MCOST * length(acting))
        if !abundant                                                     # B2
            for k in 1:2
                pool[k] += LC.port_take!(w.port, g[k] * s.U); over = pool[k] - 50 * s.U
                if over > 0; pool[k] -= over; LC.port_give!(w.port, over); end
            end
        end
    end
    LC.step!(w, ())
    st.active = st.dead ? fill(false, length(s.names)) : copy(c.active)
    st.strength = strength(s, c, w)
    st.t += 1
    st
end

function AS.run_trajectory(s::BodyOrg, p::AS.Params, sch::AS.Schedule; silenced::Set{Int} = Set{Int}())
    st = AS.initial_state(s, p)
    traj = [deepcopy(st)]
    for _ in 1:p.horizon
        AS.step!(st, s, p, sch, silenced)
        push!(traj, AS.State(copy(st.active), copy(st.strength), st.resource, st.t, st.dead))
    end
    delete!(s.side, st)
    traj
end

# The criteria typed on `Substrate`, re-evaluated from the protocol's source with `BodyOrg` (as audit/agency_adapter.jl).
const CRITERIA = joinpath(pkgdir(AgencySubstrate), "src", "criteria.jl")
function _retype(ex)
    ex isa Expr || return ex
    ex.head == :(::) && length(ex.args) == 2 && ex.args[2] == :Substrate && return Expr(:(::), ex.args[1], BodyOrg)
    Expr(ex.head, map(_retype, ex.args)...)
end
function _install()
    n = 0
    for ex in Meta.parseall(read(CRITERIA, String)).args
        ex isa Expr || continue
        def = ex.head == :macrocall ? ex.args[end] : ex
        def isa Expr && def.head in (:function, :(=)) || continue
        occursin("::Substrate", string(def.args[1])) || continue
        Core.eval(AS, Expr(def.head, _retype(def.args[1]), def.args[2:end]...)); n += 1
    end
    n
end
const INSTALLED = _install()

with_horizon(p::AS.Params, H) = AS.Params(p.smax, p.decay_period, p.grow_cost, p.resource0, p.rmax, H, p.alive_window, p.strength0)

"""The frozen setup with every horizon set to H (only the horizon changes)."""
function setup_with(H)
    su = AS.load_templates()
    merge(su, (params = with_horizon(su.params, H), choice_params = with_horizon(su.choice_params, H)))
end

"""Tables for Lean's checks (formal/LabCircuit.lean): survival intact/ablated per schedule, structure all-silenced /
own-activity per schedule."""
function tables(s::BodyOrg, su, r)
    p, pc, surv = su.params, su.choice_params, su.survival
    T = Set(findall(n -> n in r.value_tracking, s.names))
    survival = [(AS.survives(s, p, x), isempty(T) ? AS.survives(s, p, x) : AS.survives(s, p, x; silenced = T)) for x in surv]
    structure = [(AS.structure_persists(s, pc, x; silenced = AS.sensor_units(s)),
                  AS.structure_persists(s, p, x; silenced = Set(1:AS.nunits(s)))) for x in surv]
    (; survival, structure, T_empty = isempty(T))
end

end # module

const LBA = LabBodyAgency
const AS = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "60,294,392,588"), ","))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", "1,2,3,4,5,6,7,8,9,10"), ","))
const OUT = get(ENV, "OUT", joinpath(LAB, "experiments", "results-horizon.json"))
const IDLE = get(ENV, "IDLE", "0") == "1"   # item 72: the idle-first choice in the raising and the trials

res = Dict{String,Any}("horizons" => HS, "seeds" => SEEDS, "criteria" => "bridge-protocol tools/AgencySubstrate criteria.jl (unchanged)",
    "templates_sha256" => AS.load_templates().sha256, "idle_first" => IDLE, "runs" => Any[])
for H in HS
    su = LBA.setup_with(H)
    for seed in SEEDS, structure in (:constituents, :q)
        s = LBA.BodyOrg(seed; structure, abundant_r0 = su.choice_params.resource0, idle_first = IDLE)
        t0 = time(); r = AS.evaluate(s, su); tb = LBA.tables(s, su, r)
        push!(res["runs"], Dict("H" => H, "seed" => seed, "structure" => String(structure), "agency_L2" => r.agency,
            "self_producing_L3" => r.self_producing, "self_repairing_L3R" => structure == :q ? r.self_repairing : nothing,
            "core" => r.core, "core_enables_action" => r.core_enables_action, "alive_somewhere" => r.alive_somewhere,
            "differentiated" => r.differentiated, "value_needed" => r.value_needed, "value_tracking" => r.value_tracking,
            "value_tracking_measured" => r.value_tracking_measured, "choices" => r.choices, "survival" => r.survival,
            "survival_without_tracking" => r.survival_without_tracking,
            "table_survival" => [[a, b] for (a, b) in tb.survival], "table_structure" => [[a, b] for (a, b) in tb.structure],
            "seconds" => round(time() - t0; digits = 1)))
        x = res["runs"][end]
        println("H=$H seed=$seed $(rpad(String(structure), 12)) L2=$(r.agency) L3=$(r.self_producing) L3R=$(x["self_repairing_L3R"]) core=$(r.core) hinge=$(r.core_enables_action) alive=$(r.alive_somewhere) diff=$(r.differentiated) needed=$(r.value_needed) T=$(r.value_tracking) surv=$(r.survival) survT=$(r.survival_without_tracking) ($(x["seconds"]) s)")
    end
end
write(OUT, JSON.json(res, 2))
println("written ", relpath(OUT, LAB))
