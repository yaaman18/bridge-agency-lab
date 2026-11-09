# S32 (spec discussion/specs/S32-body-activity.md r1): is the BODY's activity kept maximal by its rules? Records, for each
# update of the raising (a copy of the curriculum run) and of the trials (SF, no intervention), the candidates computed
# from step!'s `drove` (the formula of core/circuit.jl:116-128), the cores' state, S(m) (formal Activity.cand_of_S), the
# acting patch motors and the breakdown of updates without a candidate. Writes results-activity.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(401:410, ",")), ","))
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const GSEED = parse(Int, get(ENV, "GSEED", "401"))
const H = 392

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)

"""One update's record from the state before (`pre`: active, q, sg, lastM, now) and step!'s result `o`."""
function record(b, pre, o, post_active, sil)
    patch = [m for m in eachindex(b.names) if b.kind[m] == 'M' && b.patch[m] <= 2]
    cores = [u for u in eachindex(b.names) if b.kind[u] == 'C']
    th(u) = b.theta[u]
    cand = Int[]; why = Dict{String,Any}()
    S = Dict{String,Bool}(); stale = Dict{String,Bool}(); idlem = Dict{String,Bool}(); onsetm = Dict{String,Bool}(); rk = Dict{Int,Any}()
    for m in patch
        ins = b.ins[m]
        total = count(k -> o.drove[k], ins)
        core = any(k -> o.drove[k] && b.kind[b.edges[k][1]] == 'C', ins)
        (total >= th(m) && core) && push!(cand, m)
        why[b.names[m]] = Dict("total" => total, "core" => core)
        kc = [k for k in ins if b.kind[b.edges[k][1]] == 'C']
        kr = [k for k in ins if b.kind[b.edges[k][1]] == 'R']
        S[b.names[m]] = any(k -> pre.active[b.edges[k][1]] && !(b.edges[k][1] in sil) && pre.q[k] >= 1, kc) &&
                        any(k -> pre.active[b.edges[k][1]] && !(b.edges[k][1] in sil) && (pre.q[k] >= 1 || pre.sg[k] >= 1), kr)
        idle = pre.lastM !== nothing && pre.now - pre.lastM[m] > LC.FORGET
        idlem[b.names[m]] = idle
        stale[b.names[m]] = all(k -> pre.q[k] == 0 && pre.sg[k] == 0, ins)   # all edges in without q and sg (idle separately)
        onsetm[b.names[m]] = any(k -> (a = b.edges[k][1]; b.kind[a] == 'R' && pre.active[a] && !pre.prev[a] && pre.q[k] == 0 && pre.sg[k] == 0 && pre.h[k] == 0), ins)
        # the rank of circuit.jl:135-138 (key, then on before, then the smaller patch) and the idle preference (:139-143)
        conf = count(k -> o.drove[k] && pre.q[k] >= 1, ins); habit = count(k -> o.drove[k] && pre.q[k] == 0 && pre.sg[k] >= 1, ins)
        rk[m] = (conf * 1_000_000 + habit * 1_000 + total, pre.active[m] ? 1 : 0, -b.patch[m], idle)
    end
    # A1's premise for each core: on before, not silenced, a confident self edge
    a1 = Dict(b.names[u] => pre.active[u] && !(u in sil) && any(k -> b.edges[k][1] == u && b.edges[k][2] == u && pre.q[k] >= 1, b.ins[u]) for u in cores)
    acting = [m for m in o.acting if b.kind[m] == 'M' && b.patch[m] <= 2]
    pl = [m for m in cand if rk[m][4]]; pl = isempty(pl) ? cand : pl
    winner = isempty(pl) ? nothing : pl[argmax([rk[m][1:3] for m in pl])]
    g1 = o.choice === nothing ? (length(cand) <= 1 ? missing : false) : sort(o.choice.cand) == sort(cand)
    Dict("cand" => [b.names[m] for m in cand], "acting" => [b.names[m] for m in acting], "cores_on" => all(u -> post_active[u], cores),
         "A1" => a1, "S" => S, "stale" => stale, "idle" => idlem, "onset" => onsetm, "why" => why, "G1" => g1,
         "winner" => winner === nothing ? nothing : b.names[winner])
end
prestate(c) = (active = copy(c.active), q = copy(c.q), sg = copy(c.sg), h = copy(c.h), prev = c.prev === nothing ? copy(c.active) : copy(c.prev),
               lastM = c.lastM === nothing ? nothing : copy(c.lastM), now = c.t + 1)

function raising(s, seed, cur)
    b = LC.newborn(false); c = LC.init(b); noise = LC.Mulberry(seed); recs = Any[]
    for y in LBA.curriculum(cur)
        pre = prestate(c)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = s.contrast, idle_first = s.idle_first, core_gate = s.core_gate,
                     seen_both = s.seen_both, sed_fade = s.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[])
        push!(recs, record(b, pre, o, c.active, Set{Int}()))
    end
    same = b.edges == s.b.edges && all(f -> isequal(getfield(c, f), getfield(s.raised, f)), fieldnames(typeof(c))) &&
           all(f -> isequal(getfield(noise, f), getfield(s.noise, f)), fieldnames(typeof(noise)))
    (recs = recs, same = same)
end

const PRE = Ref{Any}(nothing)
function trial(s, p, sch)
    st = AS.initial_state(s, p); recs = Any[]
    LBA.CLAMP[] = (st_, y) -> (PRE[] = prestate(s.side[st_].c); (y, nothing))   # read only: returns the default channels
    LBA.ON_STEP[] = (st_, o, c, y) -> push!(recs, merge(record(s.b, PRE[], o, c.active, Set{Int}()), Dict("t" => st_.t + 1)))
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
    end
    LBA.CLAMP[] = nothing; LBA.ON_STEP[] = nothing; delete!(s.side, st)
    recs
end

res = Dict{String,Any}("spec" => "discussion/specs/S32-body-activity.md r1", "rule" => "sf", "seeds" => SEEDS, "gseed" => GSEED, "H" => H,
                       "arms" => String.(ARMS), "raising" => Any[], "trials" => Any[])
su = LBA.setup_with(H); p = su.params
r1 = trial(org(GSEED, su, :std), p, su.survival[1]); r2 = trial(org(GSEED, su, :std), p, su.survival[1])
res["G2_repeat"] = isequal(r1, r2)
for seed in SEEDS, arm in ARMS
    s = org(seed, su, arm)
    R = raising(s, seed, arm)
    push!(res["raising"], Dict("seed" => seed, "arm" => String(arm), "G0_same" => R.same, "steps" => R.recs))
    for sch in su.survival
        push!(res["trials"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "steps" => trial(s, p, sch)))
    end
    println("seed=$seed $arm G0 $(R.same)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-activity.json"))
write(out, JSON.json(res))
println("written ", out)
