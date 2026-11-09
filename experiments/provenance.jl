# S41 (spec discussion/specs/S41-rb-provenance.md r1): the history of the low conf of the newly high patch's motor m* after
# the exchange Z (S40). For each Z update τ where m0 wins with conf(m*) < conf(m0), the target edges E* are the edges into
# m* that drove at τ with q = 0 before τ (core edges selected by the same rule, also listed apart). Their q history runs from
# the trial's start to just before τ (main run 1..t, then the Z branch t+1..τ-1); each update's change of q is attributed by
# the rule, in the rule's order (core/circuit.jl): confirmation (grow, :219–230), then W (:232–238, an acting patch motor
# without an answer weakens its unconfirmed receptor edges that drove), then D (:289, every unconfirmed non-exempt edge at
# now % 8 == 0). The attribution is checked against the actual q (a mismatch leaves the edge undetermined from then on).
# Writes experiments/results-rb-provenance.json. Predictions: predictions-rb-provenance.md (frozen before the claim seeds).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(481:490, ",")), ",")))
const H = 392
const W = 15

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)
swapped(sch) = AS.Schedule(sch.name * "-swap", reverse(sch.first), reverse(sch.second), sch.switch)

# ---------------------------------------------------------------- one update's record
const PRE = Ref{Any}(nothing); const POST = Ref{Any}(nothing); const WATCH = Ref{Any}(nothing); const SREF = Ref{Any}(nothing)
LBA.CLAMP[] = (st, y) -> (st === WATCH[] && (S = SREF[].side[st]; PRE[] = (q = copy(S.c.q), sg = copy(S.c.sg), y = copy(y), t = S.c.t)); (y, nothing))
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCH[] && (POST[] = (q = copy(c.q), acting = copy(o.acting), drove = copy(o.drove), confirmed = copy(o.confirmed_patch),
                                                               answered = copy(o.answered), now = c.t)))
