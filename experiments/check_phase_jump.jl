# S50 judgment (discussion/specs/S50-phase-jump.md r3 §4-§5; predictions-phase-jump.md PJ1-PJ5). Reads results-phase-jump-<mode>.json.
# Usage (from experiments/): julia --project=.. check_phase_jump.jl main    -> results-phase-jump-main-check.json / .out
#                            julia --project=.. check_phase_jump.jl smoke   -> the same on the smoke file, written to a
#                            temporary directory; only the structure is printed (development check of this script).
# The act at a step = the set of patches acted on ('0' none, '1', '2', '3' both); two acts agree when the sets are equal.
include(joinpath(@__DIR__, "phase_jump.jl"))

const CMODE = length(ARGS) >= 1 ? ARGS[1] : error("mode smoke | main")
const INFILE = joinpath(LAB, "experiments", "results-phase-jump-$(CMODE).json")
recs = Dict{String,Any}()
for l in eachline(INFILE)
    d = try JSON.parse(l) catch; nothing end
    d === nothing || (recs[d["key"]] = d)
end
const SEEDS = sort(unique([Int(d["seed"]) for d in values(recs)]))
mean(v) = isempty(v) ? nothing : sum(v) / length(v)
rnd(x, k = 4) = x === nothing ? nothing : round(x; digits = k)
get_run(u, arm, k) = recs["$(u) $(arm)"]["runs"][k]
const LINES = String[]
say(x...) = (s = string(x...); push!(LINES, s); CMODE == "main" && println(s))

out = Dict{String,Any}("mode" => CMODE, "seeds" => SEEDS, "nrecs" => length(recs))
# completeness
out["complete"] = all(haskey(recs, "$(u) $(a)") for u in SEEDS for a in ARMS) && all(d["nruns"] == 11 for d in values(recs))
out["movedOK"] = all(r["movedOK"] for d in values(recs) for r in values(d["runs"]))
say("# S50 check ($(CMODE)): seeds $(SEEDS), records $(length(recs)), complete $(out["complete"]), moved recomputation exact $(out["movedOK"])")

# PJ1: every J = 1000 run is bit-identical (fingerprint) to its J = 0 run
pj1 = [(u, a, Tj, get_run(u, a, runkey(Tj, 1000))["fp"] == get_run(u, a, "J0")["fp"] &&
        get_run(u, a, runkey(Tj, 1000))["acts"] == get_run(u, a, "J0")["acts"]) for u in SEEDS for a in ARMS for Tj in TJS]
out["PJ1"] = Dict("identical" => count(x -> x[4], pj1), "of" => length(pj1), "holds" => all(x -> x[4], pj1),
                  "differ" => [string(x[1:3]) for x in pj1 if !x[4]])
say("PJ1: J1000 = J0 (fingerprint and acts) in ", out["PJ1"]["identical"], "/", length(pj1), " -> ", out["PJ1"]["holds"] ? "成立" : "不成立（作りが誤り、読まない）")

# T0 circuit types
out["types"] = Dict(law => length(unique([get_run(u, law, "J0")["type"] for u in SEEDS])) for law in LAWS)
say("T0 circuit types (of $(length(SEEDS)) seeds): ", out["types"])

