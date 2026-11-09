# S42 (spec discussion/specs/S42-rb-lockin.md): how the rest after the exchange Z ends over a longer branch on RB :swap
# (S40, S41). From the same state at t (after update t), the Z branch (pools exchanged at t, schedule swapped from t+1)
# runs L updates. m* = the motor of the patch with the larger y read at t+1. Per branch: release (m* acts within L),
# lock (alive through L, m* never acts), death (dead before m* acts); the decision record of m*'s first act (how, idle,
# conf, key, lastM), whether it was answered, the q of m*'s edges after it, and whether m* later wins by key without idle.
# Writes experiments/results-rb-lockin.json. Predictions: predictions-rb-lockin.md (frozen before the claim seeds).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(491:500, ",")), ",")))
const H = 392
const L = parse(Int, get(ENV, "L", "160"))
const TPTS = 32:32:H              # codex V1 5: main = t + L <= H (32:32:224); the later points are a separate extension
main_point(t) = t + L <= H

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)
swapped(sch) = AS.Schedule(sch.name * "-swap", reverse(sch.first), reverse(sch.second), sch.switch)

# ---------------------------------------------------------------- the decision record of one update (as S40's decision)
const PRE = Ref{Any}(nothing); const POST = Ref{Any}(nothing); const WATCH = Ref{Any}(nothing); const SREF = Ref{Any}(nothing)
LBA.CLAMP[] = (st, y) -> (st === WATCH[] && (S = SREF[].side[st]; PRE[] = (q = copy(S.c.q), sg = copy(S.c.sg), old = copy(S.c.active),
    lastM = S.c.lastM === nothing ? nothing : copy(S.c.lastM), t = S.c.t, y = copy(y))); (y, nothing))
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCH[] && (POST[] = (acting = copy(o.acting), drove = copy(o.drove), choice = o.choice,
    answered = copy(o.answered), q = copy(c.q))))
function decision(s, pre, post)
    b = s.b; motors = [u for u in eachindex(b.names) if b.kind[u] == 'M']
    conf = Dict(m => 0 for m in motors); habit = Dict(m => 0 for m in motors); total = Dict(m => 0 for m in motors)
    for (k, (a, c, w)) in enumerate(b.edges)
        b.kind[c] == 'M' && post.drove[k] || continue
        total[c] += w; pre.q[k] >= 1 ? (conf[c] += w) : pre.sg[k] >= 1 && (habit[c] += w)
    end
    on = Dict(m => total[m] >= b.theta[m] && any(k -> post.drove[k] && b.kind[b.edges[k][1]] == 'C', b.ins[m]) for m in motors)   # core_gate
    cand = sort([m for m in motors if on[m]])
    key(m) = conf[m] * 1_000_000 + habit[m] * 1_000 + total[m]
    now = pre.t + 1
    idl = pre.lastM === nothing ? Int[] : [m for m in cand if now - pre.lastM[m] > LC.FORGET]
    pool0 = isempty(idl) ? cand : idl
    how = if length(cand) <= 1
        isempty(cand) ? "no candidate" : "single candidate"
    else
        best = maximum(key, pool0); tied = [m for m in pool0 if key(m) == best]
        pv = [m for m in tied if pre.old[m]]; px = isempty(pv) ? tied : pv
        length(tied) == 1 ? (isempty(idl) ? "key" : "idle, then key") : length(px) == 1 ? "tie on key, decided by old" : "tie on key and old, decided by patch number"
    end
    nm(m) = b.names[m]
    ok = (post.choice === nothing ? length(cand) <= 1 : sort(post.choice.cand) == cand) && all(m -> m in cand, post.acting)
    Dict("now" => now, "y" => pre.y[1:2], "cand" => nm.(cand), "idle" => nm.(idl),
         "conf" => Dict(nm(m) => conf[m] for m in motors), "habit" => Dict(nm(m) => habit[m] for m in motors), "total" => Dict(nm(m) => total[m] for m in motors),
         "lastM" => pre.lastM === nothing ? nothing : Dict(nm(m) => pre.lastM[m] for m in motors),
         "act" => isempty(post.acting) ? "none" : join(sort(nm.(post.acting)), ","), "how" => how, "selfcheck" => ok,
         "answered" => Dict(nm(m) => v for (m, v) in post.answered),
         "qin" => Dict(nm(m) => Dict(nm(b.edges[k][1]) => (pre.q[k], post.q[k], pre.sg[k]) for k in b.ins[m]) for m in motors if b.patch[m] <= 2),
         "theta" => Dict(nm(m) => b.theta[m] for m in motors),
         "core_drove" => Dict(nm(m) => any(k -> post.drove[k] && b.kind[b.edges[k][1]] == 'C', b.ins[m]) for m in motors),
         "key" => Dict(nm(m) => key(m) for m in motors))