"""Steps from the state (st, S): one record per update (nothing for a dead update)."""
function run_steps!(s, p, sch, st, n)
    S = s.side[st]; WATCH[] = st; SREF[] = s; recs = Any[]
    for _ in 1:n
        PRE[] = nothing; POST[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        push!(recs, (PRE[] === nothing || POST[] === nothing) ? nothing : merge(POST[], (q_pre = PRE[].q, sg_pre = PRE[].sg, y = PRE[].y)))
    end
    WATCH[] = nothing
    recs
end

# ---------------------------------------------------------------- the attribution of q's change on one edge in one update
exempt(b, k) = b.patch[b.edges[k][2]] == 4 && b.q0[k] > 0
"""The rule's order on edge k: confirmed -> grow (exact, never a decrease); otherwise W (if the target is an acting
patch motor without an answer, the source a receptor, and the edge drove) lowers q if q > 0; then D (now % 8 == 0, not exempt)
lowers q if still > 0. Returns (ops that lowered q, predicted q, matches)."""
function attribute(b, r, k)
    a, c, _ = b.edges[k]; q0 = r.q_pre[k]; q1 = r.q[k]
    # a confirmed edge grows exactly as core/circuit.jl:219–225 (confirmed_patch holds only edges that passed L2's contrast, :218,
    # so grow is not blocked): q < P_SMAX -> min(P_SMAX, q + 1 + sg) (memory on), else unchanged; nothing lowers it this update
    if r.confirmed[k]
        pred = q0 < LC.P_SMAX ? min(LC.P_SMAX, q0 + 1 + r.sg_pre[k]) : q0
        return (ops = String[], pred = pred, ok = pred == q1)
    end
    ops = String[]; q = q0
    w = c in r.acting && b.patch[c] <= 2 && get(r.answered, c, true) == false && b.kind[a] == 'R' && r.drove[k]
    w && q > 0 && (q -= 1; push!(ops, "W"))
    d = r.now % LC.P_DECAY == 0 && !exempt(b, k)
    d && q > 0 && (q -= 1; push!(ops, "D"))
    (ops = ops, pred = q, ok = q == q1)
end
"""The history of edge k for the motor m over the records (trial start .. just before τ): the q series, the last positive
run and the update that zeroed it (with the rule), the acts of m, and whether the attribution held at every update."""
function history(b, recs, k, m, qstart)
    qs = [qstart]; ok = true; drops = Any[]
    for (i, r) in enumerate(recs)
        r === nothing && (ok = false; break)
        at = attribute(b, r, k); ok &= at.ok
        r.q_pre[k] == qs[end] || (ok = false)
        isempty(at.ops) || push!(drops, (i = i, ops = at.ops, from = r.q_pre[k], to = r.q[k], m_acted = m in r.acting))
        push!(qs, r.q[k])
    end
    acts = [i for (i, r) in enumerate(recs) if r !== nothing && m in r.acting]
    everpos = any(>(0), qs)
    # the zeroing of the current zero: the last update whose q went from > 0 to 0
    z = findlast(i -> qs[i] > 0 && qs[i + 1] == 0, 1:length(qs) - 1)
    zinfo = z === nothing ? nothing : (u = z, ops = [d.ops for d in drops if d.i == z], m_acted = m in recs[z].acting,
                                       last_act_before = (l = findlast(<(z), acts); l === nothing ? nothing : acts[l]))
    cls = !ok ? "undetermined" : qs[end] != 0 ? "positive" : !everpos ? "Z0 (zero over the trial)" :
          zinfo === nothing ? "undetermined" : begin
              o = only(zinfo.ops)
              o == ["D"] && !zinfo.m_acted ? "zeroed by D while m* did not act" : o == ["D"] ? "zeroed by D at an update m* acted" :
              o == ["W"] ? "zeroed by W (m* acted without an answer)" : "zeroed by W and D"
          end
    Dict("class" => cls, "q_start" => qstart, "ever_positive" => everpos, "attribution_ok" => ok, "n_updates" => length(recs),
         "zeroed_at" => zinfo === nothing ? nothing : zinfo.u, "zeroed_ops" => zinfo === nothing ? nothing : zinfo.ops,
         "last_act_before_zeroing" => zinfo === nothing ? nothing : zinfo.last_act_before, "m_acts_in_trial" => length(acts),
         "n_drop_W" => count(d -> "W" in d.ops, drops), "n_drop_D" => count(d -> "D" in d.ops, drops))
end

# ---------------------------------------------------------------- conf of the motors at one update (as S40, from drove and q before)
function confs(b, r)
    motors = [u for u in eachindex(b.names) if b.kind[u] == 'M']
    Dict(m => sum((w for (k, (a, c, w)) in enumerate(b.edges) if c == m && r.drove[k] && r.q_pre[k] >= 1); init = 0) for m in motors)
end

res = Dict{String,Any}("spec" => "discussion/specs/S41-rb-provenance.md r1", "rule" => "rb", "seeds" => SEEDS, "H" => H, "W" => W, "arm" => "swap", "runs" => Any[])
su = LBA.setup_with(H); p = su.params
# unit tests of the attribution (seed 1, outside the claim seeds): a real update's record, then built records
let s1 = org(1, su, :swap), b = s1.b, st = AS.initial_state(s1, p), rr = run_steps!(s1, p, su.survival[1], st, 16)
    delete!(s1.side, st)
    r = rr[16]; k = first(b.ins[LC.unit(b, "m1")])
    real_ok = all(kk -> attribute(b, r, kk).ok, eachindex(b.edges))
    bad = merge(r, (q = (q2 = copy(r.q); q2[k] += 1; q2),)); mis = !attribute(b, bad, k).ok   # a perturbed q is caught
    m1 = LC.unit(b, "m1"); kr = only([kk for kk in b.ins[m1] if b.names[b.edges[kk][1]] == "r1"])
    mk(now, q0, q1; answered = false, drove = true) = merge(r, (q_pre = (x = copy(r.q_pre); x[kr] = q0; x), q = (x = copy(r.q); x[kr] = q1; x), acting = [m1],
        answered = Dict(m1 => answered), drove = (x = copy(r.drove); x[kr] = drove; x), confirmed = (x = copy(r.confirmed); x[kr] = false; x), now = now))
    w1 = attribute(b, mk(9, 3, 2), kr); w2 = attribute(b, mk(16, 3, 1), kr); d1 = attribute(b, mk(16, 3, 2; answered = true), kr); n1 = attribute(b, mk(9, 0, 0), kr)
    res["attribution_unit"] = Dict("real_update_matches" => real_ok, "perturbed_q_caught" => mis,
        "W_alone" => w1.ok && w1.ops == ["W"], "W_then_D" => w2.ok && w2.ops == ["W", "D"], "D_alone_when_answered" => d1.ok && d1.ops == ["D"],
        "q0_W_not_a_q_drop" => n1.ok && isempty(n1.ops))
    println("attribution unit tests ", res["attribution_unit"])
end
for seed in SEEDS
    s = org(seed, su, :swap); b = s.b; m0 = LC.unit(b, "m0")
    for sch in su.survival
        st = AS.initial_state(s, p); qstart = copy(s.side[st].c.q)
        main = Any[]; snaps = Dict{Int,Any}()
        for t in 1:H
            append!(main, run_steps!(s, p, sch, st, 1))
            !isempty(LBA.body_sites(s.side[st].w)) && t % 32 == 0 && (snaps[t] = deepcopy((st, s.side[st])))
        end
        delete!(s.side, st)
        targets = Any[]; nz = 0; nself = 0
        for t in sort(collect(keys(snaps)))
            st2, S2 = deepcopy(snaps[t]); S2.pool .= reverse(S2.pool); s.side[st2] = S2
            zr = run_steps!(s, p, swapped(sch), st2, W); delete!(s.side, st2)
            for (j, r) in enumerate(zr)
                r === nothing && break
                (length(r.acting) == 1 && only(r.acting) == m0) || continue
                y = r.y; y[1] == y[2] && continue
                ms = LC.unit(b, y[1] > y[2] ? "m1" : "m2"); cf = confs(b, r)
                cf[ms] < cf[m0] || continue
                nz += 1
                es = [k for k in b.ins[ms] if r.drove[k] && r.q_pre[k] == 0]
                recs = vcat(main[1:t], zr[1:j-1])
                for k in es
                    h = history(b, recs, k, ms, qstart[k])
                    # codex I-R 2 #4: where the zeroing happened: in the main run (shared by every branch) or in this Z branch
                    zl = h["zeroed_at"] === nothing ? nothing : h["zeroed_at"] <= t ? "main:$(h["zeroed_at"])" : "Z(t=$t):$(h["zeroed_at"])"
                    push!(targets, merge(h, Dict("t" => t, "tau" => t + j, "zeroing_loc" => zl, "motor" => b.names[ms], "edge" => "$(b.names[b.edges[k][1]])->$(b.names[ms])",
                        "core" => b.kind[b.edges[k][1]] == 'C', "conf_m" => cf[ms], "conf_m0" => cf[m0], "conf_zero" => cf[ms] == 0)))
                end
                isempty(es) && (nself += 1)
            end
        end
        push!(res["runs"], Dict("seed" => seed, "schedule" => sch.name, "q_start" => Dict("$(b.names[b.edges[k][1]])->$(b.names[b.edges[k][2]])" => qstart[k] for k in eachindex(b.edges) if b.patch[b.edges[k][2]] in (1, 2)),
                                "n_events" => nz, "n_events_without_target" => nself, "targets" => targets))
        cl = Dict{String,Int}(); for x in targets; cl[x["class"]] = get(cl, x["class"], 0) + 1; end
        println("seed=$seed $(rpad(sch.name, 11)) events $nz (no target $nself) targets $(length(targets)) ", sort(collect(cl), by = x -> -x[2]))
    end
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rb-provenance.json"))
write(out, JSON.json(res)); println("written ", out)
