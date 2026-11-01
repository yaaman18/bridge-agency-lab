# Fragility battery (2026-10-29): how small a perturbation kills the agent in the depletion world (rev. 2).
# Perturbations, each started at t0 in {50, 100, ..., 250} (season 1), {350, 450, 550} (season 2) and
# {650, 750, 850} (season 3), run to step 1000:
#   silence u k : source silencing of unit u for k steps (P-04)
#   famine k    : both yields forced to 0 and no regeneration for k steps (environment shock)
#   theft       : the stock of every patch set to 0 at t0
# Reported: for each perturbation, the number of start times (of 11) after which the agent is dead at 1000.
using AgencySubstrate, Printf
const AS = AgencySubstrate
include(joinpath(@__DIR__, get(ENV, "WORLD_VARIANT", "variant_sensor_ge.jl")))
include(joinpath(@__DIR__, "env_deplete.jl"))
function run_world(s, p, T; sil=t -> Set{Int}(), famine=t -> false, theft=t -> false)
    st = AS.initial_state(s, p); stock = [CAP, CAP]
    for t in 1:T
        theft(t) && (stock = [0, 0])
        y = famine(t) ? (0, 0) : (min(stock[1], 5), min(stock[2], 5))
        S = sil(t)
        AS.step!(st, s, p, AS.Schedule("w", y, y, 0), S)
        st.dead && return (false, t)
        h = [0, 0]; for (m, pa) in s.motors; (st.active[m] && !(m in S)) && (h[pa] = y[pa]); end
        g = famine(t) ? (0, 0) : season(t)
        stock = [min(CAP, stock[i] - h[i] + g[i]) for i in 1:2]
    end
    (true, T)
end
const T0S = [50, 100, 150, 200, 250, 350, 450, 550, 650, 750, 850]
function battery(s, p)
    out = Pair{String,Int}[]
    for u in 1:AS.nunits(s), k in (1, 3, 10, 30)
        push!(out, "silence $(s.names[u]) $k" => count(t0 -> !first(run_world(s, p, 1000; sil=t -> t0 <= t < t0 + k ? Set([u]) : Set{Int}())), T0S))
    end
    for k in (1, 3, 10, 30)
        push!(out, "famine $k" => count(t0 -> !first(run_world(s, p, 1000; famine=t -> t0 <= t < t0 + k)), T0S))
    end
    push!(out, "theft" => count(t0 -> !first(run_world(s, p, 1000; theft=t -> t == t0)), T0S))
    out
end
if abspath(PROGRAM_FILE) == @__FILE__
    base = load_templates(); p = base.params
    s = only(t for t in load_templates(joinpath(@__DIR__, "designs.toml")).templates if t.name == "selfloop-pair-agent").substrate
    println("unperturbed: ", run_world(s, p, 1000))
    for (k, v) in battery(s, p); v > 0 && println(rpad(k, 22), v, "/11 dead"); end
    println("(perturbations not listed killed 0/11)")
end
