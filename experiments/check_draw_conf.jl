# S57 (A1) judgment (discussion/specs/S57-draw-conf.md r2 §3-§6; predictions-draw-conf.md r2 PB0-PB4; freeze-draw-conf.txt freeze 1).
# Usage (from experiments/):
#   julia --project=.. check_draw_conf.jl pilot   §3 / PB0 from draw-conf-out/pilot/*.json  -> results-draw-conf-pilot-check.out / .json
#   julia --project=.. check_draw_conf.jl eval    PB1-PB4 from draw-conf-out/eval/*.json    -> results-draw-conf-eval.out / .json
# The module DrawConfJudge holds the judging rules; draw_conf_grid.jl includes this file for the gates (D3 replay, D4b, D5).
# The draw is re-implemented in S55's check_draw.jl (DrawJudge.redraw, included unchanged); here it is fed the recorded weights.
module DrawConfJudge
using JSON
include(joinpath(@__DIR__, "check_draw.jl"))
using .DrawJudge
const DJ = DrawJudge

const T0 = 800
const HORIZON = 9200
const NBITS = DJ.NBITS

# weights of the arm for the choosing set (cs ordered by (patch, unit index)); conf_s = conf[m] of the members of cs
weights_of(arm, conf_s) = arm == "UNI" ? fill(1, length(conf_s)) : arm == "CONF" ? [1 + c for c in conf_s] : error("no weights for $arm")

drawn_idx(dr) = [i for i in eachindex(dr["t"]) if length(dr["cs"][i]) >= 2 && dr["t"][i] >= T0]
# records of a drawing step: (cs patches, weights, chosen patch)
recs_of(dr) = [(Vector{Int}(dr["cs"][i]), Vector{Int}(dr["w"][i]), Int(dr["chosen"][i])) for i in drawn_idx(dr)]
unequal(w) = length(w) == 2 && w[1] != w[2]
n_unequal(dr) = count(i -> unequal(dr["w"][i]), drawn_idx(dr))

# replay of one run's records from the bit file; the weights must also equal the arm's rule from the recorded conf
function replay(dr, bits, arm)
    ok = 0; bad = 0
    for i in eachindex(dr["t"])
        cs = Vector{Int}(dr["cs"][i])
        if length(cs) < 2 || arm == "DET"
            good = dr["chosen"][i] == dr["det"][i] && dr["nb"][i] == 0 && (length(cs) >= 2 || dr["chosen"][i] == cs[1])
        else
            w = Vector{Int}(dr["w"][i])
            good = w == weights_of(arm, Vector{Int}(dr["conf"][i]))
            if good
                k, used, rej = DJ.redraw(bits, dr["pos"][i], w)
                good = k > 0 && cs[k] == dr["chosen"][i] && rej == dr["rej"][i] && used == dr["nb"][i] * (1 + dr["rej"][i])
            end
        end
        good ? (ok += 1) : (bad += 1)
    end
    return ok, bad
end

# PB1 rule (S55's PA2 rule with the groups keyed by the specified probabilities): key = (cs, weights / gcd).
function judge_groups(recs; minn = 400, alpha = 0.01, band = 0.05, wover = nothing)
    groups = Dict{Tuple{Vector{Int},Vector{Int}},Vector{Int}}()
    for (cs, w0, ch) in recs
        w = wover === nothing ? w0 : wover(cs, w0)
        g = gcd(w); wr = w .÷ g
        v = get!(groups, (cs, wr), zeros(Int, length(cs)))
        i = findfirst(==(ch), cs); i === nothing && error("chosen $ch not in $cs")
        v[i] += 1
    end
    rows = Any[]
    for kk in sort(collect(keys(groups)))
        cs, wr = kk
        o = groups[kk]; n = sum(o); pr = wr ./ sum(wr)
        e = n .* pr; x = sum((o .- e) .^ 2 ./ e); df = length(cs) - 1
        sh = o ./ n; dev = maximum(abs.(sh .- pr))
        push!(rows, Dict{String,Any}("cs" => cs, "w" => wr, "n" => n, "counts" => o, "spec" => pr, "share" => sh, "maxDev" => dev,
            "chi2" => x, "df" => df, "p" => DJ.chi2p(x, df), "judged" => n >= minn, "withinBand" => dev <= band))
    end
    J = [r for r in rows if r["judged"]]
    m = length(J)
    for r in rows; r["holmReject"] = false; end
    if m > 0
        ord = sortperm([r["p"] for r in J])
        for (i, j) in enumerate(ord)
            thr = alpha / (m - i + 1)
            J[j]["holmThreshold"] = thr
            if J[j]["p"] <= thr
                J[j]["holmReject"] = true
            else
                break
            end
        end
    end
    for r in J
        r["matches"] = !r["holmReject"] && r["withinBand"]
    end
    verdict = m == 0 ? "undetectable" : all(r -> r["matches"], J) ? "holds" : "miss"
    return Dict{String,Any}("rows" => rows, "nJudged" => m, "verdict" => verdict, "minn" => minn, "alpha" => alpha, "band" => band)
