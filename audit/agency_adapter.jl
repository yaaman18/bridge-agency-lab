# AGENCY-001's criteria (bridge-protocol tools/AgencySubstrate, unchanged) applied to the lab's circuit.
#
# Nothing in ~/bridge-protocol is changed. The criteria are the protocol's code: the functions of criteria.jl that are
# written for any substrate are called as they are; the three that are typed on AgencySubstrate's `Substrate`
# (alive, sensor_units, evaluate) are re-evaluated from the protocol's own source file with the type replaced by
# `LabSubstrate`, so that if criteria.jl changes, the adapter follows it. The frozen setup (fixtures/templates.toml:
# params, survival and choice schedules, choice window) is used as it is.
#
# What the adapter has to choose, because the lab's circuit is not AgencySubstrate's prototype (all reported with the
# results, none of them decided by the user yet; they belong to D6 of formal/README.md):
#   A1 sensors = the receptors r1..r11; motors = m1 -> patch 1, m2 -> patch 2 (m3, the call, has no patch).
#   A2 strength of a connection = `:q` (its confidence) or `:qsg` (confidence + sediment: the connection can still act).
#   A3 death = `:none` (the organization layer has no death; the being of the app cannot die) or `:agency001`
#      (AgencySubstrate's resource rule, as an observer's account: every active unit costs 1 per step, an active
#      patch motor gains its patch's yield, the system dies when the resource would go below 0; no growth cost).
#   A4 start = the being as saved (each run starts from a copy of it); the partner is absent (no gestures); the
#      world gives the schedule's yields directly (no pools), as in AgencySubstrate.
module LabAgency

using AgencySubstrate
const AS = AgencySubstrate
import ..LabCore

"""The lab's circuit, from a saved being, as a substrate for the AGENCY-001 criteria."""
struct LabSubstrate
    names::Vector{String}
    edges::Vector{NTuple{3,Int}}
    motors::Dict{Int,Int}
    b::LabCore.Circuit
    start::LabCore.CState
    rng::UInt32
    strength::Symbol
    death::Symbol
    side::IdDict{Any,Any}      # AgencySubstrate.State => (circuit state, noise)
end

function LabSubstrate(record::AbstractDict; strength::Symbol = :q, death::Symbol = :none)
    l = LabCore.makelife(deepcopy(record))
    b = l.b
    motors = Dict(LabCore.unit(b, "m1") => 1, LabCore.unit(b, "m2") => 2)
    LabSubstrate(copy(b.names), copy(b.edges), motors, b, deepcopy(l.st), LabCore.Mulberry(l.L["rng"]).s, strength, death, IdDict())
end

strengths(s::LabSubstrate, cs) = s.strength == :q ? copy(cs.q) : cs.q .+ cs.sg

AS.nunits(s::LabSubstrate) = length(s.names)
AS.is_sensor(s::LabSubstrate, u::Int) = s.b.kind[u] == 'R'

function AS.initial_state(s::LabSubstrate, p::AS.Params)
    cs = deepcopy(s.start)
    st = AS.State(copy(cs.active), strengths(s, cs), p.resource0, 0, false)
    s.side[st] = (cs, LabCore.Mulberry(s.rng))
    st
end

function AS.step!(st::AS.State, s::LabSubstrate, p::AS.Params, sch::AS.Schedule, silenced::Set{Int})
    cs, noise = s.side[st]
    if st.dead
        # as AgencySubstrate: nothing maintains a dead system's connections; they decay (confidence, every decay steps)
        if (st.t + 1) % p.decay_period == 0
            cs.q .= max.(cs.q .- 1, 0)
        end
        st.strength = strengths(s, cs)
        st.t += 1
        return st
    end
    y = [Float64(AS.yield_of(sch, 1, st.t)), Float64(AS.yield_of(sch, 2, st.t)), 0.0]
    o = LabCore.step!(cs, s.b, y; noise = noise, contrast = LabCore.RULE, sil = silenced,
                      idle_first = LabCore.RULES[LabCore.RULE_NAME].idle_first)   # the app's rule (bin3+idle since v3.7)
    if s.death == :agency001
        gain = sum((AS.yield_of(sch, s.motors[m], st.t) for m in o.acting if haskey(s.motors, m) && !(m in silenced)); init = 0)
        resource = st.resource + gain - count(cs.active)
        if resource < 0
            st.dead = true; st.active = fill(false, length(s.names)); st.resource = 0
            st.strength = strengths(s, cs); st.t += 1
            return st
        end
        st.resource = min(resource, p.rmax)
    end
    st.active = copy(cs.active)
    st.strength = strengths(s, cs)
    st.t += 1
    st
end

function AS.run_trajectory(s::LabSubstrate, p::AS.Params, sch::AS.Schedule; silenced::Set{Int} = Set{Int}())
    st = AS.initial_state(s, p)
    traj = [deepcopy(st)]
    for _ in 1:p.horizon
        AS.step!(st, s, p, sch, silenced)
        push!(traj, deepcopy(st))
    end
    delete!(s.side, st)
    traj
end

# The criteria typed on `Substrate`, re-evaluated from the protocol's source with `LabSubstrate`.
const CRITERIA = joinpath(pkgdir(AgencySubstrate), "src", "criteria.jl")
function _retype(ex)
    ex isa Expr || return ex
    if ex.head == :(::) && length(ex.args) == 2 && ex.args[2] == :Substrate
        return Expr(:(::), ex.args[1], LabSubstrate)
    end
    Expr(ex.head, map(_retype, ex.args)...)
end
_sig_has_substrate(sig) = occursin("::Substrate", string(sig))
function _install()
    n = 0
    for ex in Meta.parseall(read(CRITERIA, String)).args
        ex isa Expr || continue
        def = ex.head == :macrocall ? ex.args[end] : ex     # a docstring wraps the definition
        def isa Expr && def.head in (:function, :(=)) || continue
        sig = def.args[1]
        _sig_has_substrate(sig) || continue
        Core.eval(AS, Expr(def.head, _retype(sig), def.args[2:end]...))
        n += 1
    end
    n
end
const INSTALLED = _install()

"""AGENCY-001's evaluation of a saved being under adapter choices A2 (strength) and A3 (death)."""
function evaluate_being(record::AbstractDict; strength::Symbol = :q, death::Symbol = :none)
    setup = AS.load_templates()
    s = LabSubstrate(record; strength, death)
    r = AS.evaluate(s, setup)
    (; result = r, setup_sha256 = setup.sha256)
end

end
