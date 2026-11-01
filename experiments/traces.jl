using AgencySubstrate, SHA, Random
const AS = AgencySubstrate
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
all_t = vcat(load_templates(joinpath(@__DIR__, "designs.toml")).templates, load_templates().templates)
pick = ["selfloop-pair-agent", "reflex", "thermostat", "alternator", "no-loop"]
p = load_templates().params; H = 40
env = [isodd(div(t - 1, 7)) ? (0, 5) : (5, 0) for t in 1:H]
order = shuffle(MersenneTwister(7), pick); letters = 'A':'E'
io = open("traces.txt", "w"); key = open("key.txt", "w"); hashes = String[]
println(io, "Each system lives in a world with two food patches. 'yields' = food available at patch 1 and patch 2 this step.\nEach active unit costs 1 food per step; an active motor unit collects the yield of its patch. 'store' = food in reserve. If store would go below 0 the system dies.\nUnit roles: S(pN)=sensor that fires when patch N is the richer one, R=sensor of its own low store, M(pN)=motor that harvests patch N, I=internal unit.\n")
for (L, name) in zip(letters, order)
    s = only(t for t in all_t if t.name == name).substrate
    perm = shuffle(MersenneTwister(hash(name)), 1:AS.nunits(s))   # anonymize unit order
    role(u) = haskey(s.patch_sensors, u) ? "S(p$(s.patch_sensors[u]))" : haskey(s.resource_sensors, u) ? "R" : haskey(s.motors, u) ? "M(p$(s.motors[u]))" : "I"
    label = Dict(u => "u$(i)=$(role(u))" for (i, u) in enumerate(perm))
    st = AS.initial_state(s, p); buf = IOBuffer()
    println(io, "### System $L\nunits: ", join([label[u] for u in perm], ", "))
    for (t, y) in enumerate(env)
        AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
        act = [split(label[u], "=")[1] for u in perm if st.active[u]]
        line = "t=$t yields=$(y) store=$(st.resource) active=[$(join(act, ","))]" * (st.dead ? " DEAD" : "")
        println(io, line); println(buf, line)
        st.dead && t > 3 && (println(io, "(no further change)"); break)
    end
    push!(hashes, "$L $(bytes2hex(sha256(take!(buf))))")
    println(key, "$L = $name"); println(io)
end
close(io); close(key); write("trace-hashes-before.txt", join(hashes, "\n") * "\n")