end
function branch_n(s, p, sch, snap, n)
    st, S = deepcopy(snap); s.side[st] = S; WATCH[] = st; SREF[] = s
    recs = Any[]
    for _ in 1:n
        PRE[] = nothing; POST[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        push!(recs, (PRE[] === nothing || POST[] === nothing) ? Dict("act" => "dead") : decision(s, PRE[], POST[]))
    end
    WATCH[] = nothing; delete!(s.side, st)
    recs
end
"""The state after n updates from a copy of snap (no records)."""
function replay(s, p, sch, snap, n)
    st, S = deepcopy(snap); s.side[st] = S
    for _ in 1:n; AS.step!(st, s, p, sch, Set{Int}()); end
    out = deepcopy((st, S)); delete!(s.side, st); out
end
"""codex V1 7: one update from the same state with the org as is and with idle_first off only (stale is kept: it does not
read idle_first). Returns the two acts. A rule intervention for this one update, not a long-run effect."""
function one_step_acts(s, p, sch, snap)
    s0 = typeof(s)([f == :idle_first ? false : getfield(s, f) for f in fieldnames(typeof(s))]...)
    acts = String[]
    for o in (s, s0)
        st, S = deepcopy(snap); o.side[st] = S; WATCH[] = st; SREF[] = o; POST[] = nothing
        AS.step!(st, o, p, sch, Set{Int}())
        push!(acts, POST[] === nothing ? "dead" : isempty(POST[].acting) ? "none" : join(sort([s.b.names[m] for m in POST[].acting]), ","))
        WATCH[] = nothing; delete!(o.side, st)
    end
    acts
end
function main_run(s, p, sch)
    st = AS.initial_state(s, p); snaps = Dict{Int,Any}(); clock0 = s.side[st].c.t   # codex V1 8: the circuit clock at the trial start
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        !isempty(LBA.body_sites(s.side[st].w)) && t in TPTS && (snaps[t] = deepcopy((st, s.side[st])))
    end
    delete!(s.side, st)
    snaps, clock0
end

"""One Z branch from t: the outcome and the record of m*'s first act."""
function outcome(s, p, sch, snap, recs, t, clock0)
    first = recs[1]
    first["act"] == "dead" && return Dict("t" => t, "outcome" => "dead at t+1", "mstar" => nothing)
    y = first["y"]; y[1] == y[2] && return Dict("t" => t, "outcome" => "excluded (y1 == y2 at t+1)", "mstar" => nothing)
    ms = y[1] > y[2] ? "m1" : "m2"
    i = findfirst(r -> r["act"] != "dead" && ms in split(r["act"], ","), recs)
    d = findfirst(r -> r["act"] == "dead", recs)
    alive_steps = d === nothing ? length(recs) : d - 1
    acts = Dict(a => count(r -> r["act"] == a, recs) for a in ("m0", "m1", "m2", "none", "dead"))
    base = Dict{String,Any}("t" => t, "mstar" => ms, "alive_steps" => alive_steps, "acts" => acts,
                            "lastM_t1" => first["lastM"] === nothing ? nothing : first["lastM"][ms], "clock0" => clock0,
                            # the branch update k at which m* becomes idle if it does not act before: now(k) - lastM > FORGET, now(k) = now(1) + k - 1
                            "k_idle_due" => first["lastM"] === nothing ? nothing : first["lastM"][ms] + LC.FORGET + 2 - first["now"],
                            # codex V1 8: lastM before the trial start = m* has not acted in the trial before t (lastM carried from the raising)
                            "no_act_in_trial_before_t" => first["lastM"] !== nothing && first["lastM"][ms] <= clock0,
                            # codex V1 4: m0 won every update of the first 15 (the S40 rest); the main set
                            "m0_all15" => length(recs) >= 15 && all(r -> r["act"] == "m0", recs[1:15]), "main_point" => main_point(t),
                            "selfcheck" => all(r -> r["act"] == "dead" || r["selfcheck"], recs),
                            "order_constant" => all(r -> r["act"] == "dead" || sign(r["y"][1] - r["y"][2]) == sign(y[1] - y[2]), recs),
                            # the main set (codex V1 4): alive through the first 15 updates and m* did not act in them (S40's rest)
                            "rest15" => length(recs) >= 15 && all(r -> r["act"] != "dead" && !(ms in split(r["act"], ",")), recs[1:15]),
                            "other_acts" => count(r -> r["act"] != "dead" && (ms == "m1" ? "m2" : "m1") in split(r["act"], ","), recs),
                            # gate: with no idle motor at t+1, idle_first off cannot change the act (the comparison's negative control)
                            "one_step_t1" => isempty(first["idle"]) ? (a = one_step_acts(s, p, sch, snap); Dict("same" => a[1] == a[2], "replay_agrees" => a[1] == first["act"])) : nothing)
    # codex I-R 1 #6: for every branch (released or not): the update at which m* first became idle (now - lastM > FORGET) and
    # whether it was a candidate there; for a death, the dead update = alive_steps + 1
    on = findfirst(x -> x["act"] != "dead" && x["lastM"] !== nothing && x["now"] - x["lastM"][ms] > LC.FORGET, recs)
    base["idle_onset_k"] = on
    base["cand_at_idle_onset"] = on === nothing ? nothing : ms in recs[on]["cand"]
    base["dead_k"] = d
    if i === nothing
        base["outcome"] = d === nothing ? "lock" : "death"
        return base
    end
    r = recs[i]
    base["outcome"] = "release"; base["k"] = i; base["first"] = r
    base["since_lastM"] = r["now"] - r["lastM"][ms]
    # codex V1 3, 6: flags, not an exclusive cause; the conditions of candidacy and of choice kept apart
    allzero = all(v -> v[1] == 0 && v[3] == 0, values(r["qin"][ms]))
    base["flags"] = Dict("idle_mstar" => ms in r["idle"], "allzero_stale" => allzero, "m0_candidate" => "m0" in r["cand"],
                         "key_mstar_ge_m0" => r["key"][ms] >= r["key"]["m0"], "conf_mstar" => r["conf"][ms], "conf_m0" => r["conf"]["m0"],
                         "total_ge_theta" => r["total"][ms] >= r["theta"][ms], "core_drove" => r["core_drove"][ms], "how" => r["how"])
    # codex V1 7: the one-update comparison at the state just before m*'s first act; the first act replayed must agree
    pre = replay(s, p, sch, snap, i - 1)
    a_on, a_off = one_step_acts(s, p, sch, pre)
    base["one_step"] = Dict("act_as_is" => a_on, "act_idle_first_off" => a_off, "replay_agrees" => a_on == r["act"])
    base["answered"] = get(r["answered"], ms, nothing)
    base["q_up"] = any(v -> v[2] > v[1], values(r["qin"][ms]))
    # codex V1 9: described separately (not called relearning): answered, an edge of m* raised, a later act of m* with no idle motor
    j = findfirst(x -> x["act"] != "dead" && ms in split(x["act"], ",") && isempty(x["idle"]), recs[i+1:end])
    base["later_nonidle_act"] = j === nothing ? nothing : i + j
    base
end

res = Dict{String,Any}("spec" => "discussion/specs/S42-rb-lockin.md", "rule" => "rb", "seeds" => SEEDS, "H" => H, "L" => L, "arm" => "swap",
                       "branch_points" => collect(TPTS), "runs" => Any[])
su = LBA.setup_with(H); p = su.params
for seed in SEEDS
    s = org(seed, su, :swap)
    for sch in su.survival
        snaps, clock0 = main_run(s, p, sch)
        evs = Any[]
        for t in sort(collect(keys(snaps)))
            Zs = deepcopy(snaps[t]); Zs[2].pool .= reverse(Zs[2].pool)   # Z as S39–S41
            push!(evs, outcome(s, p, swapped(sch), Zs, branch_n(s, p, swapped(sch), Zs, L), t, clock0))
        end
        push!(res["runs"], Dict("seed" => seed, "schedule" => sch.name, "events" => evs))
        println("seed=$seed $(rpad(sch.name, 11)) ", join(["t$(e["t"]):$(e["outcome"])" * (e["outcome"] == "release" ? "($(e["flags"]["idle_mstar"] ? "idle" : e["flags"]["how"]),k$(e["k"]),Δ$(e["since_lastM"]),off=$(e["one_step"]["act_idle_first_off"]))" : "") for e in evs], " "))
    end
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rb-lockin.json"))
write(out, JSON.json(res)); println("written ", out)
