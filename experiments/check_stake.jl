# S53 judgment (discussion/specs/S53-stake.md r2 §3-§4; predictions-stake.md PK1-PK5). Reads results-stake-<mode>.json.
# Usage (from experiments/): julia --project=.. check_stake.jl main   -> results-stake-main-check.json / .out
#                            julia --project=.. check_stake.jl smoke <outdir>   (script test only; trial windows, no claim)
# signtest is copied from check_pa_grid.jl (S47 r3 §5 (c)); its labels are mapped to larger / smaller / undetectable.
using JSON

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode smoke | main")
const ODIR = length(ARGS) >= 2 ? ARGS[2] : joinpath(LAB, "experiments")
const T0 = 800; const X500 = 1; const X2000 = 2; const X9200 = 3
const LAWS = ("L2", "L2+SF"); const LAMS = (0, 2, 8)

recs = Dict{String,Any}()
for l in eachline(joinpath(LAB, "experiments", "results-stake-$(MODE).json"))
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

S(r, arm, u, x) = r[arm][u]["countAt"][x]
dw(r, arm, u) = r[arm][u]["deathW"]
alive500(r, arm, u) = (d = r[arm][u]["death"]; d === nothing || d >= T0 + 500)
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
r3(x) = round(x; digits = 3)

const L = String[]
say(x...) = (s = string(x...); println(s); push!(L, s))
out = Dict{String,Any}()
for law in LAWS
    o = Dict{String,Any}(); out[law] = o
    us = string.(rec(0, 0, law)["evals"])
    say("==== law ", law, "  (windows ", join(us, ","), ", n = ", length(us), ")")
    # per point: realized yields, levy requested / taken, sizes, deaths
    for s in 0:3, lam in (s == 0 ? (0,) : LAMS)
        r = rec(s, lam, law)
        ym = mean([mean(r[a][u]["rep"]["yieldMean"]) for a in ("ORG", "ORG-SIL") for u in us])
        lq = Dict(a => sum(r[a][u]["levyReq"] for u in us) for a in ("ORG", "ORG-SIL"))
        lt = Dict(a => sum(r[a][u]["levyTaken"] for u in us) for a in ("ORG", "ORG-SIL"))
        sz(a, x) = join([S(r, a, u, x) for u in us], " ")
        say("s$s lam$lam M=$(r["M"]) levy/step=$(r["levyAmount"])  realized yield mean (patch mean, from T0) $(r3(ym))",
            "  levy requested / taken: ORG $(r3(lq["ORG"])) / $(r3(lt["ORG"])), ORG-SIL $(r3(lq["ORG-SIL"])) / $(r3(lt["ORG-SIL"]))")
        for a in ("ORG", "ORG-SIL")
            say("   ", rpad(a, 8), " S@T0+500: ", sz(a, X500), " | S@T0+2000: ", sz(a, X2000), " | S@9200: ", sz(a, X9200),
                " | deathW: ", join([dw(r, a, u) for u in us], " "))
        end
        o["s$s lam$lam"] = Dict("yieldMean" => ym, "levyReq" => lq, "levyTaken" => lt)
    end
    # PK1
    viol = Any[]
    for s in 0:3, lam in (s == 0 ? (0,) : LAMS), u in us
        r = rec(s, lam, law)
        S(r, "ORG-SIL", u, X2000) > S(r, "ORG", u, X2000) && push!(viol, ("s$s lam$lam", u, S(r, "ORG", u, X2000), S(r, "ORG-SIL", u, X2000)))
    end
    o["PK1"] = Dict("violations" => length(viol), "of" => 10 * length(us), "list" => viol, "holds" => isempty(viol))
    say("PK1 ORG-SIL S <= ORG S (T0+2000) everywhere: ", isempty(viol), "  violations ", length(viol), "/", 10 * length(us), "  ", viol)
    # PK2
    a3 = [S(rec(3, 0, law), "ORG", u, X2000) for u in us]; a0 = [S(rec(0, 0, law), "ORG", u, X2000) for u in us]
    t2 = st(a3, a0); o["PK2"] = merge(t2, Dict("holds" => t2["dir"] == "larger"))
    say("PK2 lam0: ORG S(s3) > S(s0): ", t2["dir"] == "larger", "  ", t2)
    # PK3 (lam 8 predicted; lam 2 reported)
    for lam in (8, 2)
        d0 = [dw(rec(3, 0, law), "ORG-SIL", u) for u in us]; dl = [dw(rec(3, lam, law), "ORG-SIL", u) for u in us]
        t3 = st(d0, dl)
        o["PK3 lam$lam"] = merge(t3, Dict("holds" => t3["dir"] == "larger", "deathW lam0" => d0, "deathW lam$lam" => dl))
        say("PK3 s3: ORG-SIL death earlier with lam$lam than lam0", lam == 8 ? " (predicted)" : " (no prediction)", ": ", t3["dir"] == "larger", "  ", t3)
    end
    # PK4
    for lam in (2, 8)
        r0 = rec(0, lam, law); r3_ = rec(3, lam, law)
        both = [u for u in us if alive500(r0, "ORG", u) && alive500(r0, "ORG-SIL", u) && alive500(r3_, "ORG", u) && alive500(r3_, "ORG-SIL", u)]
        g3 = [S(r3_, "ORG", u, X500) - S(r3_, "ORG-SIL", u, X500) for u in both]; g0 = [S(r0, "ORG", u, X500) - S(r0, "ORG-SIL", u, X500) for u in both]
        t4 = length(both) < 8 ? Dict{String,Any}("dir" => "undetectable", "reason" => "fewer than 8 windows with both arms alive at T0+500") : st(g3, g0)
        G2(r) = [S(r, "ORG", u, X2000) - S(r, "ORG-SIL", u, X2000) for u in us]
        silDead(r) = count(u -> S(r, "ORG-SIL", u, X2000) == 0, us)
        t4b = st(G2(r3_), G2(r0))
        o["PK4 lam$lam"] = Dict("G500" => t4, "nBoth" => length(both), "G500 s3" => g3, "G500 s0" => g0, "holds" => t4["dir"] == "larger",
            "G2000" => t4b, "G2000 s3" => G2(r3_), "G2000 s0" => G2(r0), "SIL dead at T0+2000 s3" => silDead(r3_), "SIL dead at T0+2000 s0" => silDead(r0))
        say("PK4 lam$lam: G500(s3) > G500(s0): ", t4["dir"] == "larger", "  windows both alive ", length(both), "  ", t4,
            "  G500 s3 ", g3, " s0 ", g0)
        say("    G2000 (beside): ", t4b, "  s3 ", G2(r3_), " s0 ", G2(r0), "  ORG-SIL dead at T0+2000: s3 ", silDead(r3_), ", s0 ", silDead(r0))
    end
    # PK5
    t5 = Dict{Int,Any}()
    for lam in (2, 8)
        a3 = [S(rec(3, lam, law), "ORG", u, X2000) for u in us]; a0 = [S(rec(0, lam, law), "ORG", u, X2000) for u in us]
        t5[lam] = st(a3, a0)
        say("PK5 lam$lam: ORG S(s3) vs S(s0): ", t5[lam]["dir"], "  ", t5[lam])
    end
    pk5 = t5[2]["dir"] == "larger" && t5[8]["dir"] != "larger"
    o["PK5"] = Dict("lam2" => t5[2], "lam8" => t5[8], "holds" => pk5, "larger at both" => t5[2]["dir"] == "larger" && t5[8]["dir"] == "larger")
    say("PK5 predicted (larger at lam2, not larger at lam8): ", pk5, "   larger at both (6.13 false on this grid): ", o["PK5"]["larger at both"])
end
write(joinpath(ODIR, "results-stake-$(MODE)-check.out"), join(L, "\n") * "\n")
write(joinpath(ODIR, "results-stake-$(MODE)-check.json"), JSON.json(out, 2))
