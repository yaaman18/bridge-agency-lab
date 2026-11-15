# S53b judgment (discussion/specs/S53b-stake-fix.md r2 §2-§3; predictions-stake-fix.md r2 PF1-PF4). Reads results-stake-fix-<mode>.json.
# Usage (from experiments/): julia --project=.. check_stake_fix.jl main    -> results-stake-fix-main-check.json / .out
#                            julia --project=.. check_stake_fix.jl smoke   (script test only; trial windows, no claim)
# signtest is copied from check_stake.jl (from check_pa_grid.jl); labels mapped to larger / smaller / undetectable.
# Alive at T0 + x: death === nothing or death > T0 + x (a run with death = T0 + x has body 0 at that count).
using JSON

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode smoke | main")
const ODIR = length(ARGS) >= 2 ? ARGS[2] : joinpath(LAB, "experiments")
const T0 = 800; const XI = Dict(500 => 1, 2000 => 2, 9200 => 3)
const LAWS = ("L2", "L2+SF"); const LAMS = (0, 2, 8); const ARMS = ("ORG", "ORG-FIX")
const READING_LIMIT = "Reading limit (frozen): G is the body gap on windows where all four runs are alive; it is not the total worth of updating including death, and survivor selection depends on arm, s and lambda."

recs = Dict{String,Any}()
for l in eachline(joinpath(LAB, "experiments", "results-stake-fix-$(MODE).json"))
    d = try JSON.parse(l) catch; nothing end
    d === nothing || (recs[d["key"]] = d)
end
# s = 0 has no levy for any lambda: the point s0 lam0 stands for s0 lam2 and s0 lam8
rec(s, lam, law) = recs["s$(s) lam$(s == 0 ? 0 : lam) | $(law)"]

function signtest(a, b)
    pos = count(i -> a[i] > b[i], eachindex(a)); neg = count(i -> a[i] < b[i], eachindex(a)); n = pos + neg
    n < 8 && return Dict("pos" => pos, "neg" => neg, "judge" => "検出不能")
    k = min(pos, neg); p = min(1.0, 2 * sum(binomial(big(n), i) for i in 0:k) / big(2)^n)
    j = p <= 0.05 ? (pos > neg ? "上積みあり" : "上積みなし") : "検出不能"
    return Dict("pos" => pos, "neg" => neg, "p" => Float64(p), "judge" => j)
end
const JMAP = Dict("上積みあり" => "larger", "上積みなし" => "smaller", "検出不能" => "undetectable")
st(a, b) = (d = signtest(a, b); d["dir"] = JMAP[d["judge"]]; d)

S(r, arm, u, x) = r[arm][u]["countAt"][XI[x]]
dw(r, arm, u) = r[arm][u]["deathW"]
alive(r, arm, u, x) = (d = r[arm][u]["death"]; d === nothing || d > T0 + x)
G(r, u, x) = S(r, "ORG", u, x) - S(r, "ORG-FIX", u, x)
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
r3(x) = x === nothing ? nothing : round(x; digits = 3)

