using AgencySubstrate, Random
const AS = AgencySubstrate
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
base = load_templates(); p = base.params; H = 200
function survive_env(s, yields)
    st = AS.initial_state(s, p); tail = Bool[]
    for y in yields
        AS.step!(st, s, p, AS.Schedule("env", y, y, 0), Set{Int}())
        push!(tail, !st.dead && any(u -> st.active[u] && !AS.is_sensor(s, u), 1:AS.nunits(s)))
    end
    !st.dead && all(tail[end-4:end])
end
flip(k) = [isodd(div(t - 1, k)) ? (0, 5) : (5, 0) for t in 1:H]
function randenv(seed); r = MersenneTwister(seed); g = [rand(r, 1:2) for _ in 1:cld(H, 10)]; [g[cld(t, 10)] == 1 ? (5, 0) : (0, 5) for t in 1:H]; end
envs = vcat([flip(7), flip(13)], [randenv(s) for s in 1:5])
state = Ref(UInt64(20261009)); n = Dict(:agency => 0, :robust => 0, :nonagent_robust => 0, :any => 0)
for k in 1:20000
    s = random_substrate(state); r = evaluate(s, base)
    rob = all(e -> survive_env(s, e), envs)
    r.agency && (n[:agency] += 1); rob && (n[:any] += 1)
    (r.agency && rob) && (n[:robust] += 1; println("ROBUST AGENT k=", k, " names=", s.names, " theta=", s.theta, " edges=", [(s.names[a], s.names[b], w) for (a, b, w) in s.edges], " motors=", s.motors, " ps=", s.patch_sensors, " rs=", s.resource_sensors, " init=", s.initial, " r=", r)); (!r.agency && rob) && (n[:nonagent_robust] += 1)
end

