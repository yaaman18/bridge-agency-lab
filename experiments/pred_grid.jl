# S46 (spec discussion/specs/S46-pred-grid.md r2): when does prediction hold? Observation and intervention, table predictors,
# per receptor, horizons 1..32, keys R_t / H4 / H4+plan / R_t+plan. Interventions: at fork points t = 32:32:352 a copy of the
# state (the noise rng included) runs 32 updates under 5 plans: m0/m1/m2 only (the other two motors silenced; the firing is
# left to the system), all silenced, natural (no silencing). G1 (g1_school.jl's org_g1; shared files are not edited).
# STAGE=smoke (train seeds SEEDS_TRAIN, gates only) | explore (train 511-530, explore 531-540) | confirm (+ 541-560, after
# the main freeze). Writes experiments/results-pred-grid-<STAGE>.json.
ENV["SEEDS"] = ""; ENV["OUT"] = "/dev/null"
include(joinpath(@__DIR__, "g1_school.jl"))
using JSON, SHA, Dates
const STAGE = get(ENV, "STAGE", "smoke")
const TRAIN = parse.(Int, split(get(ENV, "SEEDS_TRAIN", STAGE == "smoke" ? "511,512" : join(511:530, ",")), ","))
const EXPLORE = STAGE == "smoke" ? Int[] : collect(531:540)
const CONFIRM = STAGE == "confirm" ? collect(541:560) : Int[]
const FORKS = 32:32:352; const LB = 32; const KS = (1, 2, 4, 8, 16, 32)
const PLANS = ["m0only", "m1only", "m2only", "allsil", "natural"]
const RN = ["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "rb"]; const MN = ["m0", "m1", "m2"]
const IRB = 9; const IR6 = 6; const IR5 = 5
if STAGE == "confirm"   # the confirm losses only after the main freeze (spec §5)
    fz = joinpath(@__DIR__, "freeze-pred-grid.txt"); isfile(fz) || error("confirm needs freeze-pred-grid.txt")
    for l in readlines(fz)
        (startswith(l, "#") || isempty(strip(l))) && continue
        h, f = split(l; limit = 2); f = strip(f)
        bytes2hex(sha256(read(joinpath(@__DIR__, f)))) == h || error("freeze sha mismatch: $f")
    end
end

# ---------------------------------------------------------------- recording (natural runs, snapshots, branches)
const POSTG = Ref{Any}(nothing); const WATCHG = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCHG[] && (POSTG[] = copy(o.acting)))
function step1!(s, p, sch, st, sil, ri, mi)
    WATCHG[] = st; POSTG[] = nothing; AS.step!(st, s, p, sch, sil); WATCHG[] = nothing
    acting = POSTG[] === nothing ? Int[] : [m for m in POSTG[] if m in mi]
    (R = BitVector(st.active[ri]), act = [findfirst(==(m), mi) for m in acting], alive = !st.dead, full = copy(st.active))
end
silset(plan, mi) = plan == "m0only" ? Set(mi[[2, 3]]) : plan == "m1only" ? Set(mi[[1, 3]]) : plan == "m2only" ? Set(mi[[1, 2]]) :
                   plan == "allsil" ? Set(mi) : plan == "natural" ? Set{Int}() : plan == "m0only_nosil" ? Set{Int}() : error(plan)
function run_traj(s, p, sch)
    b = s.b; ri = [LC.unit(b, r) for r in RN]; mi = [LC.unit(b, m) for m in MN]; R5 = LC.unit(b, "r5")
    st = AS.initial_state(s, p); S = s.side[st]; nat = Any[]; snaps = Dict{Int,Any}(); tr = Vector{Vector{Bool}}()
    for u in 1:H
        push!(nat, step1!(s, p, sch, st, Set{Int}(), ri, mi))
        push!(tr, [nat[end].full[x] for x in eachindex(nat[end].full) if x != R5])
        u in FORKS && nat[end].alive && (snaps[u] = deepcopy((st, S)))
    end
    delete!(s.side, st)
    br = Dict{Tuple{Int,String},Any}()
    for (t, snap) in snaps, plan in vcat(PLANS, ["m0only_nosil"])   # the negative control at every fork (smoke r2)
        st2, S2 = deepcopy(snap); s.side[st2] = S2; sil = silset(plan, mi)
        br[(t, plan)] = [step1!(s, p, sch, st2, sil, ri, mi) for j in 1:min(LB, H - t)]
        delete!(s.side, st2)
    end
    (nat = nat, br = br, traj = string(hash(tr)), forks = sort(collect(keys(snaps))))
end