end

# PB2: per run (CONF), over the drawing steps with unequal weights
function pb2(dr)
    terms = Float64[]; pL = Float64[]; nH = 0; aH = 0; nL = 0; aL = 0
    for i in drawn_idx(dr)
        w = Vector{Int}(dr["w"][i]); unequal(w) || continue
        cs = Vector{Int}(dr["cs"][i]); length(cs) == 2 || error("PB2: choosing set of size $(length(cs))")
        W = sum(w); h = w[1] > w[2] ? 1 : 2; l = 3 - h
        ph = w[h] / W; pl = w[l] / W
        ch = Int(dr["chosen"][i]); Y = dr["ans"][i] == true ? 1.0 : 0.0
        x = 0.0
        if ch == cs[h]
            x = Y / ph; nH += 1; aH += Int(Y)
        elseif ch == cs[l]
            x = -Y / pl; nL += 1; aL += Int(Y)
        else
            error("PB2: chosen not in cs")
        end
        push!(terms, x); push!(pL, pl)
    end
    N = length(terms)
    return Dict{String,Any}("N" => N, "D" => N == 0 ? nothing : sum(terms) / N, "nH" => nH, "ansH" => aH, "nL" => nL, "ansL" => aL,
        "plain" => (nH == 0 || nL == 0) ? nothing : aH / nH - aL / nL, "minPL" => N == 0 ? nothing : minimum(pL), "pL" => pL)
end

# death step counted from T0; alive at the common horizon T0 + 9200 -> 9201
death_step(d) = d === nothing ? HORIZON + 1 : d - T0
# paired sign test over windows, two-sided 5 %, ties dropped, fewer than 8 non-ties = undetectable
function sign_test(a, b; alpha = 0.05, minn = 8)
    length(a) == length(b) || error("sign_test: lengths")
    wins = count(i -> a[i] > b[i], eachindex(a)); losses = count(i -> a[i] < b[i], eachindex(a)); ties = length(a) - wins - losses
    n = wins + losses
    p = n == 0 ? 1.0 : min(1.0, 2 * Float64(sum(binomial(BigInt(n), k) for k in 0:min(wins, losses)) / BigInt(2)^n))
    verdict = n < minn ? "undetectable" : p < alpha ? (wins > losses ? "larger" : "smaller") : "not significant"
    return Dict{String,Any}("wins" => wins, "losses" => losses, "ties" => ties, "nonTies" => n, "p" => p, "verdict" => verdict)
end

alive(death, x) = death === nothing || death > T0 + x
end # module DrawConfJudge

if abspath(PROGRAM_FILE) == @__FILE__
using .DrawConfJudge, JSON
const CJ = DrawConfJudge
const LAB = normpath(joinpath(@__DIR__, ".."))
const EXP = joinpath(LAB, "experiments")
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode pilot | eval")
const LAWS = ("L2", "L2+SF"); const ARMS = ("DET", "UNI", "CONF")
const PILOT = 686:689; const EVALS = 690:725
const L = String[]
say(x...) = (s = string(x...); println(s); push!(L, s))
r3(x) = x === nothing ? nothing : round(x; digits = 3)
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
runfile(dir, law, arm, u) = joinpath(EXP, "draw-conf-out", dir, "$(law)_$(arm)_u$(u).json")
out = Dict{String,Any}()