# per cell (arm, Tj, J) and window
function cell(arm, Tj, J)
    c = Dict{String,Any}("arm" => arm, "Tj" => Tj, "J" => J)
    per = Dict{String,Any}()
    win = Any[]
    for w in 1:NW
        V = Any[]; Cal = Any[]; Bd = Any[]; As = Any[]; Ds = Any[]; Cs = Any[]; Bs = Any[]; exA = 0; exD = 0; exC = 0; exB = 0
        for u in SEEDS
            b = get_run(u, arm, "J0"); j = get_run(u, arm, runkey(Tj, J))
            a = qA(j["acts"], j["death"], b["acts"], b["death"], Tj, J, w); bb = qB(j["acts"], j["death"], b["acts"], b["death"], Tj, J, w)
            cc = qC(b["acts"], b["death"], Tj, J, w); dd = qD(b["acts"], b["death"], Tj, J, w)
            exA += a.excluded; exD += dd.excluded; exC += cc.excluded; exB += bb.excluded
            push!(As, a.v); push!(Ds, dd.v); push!(Cs, cc.v); push!(Bs, bb.v)
            push!(V, (a.v === nothing || dd.v === nothing) ? nothing : dd.v - a.v)
            push!(Cal, (a.v === nothing || cc.v === nothing) ? nothing : cc.v - a.v)
            push!(Bd, bb.v === nothing ? nothing : 1 - bb.v)
        end
        mv(x) = rnd(mean([v for v in x if v !== nothing]))
        push!(win, Dict("w" => w, "V" => signtest(V), "Cal" => signtest(Cal), "B" => signtest(Bd),
            "meanA" => mv(As), "meanD" => mv(Ds), "meanC" => mv(Cs), "meanB" => mv(Bs), "meanV" => mv(V), "meanCal" => mv(Cal),
            "excludedSteps" => Dict("A" => exA, "D" => exD, "C" => exC, "B" => exB),
            "perSeed" => Dict("A" => rnd.(As), "D" => rnd.(Ds), "C" => rnd.(Cs), "B" => rnd.(Bs))))
    end
    c["windows"] = win
    # first step (Tj) and the first step whose read yields differ
    fs = 0; fy = 0; nfy = 0; dts = Any[]
    for u in SEEDS
        b = get_run(u, arm, "J0"); j = get_run(u, arm, runkey(Tj, J))
        (dead_at(b["death"], Tj) || dead_at(j["death"], Tj)) && continue
        b["acts"][Tj+1] != j["acts"][Tj+1] && (fs += 1)
        ts = findfirst(t -> b["y"][t-KLO+1] != j["y"][t-KLO+1], Tj:KHI-1)
        if ts === nothing
            push!(dts, nothing)
        else
            t = Tj + ts - 1; push!(dts, t - Tj)
            if !(dead_at(b["death"], t) || dead_at(j["death"], t))
                nfy += 1; b["acts"][t+1] != j["acts"][t+1] && (fy += 1)
            end
        end
    end
    c["firstStep"] = Dict("actDiffersAtTj" => fs, "firstYieldDiffOffset" => dts, "actDiffersAtFirstYieldDiff" => fy, "nAtFirstYieldDiff" => nfy)
    # body at Tj + 1000 (same time), scheduled and moved yield in [Tj, Tj + 1000)
    ia = findfirst(==(Tj), collect(TJS))
    sz = [get_run(u, arm, runkey(Tj, J))["countAt"][ia] - get_run(u, arm, "J0")["countAt"][ia] for u in SEEDS]
    c["body"] = Dict("test" => signtest(sz), "meanJump" => rnd(mean([get_run(u, arm, runkey(Tj, J))["countAt"][ia] for u in SEEDS]), 2),
        "meanBase" => rnd(mean([get_run(u, arm, "J0")["countAt"][ia] for u in SEEDS]), 2))
    c["yield"] = Dict("schedJump" => get_run(SEEDS[1], arm, runkey(Tj, J))["schedWin"][string(Tj)], "schedBase" => get_run(SEEDS[1], arm, "J0")["schedWin"][string(Tj)],
        "movedJump" => rnd(mean([get_run(u, arm, runkey(Tj, J))["movedWin"][string(Tj)] for u in SEEDS])),
        "movedBase" => rnd(mean([get_run(u, arm, "J0")["movedWin"][string(Tj)] for u in SEEDS])))
    # death in [Tj, Tj + 2000), the lives dead before Tj removed from both
    live = [u for u in SEEDS if !dead_at(get_run(u, arm, "J0")["death"], Tj)]
    din(d) = d !== nothing && Tj <= d < Tj + 2000
    nj = count(u -> din(get_run(u, arm, runkey(Tj, J))["death"]), live); nb = count(u -> din(get_run(u, arm, "J0")["death"]), live)
    c["death"] = Dict("lives" => length(live), "jump" => nj, "base" => nb, "excess" => nj - nb)
    # kept connections: mean over live steps, before (Tj - 100 .. Tj - 1) and per window, jump and base at the same time
    function km(r, ts)
        v = [r["kept"][t-KLO+1] for t in ts if !dead_at(r["death"], t)]
        return mean(v)
    end
    kpre = rnd(mean([x for x in (km(get_run(u, arm, "J0"), Tj-100:Tj-1) for u in SEEDS) if x !== nothing]), 3)
    kj = [rnd(mean([x for x in (km(get_run(u, arm, runkey(Tj, J)), winsteps(Tj, w)) for u in SEEDS) if x !== nothing]), 3) for w in 1:NW]
    kb = [rnd(mean([x for x in (km(get_run(u, arm, "J0"), winsteps(Tj, w)) for u in SEEDS) if x !== nothing]), 3) for w in 1:NW]
    c["kept"] = Dict("pre" => kpre, "jump" => kj, "base" => kb)
    return c
end

cells = [cell(a, Tj, J) for a in ARMS for Tj in TJS for J in (CELLJ..., 1000)]
out["cells"] = cells
iscell(c) = c["J"] in CELLJ
org = [c for c in cells if c["arm"] != "GREEDY" && iscell(c)]; gr = [c for c in cells if c["arm"] == "GREEDY" && iscell(c)]
nj(cs, w, q, j) = count(c -> c["windows"][w][q]["judge"] == j, cs)
summ(cs, w, q) = Dict(j => nj(cs, w, q, j) for j in ("乱れあり", "逆", "検出不能", "確かめられず"))
out["summary"] = Dict("ORG" => Dict("w1" => Dict(q => summ(org, 1, q) for q in ("V", "Cal", "B")), "w10" => Dict(q => summ(org, 10, q) for q in ("V", "Cal", "B"))),
                      "GREEDY" => Dict("w1" => Dict(q => summ(gr, 1, q) for q in ("V", "Cal", "B")), "w10" => Dict(q => summ(gr, 10, q) for q in ("V", "Cal", "B"))))
