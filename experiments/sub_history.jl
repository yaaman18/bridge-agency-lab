# S30 (spec discussion/specs/S30-sub-history.md r1, gaps G11): R-SUB-1 the history-intervention comparison on SUB (bp
# AgencySubstrate, frozen templates) and R-SUB-2 the dead / tail activity / finite rescue diagnostic. bp is not changed: the
# trial start is overridden in this process only (@eval AS, the CLAUDE.md procedure). Writes experiments/results-sub-history.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
const K = 60
@eval AS begin
    const LAB_PRE = IdDict{Any,Any}()   # Substrate => the state after the prehistory (S30)
    initial_state(s::Substrate, p::Params) = haskey(LAB_PRE, s) ?
        (x = deepcopy(LAB_PRE[s]); x.t = 0; x.resource = p.resource0; x) :
        State(copy(s.initial), fill(p.strength0, length(s.edges)), p.resource0, 0, false)
end
su = AS.load_templates(); p = su.params
fields(r) = Dict(String(k) => getfield(r, k) for k in keys(r))
cmp(r) = Dict(k => getfield(r, k) for k in (:agency, :self_producing, :self_repairing, :core, :core_enables_action, :alive_somewhere, :differentiated, :value_needed, :value_tracking, :choices, :survival))
nonsensor_active(s, st) = count(u -> st.active[u] && !AS.is_sensor(s, u), 1:AS.nunits(s))
function diag(s, sch)
    traj = AS.run_trajectory(s, p, sch); last = traj[end]
    dt = findfirst(st -> st.dead, traj)
    tail = [nonsensor_active(s, st) for st in traj[end-p.alive_window+1:end]]
    surv = AS.alive(traj, s, p)
    resc = nothing
    if !last.dead && !surv
        st = deepcopy(last); st.resource = p.rmax; R = 4 * p.alive_window; acts = Int[]
        for _ in 1:R; AS.step!(st, s, p, sch, Set{Int}()); push!(acts, st.dead ? 0 : nonsensor_active(s, st)); end
        first_re = findfirst(>(0), acts)
        first_win = findfirst(j -> j >= p.alive_window && all(>(0), acts[j-p.alive_window+1:j]), eachindex(acts))
        resc = Dict("first_reactivation" => first_re, "first_window_completed" => first_win, "reached" => first_win !== nothing, "dead_during" => st.dead, "R" => R)
    end
    Dict("schedule" => sch.name, "dead_at" => dt === nothing ? nothing : dt - 1, "tail_nonsensor_active" => tail, "survives" => surv, "rescue" => resc === nothing ? (last.dead ? "dead (no recovery by rule)" : "not needed") : resc)
end
res = Dict{String,Any}("spec" => "discussion/specs/S30-sub-history.md r1", "templates_sha256" => su.sha256, "K" => K, "rows" => Any[])
for t in su.templates
    s = t.substrate
    empty!(AS.LAB_PRE)
    orig = AS.evaluate(s, su)                                      # SH0: the original definition (no entry)
    st0 = AS.State(copy(s.initial), fill(p.strength0, length(s.edges)), p.resource0, 0, false)
    AS.LAB_PRE[s] = st0; ctrl = AS.evaluate(s, su)                 # K = 0 override
    sh0 = isequal(fields(orig), fields(ctrl))
    dctrl = [diag(s, x) for x in su.survival]
    arms = Dict{String,Any}()
    for X in su.survival[1:2]                                      # p1-high, p2-high
        st = AS.State(copy(s.initial), fill(p.strength0, length(s.edges)), p.resource0, 0, false)
        for _ in 1:K; AS.step!(st, s, p, X, Set{Int}()); end
        AS.LAB_PRE[s] = deepcopy(st)
        r = AS.evaluate(s, su)
        indep = all(f -> isequal(getfield(AS.LAB_PRE[s], f), getfield(st, f)), fieldnames(AS.State))   # field by field (fixed after the first run: isequal on the mutable State compared identity)
        arms[X.name] = Dict("pre_dead" => st.dead, "pre_state" => Dict("active" => st.active, "strength" => st.strength, "resource" => st.resource),
                            "cmp" => Dict(String(k) => v for (k, v) in cmp(r)), "stored_unchanged" => indep, "diag" => [diag(s, x) for x in su.survival])
    end
    empty!(AS.LAB_PRE)
    a, b = arms["p1-high"], arms["p2-high"]
    elig = !a["pre_dead"] && !b["pre_dead"]
    diff = elig ? [k for k in keys(a["cmp"]) if !isequal(a["cmp"][k], b["cmp"][k])] : nothing
    push!(res["rows"], Dict("template" => t.name, "SH0" => sh0, "control" => Dict(String(k) => v for (k, v) in cmp(orig)), "control_diag" => dctrl, "arms" => arms, "eligible" => elig, "differing_fields" => diff))
    println("$(rpad(t.name, 13)) SH0 $sh0 eligible $elig differing $(diff) pre_dead $(a["pre_dead"])/$(b["pre_dead"]) stored_unchanged $(a["stored_unchanged"])/$(b["stored_unchanged"])")
end
write(joinpath(LAB, "experiments", "results-sub-history.json"), JSON.json(res, 2))
println("SH1 ", any(r -> r["eligible"] && !isempty(r["differing_fields"]), res["rows"]) ? "holds" : (any(r -> r["eligible"], res["rows"]) ? "fails" : "not evaluable"), "  SH0 all ", all(r -> r["SH0"], res["rows"]))
