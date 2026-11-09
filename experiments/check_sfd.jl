# S25 evaluation of predictions-sfd.md (TS1-TS4) from results-sfd-habit-{SF,SFD}.json and results-sfd-l2-{SF,SFD}.json.
using JSON
const D = @__DIR__
h = Dict(c => JSON.parsefile(joinpath(D, "results-sfd-habit-$c.json")) for c in ("SF", "SFD"))
pts(c) = [(r, p) for r in h[c]["runs"] for p in r["points"] if !haskey(p, "excluded")]
for c in ("SF", "SFD")
    println("$c: raising reproduced $(count(r -> r["raising_reproduced"], h[c]["runs"]))/$(length(h[c]["runs"])), candidate points $(length(pts(c)))")
end
j3(c) = [(r, p) for (r, p) in pts(c) if p["j3"] == "holds"]
emerg(c) = length(unique([(r["seed"], r["arm"], r["schedule"]) for (r, p) in j3(c)]))
pers(c) = (count(((r, p),) -> p["N_endkept"] == true, j3(c)), length(j3(c)))
det(c) = [(r, p) for (r, p) in pts(c) if p["R3b"] in ("holds", "fails")]
full(c) = (count(((r, p),) -> p["R3b"] == "holds", det(c)), length(det(c)))
for c in ("SF", "SFD")
    println("$c: ① j3 runs $(emerg(c)) (j3 points $(length(j3(c))))  ② N keeps support at t+400 $(pers(c)[1])/$(pers(c)[2])  ③ R3-b′ holds $(full(c)[1])/$(full(c)[2])")
end
a, b = pers("SF"), pers("SFD")
ts1 = (a[2] == 0 || b[2] == 0) ? "not evaluable" : (b[1] / b[2] > a[1] / a[2] ? "hit" : "miss")
ts2 = emerg("SFD") >= emerg("SF") ? "hit" : "miss"
ts3 = full("SFD")[2] == 0 ? "not evaluable" : full("SFD")[1] >= 1 ? "hit" : "miss"
println("TS1 $ts1  TS2 $ts2  TS3 $ts3")
for c in ("SF", "SFD"), (r, p) in j3(c)
    println("  $c j3 seed=$(r["seed"]) $(r["arm"]) $(r["schedule"]) t=$(p["t"]) E=$(p["E"]) q=$(p["q_E"]) sg=$(p["sg_E"]) N_endkept=$(p["N_endkept"]) j1=$(p["j1"]) j2=$(p["j2"]) $(p["j2_parts"]) R3b=$(p["R3b"])")
end
l = Dict(c => JSON.parsefile(joinpath(D, "results-sfd-l2-$c.json")) for c in ("SF", "SFD"))
key(x) = (x["arm"], x["H"], x["seed"], x["structure"])
m = Dict(c => Dict(key(x) => x["agency_L2"] for x in l[c]["runs"]) for c in ("SF", "SFD"))
tot = Dict(c => count(values(m[c])) for c in ("SF", "SFD"))
println("TS4 L2 true SF $(tot["SF"]) SFD $(tot["SFD"]) of $(length(m["SF"])): ", tot["SFD"] < tot["SF"] ? "hit" : "miss")
for arm in ("std", "swap"), H in (60, 294, 392, 588), st in ("constituents", "q")
    ks = [k for k in keys(m["SF"]) if k[1] == arm && k[2] == H && k[4] == st]
    println("  $arm H=$H $(rpad(st, 12)) SF $(count(k -> m["SF"][k], ks)) SFD $(count(k -> m["SFD"][k], ks))  SF→SFD lost $(count(k -> m["SF"][k] && !m["SFD"][k], ks)) gained $(count(k -> !m["SF"][k] && m["SFD"][k], ks))")
end