pj2 = nj(org, 1, "V", "乱れあり"); pj3 = nj(org, 10, "V", "乱れあり"); pj4 = nj(gr, 1, "V", "乱れあり")
pj5 = [c for c in org if c["death"]["excess"] >= 3]
out["PJ2"] = Dict("count" => pj2, "of" => length(org), "holds" => pj2 > 8)
out["PJ3"] = Dict("count" => pj3, "of" => length(org), "holds" => pj3 < 8)
out["PJ4"] = Dict("count" => pj4, "of" => length(gr), "holds" => pj4 >= 4)
out["PJ5"] = Dict("cells" => ["$(c["arm"]) Tj$(c["Tj"]) J$(c["J"])" for c in pj5], "holds" => isempty(pj5))
ok(x) = x ? "成立" : "不成立"
say("PJ2: ORG window 1 V 乱れあり in $(pj2)/16 (more than 8 needed) -> ", ok(pj2 > 8))
say("PJ3: ORG window 10 V 乱れあり in $(pj3)/16 (fewer than 8 needed) -> ", ok(pj3 < 8))
say("PJ4: GREEDY window 1 V 乱れあり in $(pj4)/8 (at least 4 needed) -> ", ok(pj4 >= 4))
say("PJ5: ORG cells with jump deaths - base deaths >= 3: ", out["PJ5"]["cells"], " -> ", ok(isempty(pj5)))
neg_side = [("$(c["arm"]) Tj$(c["Tj"]) J$(c["J"]) w$w") for c in org for w in 1:NW if c["windows"][w]["V"]["judge"] == "逆"]
out["negativeV"] = neg_side
say("V 逆 (ORG, any window): ", neg_side)
say("summary ", JSON.json(out["summary"]))
say("")
say("cell (arm Tj J): w1 [V judge pos/neg/ties/unver p | Cal | B] meanA meanD meanC meanB ; w10 same ; first step ; body ; yield ; death ; kept")
fmt(t) = "$(t["judge"]) $(t["pos"])/$(t["neg"])/$(t["ties"])/$(t["unverified"]) p$(haskey(t, "p") ? round(t["p"]; digits = 4) : "-")"
for c in cells
    s = "$(rpad(c["arm"], 6)) Tj$(c["Tj"]) J$(lpad(c["J"], 4)):"
    for w in (1, 10)
        x = c["windows"][w]
        s *= "  w$w [V $(fmt(x["V"])) | Cal $(fmt(x["Cal"])) | B $(fmt(x["B"]))] A $(x["meanA"]) D $(x["meanD"]) C $(x["meanC"]) B $(x["meanB"]) exA $(x["excludedSteps"]["A"]) exD $(x["excludedSteps"]["D"]);"
    end
    say(s)
    f = c["firstStep"]
    say("      first: act differs at Tj $(f["actDiffersAtTj"]); first read-yield difference at +$(f["firstYieldDiffOffset"]), act differs there $(f["actDiffersAtFirstYieldDiff"])/$(f["nAtFirstYieldDiff"])",
        "; body Tj+1000 $(c["body"]["meanJump"]) vs $(c["body"]["meanBase"]) $(fmt(c["body"]["test"]))",
        "; sched $(c["yield"]["schedJump"]) vs $(c["yield"]["schedBase"]), moved $(c["yield"]["movedJump"]) vs $(c["yield"]["movedBase"])",
        "; death $(c["death"]["jump"]) vs $(c["death"]["base"]) of $(c["death"]["lives"])",
        "; kept pre $(c["kept"]["pre"]) jump $(c["kept"]["jump"]) base $(c["kept"]["base"])")
    say("      V judges w1..10: ", join([c["windows"][w]["V"]["judge"] for w in 1:NW], " "), "   meanV ", [c["windows"][w]["meanV"] for w in 1:NW])
end
deaths = Dict("$(u) $(a)" => get_run(u, a, "J0")["death"] for u in SEEDS for a in ARMS)
out["baseDeaths"] = deaths
say("baseline deaths: ", JSON.json(deaths))

if CMODE == "main"
    write(joinpath(LAB, "experiments", "results-phase-jump-main-check.out"), join(LINES, "\n") * "\n")
    write(joinpath(LAB, "experiments", "results-phase-jump-main-check.json"), JSON.json(out, 2))
else
    tmp = mktempdir()
    write(joinpath(tmp, "check.out"), join(LINES, "\n") * "\n"); write(joinpath(tmp, "check.json"), JSON.json(out, 2))
    println("smoke check written to ", tmp, ": ", length(LINES), " lines, ", length(cells), " cells, keys ", sort(collect(keys(out))))
    println("PJ1 structure: ", out["PJ1"]["of"], " pairs; types ", out["types"])
end