# ---------------------------------------------------------------- examples (key values from the natural run at times <= t)
H4key(nat, t) = (t < 4 ? nothing : BitVector(vcat([nat[v].R for v in t-3:t]...)))
Rkey(nat, t) = nat[t].R
const KEYF = Dict("R" => (nat, t, plan) -> Rkey(nat, t), "H4" => (nat, t, plan) -> H4key(nat, t),
                  "H4plan" => (nat, t, plan) -> (H4key(nat, t), plan), "Rplan" => (nat, t, plan) -> (Rkey(nat, t), plan))
const KEYSRC = Dict("R" => t -> [t], "H4" => t -> collect(t-3:t), "H4plan" => t -> collect(t-3:t), "Rplan" => t -> [t])
"""Examples (seed, key value, target R) of one dataset: :int (branches, alive at t+k) or :nat (natural u with alive u+k)."""
function examples(D, seeds, ds, keyname, k; plans = PLANS)
    out = Any[]; f = KEYF[keyname]
    for sd in seeds, (key, rec) in D[sd]
        if ds == :int
            for t in rec.forks, plan in plans
                bb = rec.br[(t, plan)]; k <= length(bb) && bb[k].alive || continue
                push!(out, (seed = sd, key = f(rec.nat, t, plan), y = bb[k].R, t = t, plan = plan, traj = key))
            end
        else
            for u in 4:H-k
                rec.nat[u+k].alive || continue
                push!(out, (seed = sd, key = f(rec.nat, u, "natural"), y = rec.nat[u+k].R, t = u, plan = "natural", traj = key))
            end
        end
    end
    out
end
lap(c, n) = (c .+ 1) ./ (n + 2)
function fit(ex)
    tab = Dict{Any,Tuple{Vector{Float64},Int}}(); on = zeros(9)
    for e in ex; on .+= e.y; a = get(tab, e.key, (zeros(9), 0)); tab[e.key] = (a[1] .+ e.y, a[2] + 1); end
    (tab = tab, b0 = on ./ max(length(ex), 1))
end
pred(m, key) = haskey(m.tab, key) ? lap(m.tab[key][1], m.tab[key][2]) : m.b0
sqerr(m, e) = (pred(m, e.key) .- e.y) .^ 2
function loss(m, ex)
    isempty(ex) && return (per = fill(NaN, 9), n = 0, cov = NaN)
    se = zeros(9); seen = 0; for e in ex; se .+= sqerr(m, e); seen += haskey(m.tab, e.key); end
    (per = se ./ length(ex), n = length(ex), cov = seen / length(ex))
end
"""Seed bootstrap of the mean of d (one value per example), the seed's examples kept together; Mulberry(46)."""
function boot(seed_of, d; B = 1000)
    seeds = unique(seed_of); bys = Dict(s => Float64[] for s in seeds)
    for (s, x) in zip(seed_of, d); push!(bys[s], x); end
    r = LC.Mulberry(46); ms = Float64[]
    for _ in 1:B
        tot = 0.0; n = 0
        for _ in seeds; s = seeds[1 + floor(Int, r() * length(seeds))]; tot += sum(bys[s]); n += length(bys[s]); end
        push!(ms, tot / n)
    end
    sort!(ms); (lo = ms[25], hi = ms[976], mean = sum(d) / length(d))
end

# ---------------------------------------------------------------- run
su = LBA.setup_with(H); p = su.params
D = Dict{Int,Dict{String,Any}}()
for sd in vcat(TRAIN, EXPLORE, CONFIRM)
    D[sd] = Dict{String,Any}()
    for cur in (:std, :swap)
        s = org_g1(sd, su, cur, school_perm(sd))
        for sch in su.survival; D[sd]["$(cur)-$(sch.name)"] = run_traj(s, p, sch); end
    end
end
res = Dict{String,Any}("spec" => "discussion/specs/S46-pred-grid.md r2", "stage" => STAGE, "train" => TRAIN, "explore" => EXPLORE, "confirm" => CONFIRM,
                       "time" => string(now()))
