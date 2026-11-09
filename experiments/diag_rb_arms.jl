# S35 (spec discussion/specs/S35-diag-rb-arms.md r1): why RB (S34) dies on :std and lives on :swap. A diagnosis on the
# used seeds 421-430 (no claim): E1 the raised circuits, E2 the raising per step, E3 the trial's first 32 updates, E4 the
# trial until death or H (acts, intake, body quantity). Writes results-diag-rb-arms.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(421:430, ",")), ","))
const H = 392

org(seed, su, cur; rest = false, rest_body = nothing) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0,
    idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = rest, rest_body = rest_body)
motors(b) = [m for m in eachindex(b.names) if b.kind[m] == 'M']
"""Rank components of each candidate at one update, from the state before (q, sg, active) and step!'s drove."""
function ranks(b, pre_q, pre_sg, pre_active, o)
    out = Dict{String,Any}()
    for m in motors(b)
        ins = b.ins[m]
        total = count(k -> o.drove[k], ins); core = any(k -> o.drove[k] && b.kind[b.edges[k][1]] == 'C', ins)
        (total >= b.theta[m] && core) || continue
        out[b.names[m]] = Dict("conf" => count(k -> o.drove[k] && pre_q[k] >= 1, ins), "habit" => count(k -> o.drove[k] && pre_q[k] == 0 && pre_sg[k] >= 1, ins),
                               "total" => total, "old" => pre_active[m])
    end
    out
end
winner(b, o) = (a = [b.names[m] for m in o.acting if b.kind[m] == 'M']; isempty(a) ? "none" : only(a))
edges_into(b, c, name) = (m = LC.unit(b, name); m === nothing ? nothing : [Dict("src" => b.names[b.edges[k][1]], "q" => c.q[k], "sg" => c.sg[k]) for k in b.ins[m] if c.q[k] > 0 || c.sg[k] > 0 || b.kind[b.edges[k][1]] == 'C'])
coreq(b, c, name) = (m = LC.unit(b, name); [c.q[k] for k in b.ins[m] if b.kind[b.edges[k][1]] == 'C'])

function raising(seed, cur, rest, rest_body, s)
    b = LC.newborn(false; rest = rest, rest_body = rest_body); c = LC.init(b); noise = LC.Mulberry(seed); steps = Any[]
    first_core = Dict{String,Any}("m1" => nothing, "m2" => nothing)
    for (i, y) in enumerate(LBA.curriculum(cur))
        pq, ps, pa = copy(c.q), copy(c.sg), copy(c.active)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = s.contrast, idle_first = s.idle_first, core_gate = s.core_gate,
                     seen_both = s.seen_both, sed_fade = s.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[])
        for m in ("m1", "m2"); (first_core[m] === nothing && any(>=(1), coreq(b, c, m))) && (first_core[m] = i); end
        push!(steps, Dict("w" => winner(b, o), "ranks" => ranks(b, pq, ps, pa, o), "d" => collect(o.d)))
    end
    same = all(f -> isequal(getfield(c, f), getfield(s.raised, f)), fieldnames(typeof(c)))
    (steps = steps, first_core = first_core, final = Dict(n => edges_into(b, c, n) for n in ("m1", "m2", "m0")), same = same)
end

const REC = Ref{Any}(nothing); const PRE = Ref{Any}(nothing)
LBA.CLAMP[] = (st, y) -> (REC[] === nothing || (S = REC[].s.side[st]; PRE[] = (q = copy(S.c.q), sg = copy(S.c.sg), a = copy(S.c.active), Q = LBA.body_quantity(S.w))); (y, nothing))
LBA.ON_STEP[] = (st, o, c, y) -> (REC[] === nothing || push!(REC[].steps, Dict("t" => st.t + 1, "w" => winner(REC[].s.b, o), "d" => collect(o.d), "Q_before" => PRE[].Q,
    "ranks" => st.t + 1 <= 32 ? ranks(REC[].s.b, PRE[].q, PRE[].sg, PRE[].a, o) : nothing,
    "rb" => (r = LC.unit(REC[].s.b, "rb"); r === nothing ? nothing : PRE[].a[r]))))
function trial(s, p, sch)
    st = AS.initial_state(s, p); REC[] = (s = s, steps = Any[]); death = nothing
    for t in 1:H; AS.step!(st, s, p, sch, Set{Int}()); (st.dead || isempty(LBA.body_sites(s.side[st].w))) && death === nothing && (death = t); end
    x = REC[].steps; REC[] = nothing; delete!(s.side, st); (steps = x, death = death)
end

res = Dict{String,Any}("spec" => "discussion/specs/S35-diag-rb-arms.md r1", "seeds" => SEEDS, "H" => H, "runs" => Any[])
su = LBA.setup_with(H); p = su.params
for seed in SEEDS, arm in (:std, :swap), (lin, rest, rb) in (("N0", false, nothing), ("RA", true, :A), ("RB", true, :B))
    s = org(seed, su, arm; rest = rest, rest_body = rb)
    R = raising(seed, arm, rest, rb, s)
    tr = Dict(sch.name => (x = trial(s, p, sch); Dict("death" => x.death, "steps" => x.steps)) for sch in su.survival)
    push!(res["runs"], Dict("seed" => seed, "arm" => String(arm), "lineage" => lin, "raising_same" => R.same, "raising" => R.steps,
                            "first_core_q" => R.first_core, "raised" => R.final, "trials" => tr))
    println("seed=$seed $arm $lin raising m0 wins $(count(x -> x["w"] == "m0", R.steps)) first core q>=1 $(R.first_core) deaths $([tr[k]["death"] for k in sort(collect(keys(tr)))])")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-diag-rb-arms.json"))
write(out, JSON.json(res)); println("written ", out)