if MODE == "pilot"
    P = JSON.parsefile(joinpath(EXP, "results-draw-conf-pilot.json"))
    adm = Dict{String,Any}(); pb2ok = Dict{String,Any}()
    for law in LAWS
        o = Dict{String,Any}(); out[law] = o; okLaw = true
        for arm in ARMS
            runs = [JSON.parsefile(runfile("pilot", law, arm, u)) for u in PILOT]
            nal = count(r -> CJ.alive(r["death"], 2000), runs)
            nd = [length(CJ.drawn_idx(r["draws"])) for r in runs]
            ok = nal >= 3 && minimum(nd) >= 200
            okLaw = okLaw && ok
            o[arm] = Dict("alive2000" => nal, "drawSteps" => nd, "meets" => ok)
            say("§3 ", law, " ", rpad(arm, 4), ": alive at T0+2000 ", nal, "/4, drawing steps per window ", join(nd, " "), " (min ", minimum(nd), ") -> ",
                ok ? "meets" : "does not meet")
            if arm == "CONF"
                nu = [CJ.n_unequal(r["draws"]) for r in runs]
                o["CONFunequal"] = nu; pb2ok[law] = all(>=(100), nu)
                say("§3 ", law, " CONF drawing steps with unequal weights per window ", join(nu, " "), " -> ", pb2ok[law] ? "meets (>= 100 in all 4)" : "does not meet")
            end
        end
        adm[law] = okLaw; o["admit"] = okLaw; o["PB2admit"] = pb2ok[law]
        agree = P["admit"][law] == okLaw && P["pb2admit"][law] == pb2ok[law]
        say("§3 decision ", law, ": ", okLaw ? "admit (three arms to the evaluation windows)" : "not admit (cannot be measured)",
            "; PB2 ", pb2ok[law] ? "admissible" : "below the pre-set admission condition", "; grid decision agrees: ", agree)
        o["agreesWithGrid"] = agree
    end
    pb0 = all(values(adm)) && all(values(pb2ok))
    out["admit"] = adm; out["pb2admit"] = pb2ok; out["PB0"] = pb0
    say("PB0 verdict: ", pb0 ? "holds" : "miss")
    write(joinpath(EXP, "results-draw-conf-pilot-check.out"), join(L, "\n") * "\n")
    write(joinpath(EXP, "results-draw-conf-pilot-check.json"), JSON.json(out, 2))