# ---- gates' data
g1rec = JSON.parsefile(joinpath(@__DIR__, "results-g1-school.json"))
g1idx = Dict((r["seed"], "$(a)-$(sn)") => t for r in g1rec["runs"] for a in ("std", "swap") for (sn, t) in r["arms"][a]["trials"])
chk = [(sd, k) for sd in keys(D) for k in keys(D[sd]) if haskey(g1idx, (sd, k))]
res["replay"] = Dict("checked" => length(chk), "match" => count(x -> g1idx[x]["traj"] == D[x[1]][x[2]].traj && g1idx[x]["alive"] == D[x[1]][x[2]].nat[H].alive, chk))
natok = 0; natn = 0; silok = 0; siln = 0; allsilok = true; r5cmp = 0; r5bad = 0; nosil_fails_gate = Bool[]
for sd in keys(D), (key, rec) in D[sd], t in rec.forks
    bnat = rec.br[(t, "natural")]; global natn += 1
    global natok += all(j -> bnat[j].full == rec.nat[t+j].full && bnat[j].alive == rec.nat[t+j].alive, eachindex(bnat))
    for (plan, allowed) in (("m0only", 1), ("m1only", 2), ("m2only", 3))
        global siln += 1; global silok += all(x -> all(==(allowed), x.act), rec.br[(t, plan)])
    end
    global allsilok &= all(x -> isempty(x.act), rec.br[(t, "allsil")])
    # the negative control only where it can bite (smoke r2): forks whose natural branch has an act of m1 or m2
    if any(x -> any(!=(1), x.act), bnat)
        push!(nosil_fails_gate, !all(x -> all(==(1), x.act), rec.br[(t, "m0only_nosil")]))
    end
    for j in 1:length(bnat)
        all(pl -> rec.br[(t, pl)][j].alive, PLANS) || continue
        global r5cmp += 1; global r5bad += length(unique(rec.br[(t, pl)][j].R[IR5] for pl in PLANS)) > 1
    end
end
res["natural_branch_equal"] = Dict("n" => natn, "ok" => natok)
res["silence"] = Dict("n" => siln, "ok" => silok, "allsil_no_act" => allsilok, "negative_nosil_caught" => nosil_fails_gate)
res["r5_common"] = Dict("compared_updates" => r5cmp, "mismatch" => r5bad)
# the key source times <= t, and the negative control (a key that reads t+1)
res["key_times_ok"] = all(kn -> all(t -> all(<=(t), KEYSRC[kn](t)), FORKS), keys(KEYSRC))
res["key_times_negative_caught"] = !all(<=(32), collect(32-2:32+1))
# leak test: tables from the train seeds only; rewriting a copy of the non-train records leaves the tables unchanged
nontrain = setdiff(collect(keys(D)), TRAIN)
mA = fit(examples(D, TRAIN, :int, "H4plan", 8))
if !isempty(nontrain)
    D2 = deepcopy(D)
    for sd in nontrain, (key, rec) in D2[sd]; for x in rec.nat; x.R .= .!x.R; end; end
    mB = fit(examples(D2, TRAIN, :int, "H4plan", 8)); res["leak_tables_unchanged"] = mA.tab == mB.tab && mA.b0 == mB.b0
else
    res["leak_tables_unchanged"] = nothing
end
# bootstrap unit
bu1 = boot(repeat(1:10; inner = 3), fill(0.01, 30)); bu2 = boot(repeat(1:10; inner = 2), repeat([0.01, -0.01], 10))
res["boot_unit"] = Dict("all_positive_excludes_0" => bu1.lo > 0, "half_includes_0" => bu2.lo <= 0 <= bu2.hi)
# ---- the grid (exploratory description) on explore (and confirm in the confirm stage)
evalsets = filter(x -> !isempty(x[2]), [("explore", EXPLORE), ("confirm", CONFIRM)])
grid = Dict{String,Any}()
for (ds, dname) in ((:nat, "nat"), (:int, "int")), k in KS, kn in (ds == :nat ? ("R", "H4") : ("R", "H4", "H4plan", "Rplan"))
    m = fit(examples(D, TRAIN, ds, kn, k))
    for (en, es) in evalsets
        l = loss(m, examples(D, es, ds, kn, k)); grid["$dname-k$k-$kn-$en"] = Dict("per" => l.per, "n" => l.n, "cov" => l.cov)
    end
end
res["grid"] = grid
deaths = Dict{String,Int}()
for sd in vcat(EXPLORE, CONFIRM), (key, rec) in D[sd], t in rec.forks, pl in PLANS, k in KS
    bb = rec.br[(t, pl)]; k <= length(bb) || continue
    deaths["$(pl)-k$k"] = get(deaths, "$(pl)-k$k", 0) + !bb[k].alive
