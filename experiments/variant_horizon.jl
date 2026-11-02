# D6 lab variant (user 2026-11-01, "じゃあ次はD6の作業をやってください", after approving the recommendation): AGENCY-001's
# criteria (bridge-protocol tools/AgencySubstrate criteria.jl, unchanged, called as they are) on body_org, the circuit on
# the material body (D1), with horizons taken from the system's own time scales instead of the frozen 60 steps.
# Nothing in ~/bridge-protocol is changed. Predictions: experiments/predictions-horizon.md (frozen-horizon.txt).
# IDLE=1 (item 72): the circuit with the idle-first choice (core/circuit.jl), predictions-idle.md.
# CONTRAST=bin3 and CUR=swap (item 74): the contrast rule of the app, and the raising with the nursery swapped
# (experiments/curricula.jl); predictions-body-bin3.md. Since item 75 the default is bin3 + idle_first (B1 below);
# item 70's runs are CONTRAST=none IDLE=0 OUT=experiments/results-horizon.json.
#
# Adapter choices (all derived from D1/D6 of formal/README.md and reported with the results):
#   B1 system = body_org of stage 42 as reproduced by core/check/reproduce_body_org.jl (U = 0.02, MCOST = 0.004, the
#      circuit newborn(false) raised on the curriculum before the body; rule bin3 + idle_first since item 75, the
#      app's rule, and the core gate since item 77 (items 70-74 ran the rule of stage 42, contrast nothing), noise seed = the run's seed);
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
include(joinpath(@__DIR__, "curricula.jl"))

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
    contrast::Union{Nothing,Symbol}
    core_gate::Bool
    side::IdDict{Any,Any}
end

"""The circuit of body_org (B1) raised on the curriculum with noise seed `seed`."""
function BodyOrg(seed::Integer; structure::Symbol = :constituents, abundant_r0::Integer, U = 0.02, MCOST = 0.004, idle_first = false,
                 contrast = nothing, cur = :std, core_gate = false)
    b = LC.newborn(false); c = LC.init(b); noise = LC.Mulberry(seed)
    for y in curriculum(cur); LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast, idle_first, core_gate); end
    motors = Dict(LC.unit(b, "m1") => 1, LC.unit(b, "m2") => 2)
    BodyOrg(copy(b.names), copy(b.edges), motors, b, c, noise, structure, abundant_r0, U, MCOST, idle_first, contrast, core_gate, IdDict())
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
        o = LC.step!(c, s.b, [y[1], y[2], 0.0]; noise = S.noise, contrast = s.contrast, sil = silenced, idle_first = s.idle_first, core_gate = s.core_gate)
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

"""Item 76: survival schedules with both patches positive, the frozen ones with the empty patch given `low` (frozen
switch_at; the choice schedules and window stay frozen). `low = nothing` keeps the frozen survival schedules."""
function survival_with(su, low)
    low === nothing && return su.survival
    f(v) = Tuple(x == 0 ? low : x for x in v)
    [AS.Schedule("$(x.name)-$(low)", f(x.first), f(x.second), x.switch) for x in su.survival]
end
"""The frozen setup with every horizon set to H (only the horizon changes; and the survival schedules with `low`, item 76)."""
function setup_with(H; low = nothing)
    su = AS.load_templates()
    merge(su, (params = with_horizon(su.params, H), choice_params = with_horizon(su.choice_params, H), survival = survival_with(su, low)))
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
if abspath(PROGRAM_FILE) == @__FILE__   # the runs (the module above is also included by experiments/diag/diag_l2.jl)
const LAB = normpath(joinpath(@__DIR__, ".."))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "60,294,392,588"), ","))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", "1,2,3,4,5,6,7,8,9,10"), ","))
# The circuit's rule. Default since item 75 (user 2026-11-02): bin3 + idle_first, the app's rule (L2's system, D1), and
# since item 77 (user 2026-11-02) with the core gate (GATE, below; output results-horizon-gate.json).
# CONTRAST=none IDLE=0 is the rule of stage 42 (item 70, results-horizon.json; item 72 IDLE=1, results-horizon-idle.json).
const IDLE = get(ENV, "IDLE", "1") == "1"   # item 72: the idle-first choice in the raising and the trials
const CONTRAST = get(ENV, "CONTRAST", "bin3") in ("", "none") ? nothing : Symbol(get(ENV, "CONTRAST", "bin3"))   # item 74
const OUT = get(ENV, "OUT", joinpath(LAB, "experiments", CONTRAST == :bin3 && IDLE ? (get(ENV, "GATE", "1") == "1" ? "results-horizon-gate.json" : "results-horizon-bin3idle.json") : "results-horizon-other.json"))
const CUR = Symbol(get(ENV, "CUR", "std"))   # item 74
const GATE = get(ENV, "GATE", "1") == "1"   # item 76 step 2: the core gate (default since item 77; GATE=0 for items 74-76)
const LOW = get(ENV, "LOW", "") == "" ? nothing : parse(Int, ENV["LOW"])   # item 76: survival schedules with the empty patch at LOW

res = Dict{String,Any}("horizons" => HS, "seeds" => SEEDS, "criteria" => "bridge-protocol tools/AgencySubstrate criteria.jl (unchanged)",
    "templates_sha256" => AS.load_templates().sha256, "idle_first" => IDLE, "contrast" => CONTRAST === nothing ? nothing : String(CONTRAST), "curriculum" => String(CUR), "survival_low" => LOW, "core_gate" => GATE, "runs" => Any[])
for H in HS
    su = LBA.setup_with(H; low = LOW)
    for seed in SEEDS, structure in (:constituents, :q)
        s = LBA.BodyOrg(seed; structure, abundant_r0 = su.choice_params.resource0, idle_first = IDLE, contrast = CONTRAST, cur = CUR, core_gate = GATE)
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
end
