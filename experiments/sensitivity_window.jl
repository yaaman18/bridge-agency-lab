# Post hoc (not pre-registered), 2026-10-29: W7 as registered was confounded, because silencing a motor for
# the whole run starves the agent by step 8. Here the intervention is short: from each start t0 in season 1,
# branch the run into "intact" and "motor m silenced for 10 steps" (P-04), and compare how often each patch
# sensor fires in those 10 steps. Averaged over t0 = 20, 30, ..., 280. Death in a branch is reported.
using AgencySubstrate, Printf
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_sensor_ge.jl"))
include(joinpath(@__DIR__, "env_deplete.jl"))
function run_from(s, p, st0, stock0, t0, n; silenced=Set{Int}())
    st = deepcopy(st0); stock = copy(stock0); fire = Dict(u => 0 for u in keys(s.patch_sensors)); died = false
    for t in (t0 + 1):(t0 + n)
        y = (min(stock[1], 5), min(stock[2], 5))
        AS.step!(st, s, p, AS.Schedule("w", y, y, 0), silenced)
        st.dead && (died = true; break)
        h = [0, 0]; for (m, pa) in s.motors; (st.active[m] && !(m in silenced)) && (h[pa] = y[pa]); end
        g = season(t); stock = [min(CAP, stock[i] - h[i] + g[i]) for i in 1:2]
        for u in keys(fire); st.active[u] && (fire[u] += 1); end
    end
    fire, died
end
base = load_templates(); p = base.params
for (f, name) in [("designs.toml", "selfloop-pair-agent"), ("", "static-agent")]
    set = f == "" ? base : load_templates(joinpath(@__DIR__, f)); s = only(t for t in set.templates if t.name == name).substrate
    st = AS.initial_state(s, p); stock = [CAP, CAP]; snaps = Dict{Int,Any}()
    for t in 1:280
        y = (min(stock[1], 5), min(stock[2], 5)); AS.step!(st, s, p, AS.Schedule("w", y, y, 0), Set{Int}())
        h = [0, 0]; for (m, pa) in s.motors; st.active[m] && (h[pa] = y[pa]); end
        g = season(t); stock = [min(CAP, stock[i] - h[i] + g[i]) for i in 1:2]
        t % 10 == 0 && t >= 20 && (snaps[t] = (deepcopy(st), copy(stock)))
    end
    print(rpad(name, 22))
    for m in sort(collect(keys(s.motors))), u in sort(collect(keys(s.patch_sensors)))
        d = Float64[]; deaths = 0
        for t0 in sort(collect(keys(snaps))); (st0, sk0) = snaps[t0]
            a, _ = run_from(s, p, st0, sk0, t0, 10); b, died = run_from(s, p, st0, sk0, t0, 10; silenced=Set([m]))
            deaths += died; push!(d, (b[u] - a[u]) / 10)
        end
        @printf("%s|silence %s: %+.2f (deaths %d/%d)   ", s.names[u], s.names[m], sum(d) / length(d), deaths, length(d))
    end
    println()
end