const L = String[]
say(x...) = (s = string(x...); println(s); push!(L, s))
out = Dict{String,Any}()
for law in LAWS
    o = Dict{String,Any}(); out[law] = o
    us = string.(rec(0, 0, law)["evals"])
    say("==== law ", law, "  (windows ", join(us, ","), ", n = ", length(us), ")")
    # reported without prediction
    for s in 0:3, lam in (s == 0 ? (0,) : LAMS)
        r = rec(s, lam, law)
        ym = Dict(a => mean([mean(r[a][u]["rep"]["yieldMean"]) for u in us]) for a in ARMS)
        lq = Dict(a => sum(r[a][u]["levyReq"] for u in us) for a in ARMS)
        lt = Dict(a => sum(r[a][u]["levyTaken"] for u in us) for a in ARMS)
        ag = [r["ORG-FIX"][u]["agree"] for u in us]; aga = [r["ORG-FIX"][u]["agreeAlive"] for u in us]
        kc = count(u -> r["ORG-FIX"][u]["keptConst"], us)
        say("s$s lam$lam M=$(r["M"]) levy/step=$(r["levyAmount"])  realized yield mean (from T0): ORG $(r3(ym["ORG"])), ORG-FIX $(r3(ym["ORG-FIX"]))",
            "  levy requested / taken: ORG $(r3(lq["ORG"])) / $(r3(lt["ORG"])), ORG-FIX $(r3(lq["ORG-FIX"])) / $(r3(lt["ORG-FIX"]))")
        say("   act alike ORG vs ORG-FIX (share of steps T0..end): ", join(r3.(ag), " "), " | while both alive: ", join(r3.(aga), " "),
            " | ORG-FIX kept constant after T0: ", kc, "/", length(us))
        for a in ARMS
            say("   ", rpad(a, 8), " S@T0+500: ", join([S(r, a, u, 500) for u in us], " "), " | S@T0+2000: ", join([S(r, a, u, 2000) for u in us], " "),
                " | S@9200: ", join([S(r, a, u, 9200) for u in us], " "), " | deathW: ", join([dw(r, a, u) for u in us], " "))
        end
        o["s$s lam$lam"] = Dict("yieldMean" => ym, "levyReq" => lq, "levyTaken" => lt, "agree" => ag, "agreeAlive" => aga, "keptConst" => kc)
    end
    # PF1: common-set eligibility, frozen order G2000, else G500, else undetectable
    prim = Dict{Int,Any}()
    for lam in LAMS
        r0 = rec(0, lam, law); r3_ = rec(3, lam, law)
        cs(x) = [u for u in us if alive(r0, "ORG", u, x) && alive(r0, "ORG-FIX", u, x) && alive(r3_, "ORG", u, x) && alive(r3_, "ORG-FIX", u, x)]
        c2 = cs(2000); c5 = cs(500)
        q = length(c2) >= 8 ? ("G2000", 2000, c2) : length(c5) >= 8 ? ("G500", 500, c5) : ("undetectable", nothing, String[])
        prim[lam] = Dict{String,Any}("quantity" => q[1], "x" => q[2], "windows" => q[3], "nCommon2000" => length(c2), "nCommon500" => length(c5))
        say("PF1 lam$lam: common set alive at T0+2000: ", length(c2), " ", c2, "  at T0+500: ", length(c5), "  -> primary quantity ", q[1])
    end
    pf1 = prim[0]["nCommon2000"] >= 8 && prim[2]["nCommon2000"] >= 8 && prim[8]["nCommon2000"] < 8
    o["PF1"] = Dict("primary" => prim, "holds" => pf1)
    say("PF1 verdict ", law, ": ", pf1 ? "holds" : "miss", "  (predicted: lam0 and lam2 >= 8 at T0+2000, lam8 < 8; got ",
        prim[0]["nCommon2000"], ", ", prim[2]["nCommon2000"], ", ", prim[8]["nCommon2000"], ")")
    # PF2: s = 0, S_ORG vs S_FIX at T0+2000 over all windows (0 if dead); beside: on windows where both arms are alive at T0+2000
    r0 = rec(0, 0, law)
    t2 = st([S(r0, "ORG", u, 2000) for u in us], [S(r0, "ORG-FIX", u, 2000) for u in us])
    b2 = [u for u in us if alive(r0, "ORG", u, 2000) && alive(r0, "ORG-FIX", u, 2000)]
    t2b = st([S(r0, "ORG", u, 2000) for u in b2], [S(r0, "ORG-FIX", u, 2000) for u in b2])
    want2 = law == "L2" ? "larger" : "undetectable"
    o["PF2"] = merge(t2, Dict("predicted" => want2, "holds" => t2["dir"] == want2, "bothAlive" => t2b, "nBothAlive" => length(b2)))
    say("PF2 verdict ", law, ": ", t2["dir"] == want2 ? "holds" : "miss", "  s0 S_ORG vs S_FIX at T0+2000: ", t2["dir"], " (predicted ", want2, ")  ", t2,
        "   beside, both alive (", length(b2), "): ", t2b)
    # PF3: G(s3) - G(s0) on the primary quantity, per lambda
    say(READING_LIMIT)
    t3 = Dict{Int,Any}()
    for lam in LAMS
        pq = prim[lam]
        if pq["x"] === nothing
            t3[lam] = Dict{String,Any}("dir" => "undetectable", "reason" => "not eligible (common set < 8 at T0+2000 and at T0+500)")
            say("PF3 lam$lam: undetectable (not eligible)")
        else
            x = pq["x"]; ws = pq["windows"]
            g3 = [G(rec(3, lam, law), u, x) for u in ws]; g0 = [G(rec(0, lam, law), u, x) for u in ws]
            t3[lam] = merge(st(g3, g0), Dict{String,Any}("quantity" => pq["quantity"], "G s3" => g3, "G s0" => g0, "windows" => ws))
            say("PF3 lam$lam (", pq["quantity"], ", ", length(ws), " windows): G(s3) vs G(s0): ", t3[lam]["dir"], "  ", t3[lam], "")
        end
    end
    pf3 = law == "L2" ? t3[2]["dir"] == "larger" : all(lam -> t3[lam]["dir"] == "undetectable", LAMS)
    o["PF3"] = Dict("lam0" => t3[0], "lam2" => t3[2], "lam8" => t3[8], "holds" => pf3)
    say("PF3 verdict ", law, ": ", pf3 ? "holds" : "miss", "  (predicted: ", law == "L2" ? "larger at lam2; lam0 and lam8 reported" : "undetectable for every lambda",
        "; got lam0 ", t3[0]["dir"], ", lam2 ", t3[2]["dir"], ", lam8 ", t3[8]["dir"], ")")
    # PF4: ORG only, S at T0+2000 (0 if dead), s3 vs s0, all windows
    t4 = Dict{Int,Any}(); c4 = Dict{Int,Bool}()
    for lam in (2, 8)
        a3 = [S(rec(3, lam, law), "ORG", u, 2000) for u in us]; a0 = [S(rec(0, lam, law), "ORG", u, 2000) for u in us]
        t4[lam] = st(a3, a0)
        if law == "L2+SF" && lam == 2
            c4[lam] = t4[lam]["dir"] == "larger"
            say("PF4 lam2: ORG S(s3) larger than S(s0) by the sign test (predicted): ", c4[lam], "  ", t4[lam])
        elseif lam == 2
            c4[lam] = t4[lam]["pos"] > t4[lam]["neg"]
            say("PF4 lam2: more windows larger than smaller (direction only, predicted): ", c4[lam], "  windows larger ", t4[lam]["pos"],
                ", smaller ", t4[lam]["neg"], "   sign test beside: ", t4[lam])
        else
            c4[lam] = t4[lam]["neg"] > t4[lam]["pos"]
            say("PF4 lam8: more windows smaller than larger (direction only, predicted): ", c4[lam], "  windows larger ", t4[lam]["pos"],
                ", smaller ", t4[lam]["neg"], "   sign test beside: ", t4[lam])
        end
    end
    pf4 = c4[2] && c4[8]
    o["PF4"] = Dict("lam2" => merge(t4[2], Dict("holds" => c4[2])), "lam8" => merge(t4[8], Dict("holds" => c4[8])), "holds" => pf4)
    say("PF4 verdict ", law, ": ", pf4 ? "holds" : "miss", "  (lam2 ", c4[2] ? "holds" : "miss", ", lam8 ", c4[8] ? "holds" : "miss", ")")
end
write(joinpath(ODIR, "results-stake-fix-$(MODE)-check.out"), join(L, "\n") * "\n")
write(joinpath(ODIR, "results-stake-fix-$(MODE)-check.json"), JSON.json(out, 2))