end
res["branch_deaths_eval"] = deaths
# ---- the primary comparisons, on each evaluation set (judged on confirm only, the checker)
function primaries(es)
    out = Dict{String,Any}()
    # PH1: pairs (m1,m0) and (m2,m0) alive at t+8; disagreement of rb at k = 1 and k = 8 on the same pairs
    n = 0; d1 = 0; d8 = 0; bykind = Dict("m1" => [0, 0, 0], "m2" => [0, 0, 0])
    for sd in es, (key, rec) in D[sd], t in rec.forks, (pl, kind) in (("m1only", "m1"), ("m2only", "m2"))
        a = rec.br[(t, pl)]; b = rec.br[(t, "m0only")]; (length(a) >= 8 && a[8].alive && b[8].alive) || continue
        n += 1; x1 = a[1].R[IRB] != b[1].R[IRB]; x8 = a[8].R[IRB] != b[8].R[IRB]; d1 += x1; d8 += x8
        bykind[kind] .+= [1, x1, x8]
    end
    out["PH1"] = Dict("pairs" => n, "frac_k1" => n == 0 ? nothing : d1 / n, "frac_k8" => n == 0 ? nothing : d8 / n, "by_kind" => bykind)
    # PH2: rb, k = 8, intervention, H4+plan vs H4 (tables from the train seeds), seed bootstrap of the difference
    mP = fit(examples(D, TRAIN, :int, "H4plan", 8)); mN = fit(examples(D, TRAIN, :int, "H4", 8))
    eP = examples(D, es, :int, "H4plan", 8); eN = examples(D, es, :int, "H4", 8)
    @assert length(eP) == length(eN) && all(i -> eP[i].seed == eN[i].seed && eP[i].t == eN[i].t && eP[i].plan == eN[i].plan, eachindex(eP))
    d = [sqerr(mN, eN[i])[IRB] - sqerr(mP, eP[i])[IRB] for i in eachindex(eP)]
    bt = boot([e.seed for e in eP], d)
    out["PH2"] = Dict("n" => length(d), "diff_mean" => bt.mean, "ci" => [bt.lo, bt.hi], "L_H4" => loss(mN, eN).per[IRB], "L_H4plan" => loss(mP, eP).per[IRB])
    # PH5 (added after the exploration, main freeze): rb, k = 32, intervention, R_t+plan vs R_t, d = e(R_t) - e(R_t+plan)
    mRp = fit(examples(D, TRAIN, :int, "Rplan", 32)); mR0 = fit(examples(D, TRAIN, :int, "R", 32))
    fP = examples(D, es, :int, "Rplan", 32); fN = examples(D, es, :int, "R", 32)
    @assert length(fP) == length(fN) && all(i -> fP[i].seed == fN[i].seed && fP[i].t == fN[i].t && fP[i].plan == fN[i].plan, eachindex(fP))
    d5 = [sqerr(mR0, fN[i])[IRB] - sqerr(mRp, fP[i])[IRB] for i in eachindex(fP)]
    b5 = boot([e.seed for e in fP], d5)
    out["PH5"] = Dict("n" => length(d5), "diff_mean" => b5.mean, "ci" => [b5.lo, b5.hi], "L_R" => loss(mR0, fN).per[IRB], "L_Rplan" => loss(mRp, fP).per[IRB])
    # transfer to the natural plan (the same tables, the natural branches only)
    nP = [e for e in eP if e.plan == "natural"]; nN = [e for e in eN if e.plan == "natural"]
    out["natural_transfer"] = Dict("n" => length(nP), "L_H4" => loss(mN, nN).per[IRB], "L_H4plan" => loss(mP, nP).per[IRB])
    # PH3: natural, r6, k = 1, R vs H4
    mR = fit(examples(D, TRAIN, :nat, "R", 1)); mH = fit(examples(D, TRAIN, :nat, "H4", 1))
    out["PH3"] = Dict("L_R" => loss(mR, examples(D, es, :nat, "R", 1)).per[IR6], "L_H4" => loss(mH, examples(D, es, :nat, "H4", 1)).per[IR6])
    # PH4: H4+plan, rb, k = 8, absolute loss on the fixed evaluation examples, train sets S5 ⊂ S10 ⊂ S20
    sizes = Dict{String,Any}()
    for (nm, ss) in (("S5", TRAIN[1:min(5, end)]), ("S10", TRAIN[1:min(10, end)]), ("S20", TRAIN))
        l = loss(fit(examples(D, ss, :int, "H4plan", 8)), eP); sizes[nm] = Dict("L" => l.per[IRB], "n" => l.n, "train" => ss)
    end
    out["PH4"] = sizes
    out
end
for (en, es) in evalsets; res["primary_$en"] = primaries(es); end
res["confirm_computed"] = STAGE == "confirm"
out = get(ENV, "RES", joinpath(@__DIR__, "results-pred-grid-$STAGE.json")); write(out, JSON.json(res))
println("replay ", res["replay"], " natural branch ", res["natural_branch_equal"], " silence ", (res["silence"]["n"], res["silence"]["ok"], res["silence"]["allsil_no_act"], res["silence"]["negative_nosil_caught"]))
println("r5 common ", res["r5_common"], " key times ", res["key_times_ok"], " leak unchanged ", res["leak_tables_unchanged"], " boot unit ", res["boot_unit"])
for (en, _) in evalsets; println("primary $en ", JSON.json(res["primary_$en"])); end
println("written ", out)