elseif MODE == "eval"
    P = JSON.parsefile(joinpath(EXP, "results-draw-conf-pilot.json"))
    bitcache = Dict{Int,Any}()
    bitsof(u) = get!(() -> CJ.DJ.load_bits(joinpath(EXP, "draw-conf-bits", "u$(u).bits")), bitcache, u)
    for law in LAWS
        o = Dict{String,Any}(); out[law] = o
        if !P["admit"][law]
            say("==== law ", law, ": not admitted by the pilot -> PB1-PB4 cannot be measured (no evaluation run)")
            o["admitted"] = false
            continue
        end
        o["admitted"] = true
        us = collect(EVALS)
        R = Dict(arm => [JSON.parsefile(runfile("eval", law, arm, u)) for u in us] for arm in ARMS)
        say("==== law ", law, "  (windows ", first(us), "-", last(us), ", n = ", length(us), ")")
        for arm in ARMS
            v = R[arm]; dth = [x["death"] for x in v]
            say("   ", rpad(arm, 4), " alive T0+500 ", count(d -> CJ.alive(d, 500), dth), "/", length(us), ", T0+2000 ", count(d -> CJ.alive(d, 2000), dth),
                "/", length(us), ", horizon ", count(d -> d === nothing, dth), "/", length(us), " | death steps from T0: ", join([CJ.death_step(d) for d in dth], " "))
            say("        body (countAt T0+500/2000/9200): ", join([join(x["countAt"], "/") for x in v], " "))
            say("        answered share of acts from T0 (mean ", r3(mean([x["answered"] for x in v])), "): ", join(r3.([x["answered"] for x in v]), " "))
            ag = filter(!isnan, Float64[something(x["agreeDET"], NaN) for x in v])
            say("        drawing steps: ", join([x["drawSteps"] for x in v], " "), " | agreement with DET's choice at the same state (mean ", r3(mean(ag)), ")",
                " | rejected share of bit groups (mean ", r3(mean(filter(!isnan, Float64[something(x["rejShare"], NaN) for x in v]))), ")")
            if arm == "CONF"
                hist = Dict{String,Int}()
                for x in v, i in CJ.drawn_idx(x["draws"]); k = string(x["draws"]["w"][i]); hist[k] = get(hist, k, 0) + 1; end
                top = sort(collect(hist); by = p -> -p[2])
                say("        CONF weights [patch1, patch2] over drawing steps (", length(hist), " kinds), top: ", join(["$(k)x$(n)" for (k, n) in top[1:min(12, end)]], " "))
                o["CONFweights"] = hist
            end
            o[arm] = Dict("death" => dth, "deathStep" => [CJ.death_step(d) for d in dth], "countAt" => [x["countAt"] for x in v],
                "answered" => [x["answered"] for x in v], "drawSteps" => [x["drawSteps"] for x in v], "agreeDET" => [x["agreeDET"] for x in v],
                "rejShare" => [x["rejShare"] for x in v])
        end
        # PB1
        pb1 = true
        for arm in ("UNI", "CONF")
            rs = reduce(vcat, [CJ.recs_of(x["draws"]) for x in R[arm]])
            j = CJ.judge_groups(rs; minn = 400)
            for r in j["rows"]
                r["judged"] || continue
                say("   PB1 ", arm, " cs ", r["cs"], " w ", r["w"], ": n ", r["n"], ", shares ", r3.(r["share"]), " vs ", r3.(r["spec"]), ", max dev ", r3(r["maxDev"]),
                    ", uncorrected p ", r3(r["p"]), ", Holm reject at 1 %: ", r["holmReject"], ", within 0.05: ", r["withinBand"])
            end
            nsmall = count(r -> !r["judged"], j["rows"]); dsmall = sum((r["n"] for r in j["rows"] if !r["judged"]); init = 0)
            say("   PB1 ", arm, ": groups with fewer than 400 draws (reported, not judged): ", nsmall, " groups, ", dsmall, " draws")
            o["PB1 " * arm] = j
            pb1 = pb1 && j["verdict"] == "holds"
            say("   PB1 ", law, " ", arm, " goodness of fit: ", j["verdict"], " (", j["nJudged"], " group(s) judged)")
        end
        tot = 0; bad = 0
        for arm in ARMS, (i, u) in enumerate(us)
            okn, badn = CJ.replay(R[arm][i]["draws"], bitsof(u), arm); tot += okn + badn; bad += badn
        end
        pb1 = pb1 && bad == 0
        o["PB1"] = Dict("holds" => pb1, "replayRecords" => tot, "replayBad" => bad)
        say("PB1 verdict ", law, ": ", pb1 ? "holds" : "miss", " (replay from the bit files: ", tot - bad, "/", tot, " records reproduced)")
        # PB2
        if !P["pb2admit"][law]
            say("PB2 verdict ", law, ": cannot be measured (below the pre-set admission condition of the pilot; not a proof that CONF equals UNI)")
            o["PB2"] = Dict("verdict" => "cannot be measured")
        else
            q = [CJ.pb2(x["draws"]) for x in R["CONF"]]
            keep = [i for i in eachindex(q) if q[i]["N"] >= 100]
            Ds = [q[i]["D"] for i in keep]
            st = CJ.sign_test(Ds, zeros(length(Ds)))
            say("   PB2 per window N: ", join([x["N"] for x in q], " "), " | dropped (N < 100): ", length(q) - length(keep))
            say("   PB2 per window D: ", join([r3(q[i]["D"]) for i in keep], " "), " (median ", r3(sort(Ds)[cld(length(Ds), 2)]), ")")
            say("   PB2 plain difference of answered shares (heavier chosen - lighter chosen): ", join([r3(q[i]["plain"]) for i in keep], " "))
            allpl = reduce(vcat, [q[i]["pL"] for i in keep]); spl = sort(allpl)
            qt(f) = spl[clamp(round(Int, f * length(spl)), 1, length(spl))]
            say("   PB2 p_L: min ", r3(spl[1]), ", 5 % ", r3(qt(0.05)), ", 25 % ", r3(qt(0.25)), ", median ", r3(qt(0.5)), ", 75 % ", r3(qt(0.75)), ", max ", r3(spl[end]),
                " (", length(spl), " steps)")
            ok = st["verdict"] == "larger"
            say("PB2 verdict ", law, ": ", ok ? "holds" : "miss", " (D > 0 in ", st["wins"], ", D < 0 in ", st["losses"], ", ties ", st["ties"], ", p ", r3(st["p"]), ", ", st["verdict"], ")")
            o["PB2"] = Dict("perWindow" => [delete!(copy(x), "pL") for x in q], "dropped" => length(q) - length(keep), "sign" => st, "holds" => ok,
                "minPL" => spl[1])
        end
        # PB3, PB4
        ds(arm) = [CJ.death_step(x["death"]) for x in R[arm]]
        for (a, b, tag, pred) in (("UNI", "DET", "PB3", law == "L2" ? "larger" : nothing), ("CONF", "UNI", "PB4", law == "L2" ? "undetectable" : nothing),
                                  ("CONF", "DET", "PB4", law == "L2" ? "larger" : nothing))
            st = CJ.sign_test(ds(a), ds(b))
            res = pred === nothing ? "no prediction (reported)" : st["verdict"] == pred ? "holds" : "miss"
            say(tag, " verdict ", law, " ", a, " vs ", b, " (death step): ", res, " (predicted ", something(pred, "-"), "; wins ", st["wins"], ", losses ", st["losses"],
                ", ties ", st["ties"], ", non-ties ", st["nonTies"], ", p ", r3(st["p"]), ", result ", st["verdict"], ")")
            o["$tag $a vs $b"] = merge(st, Dict("predicted" => pred, "result" => res))
        end
    end
    write(joinpath(EXP, "results-draw-conf-eval.out"), join(L, "\n") * "\n")
    write(joinpath(EXP, "results-draw-conf-eval.json"), JSON.json(out, 2))
else
    error("mode pilot | eval")
end
end
