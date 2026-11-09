# S20 / S20b evaluation (predictions-alpha-grid.md AG1-AG4, predictions-alpha-scan.md AG1b-AG3b). IN = results file.
using JSON
f = get(ENV, "IN", "results-alpha-grid.json"); d = JSON.parsefile(joinpath(@__DIR__, f))
DECL = [("m1", r) for r in ("r1", "r3", "r7", "r8")] ∪ [("m2", r) for r in ("r2", "r4", "r7", "r8")]
UNDECL = [("m1", "r2"), ("m1", "r4"), ("m2", "r1"), ("m2", "r3")]
ev = [e for r in d["runs"] for e in r["events"]]
grid = [e for e in ev if !e["natural"]]; nat = [e for e in ev if e["natural"]]
nm = Dict(m => count(e -> e["m"] == m, grid) for m in ("m1", "m2"))
println(f, ": usable grid/scan events ", length(grid), " (m1 ", nm["m1"], ", m2 ", nm["m2"], "), natural ", length(nat))
real = Dict(pr => count(e -> e["m"] == pr[1] && pr[2] in e["diff"], grid) for pr in DECL ∪ UNDECL)
for pr in DECL; println("  declared $(pr[1])->$(pr[2]): ", nm[pr[1]] == 0 ? "not evaluable" : real[pr], " events with a difference"); end
ag1 = all(pr -> nm[pr[1]] > 0, DECL) ? (all(pr -> real[pr] > 0, DECL) ? "hit" : "miss") : "not evaluable"
ag2 = all(pr -> real[pr] == 0, UNDECL) ? "hit" : "miss"
ag3 = all(e -> !("r5" in e["diff"]) && !("r6" in e["diff"]), grid) ? "hit" : "miss"
println("AG1 ", ag1, "  AG2 ", ag2, " ", Dict("$(a)->$(b)" => real[(a, b)] for (a, b) in UNDECL), "  AG3 ", ag3)
if !isempty(nat) || haskey(d, "grid") && maximum(d["grid"]) == 6
    k = count(e -> "r7" in e["diff"] || "r8" in e["diff"], nat)
    println("AG4 natural r7/r8 ", k, "/", length(nat), ": ", isempty(nat) ? "not evaluable" : k <= 0.01 * length(nat) ? "hit" : "miss",
            "  per motor ", Dict(m => (count(e -> e["m"] == m && ("r7" in e["diff"] || "r8" in e["diff"]), nat), count(e -> e["m"] == m, nat)) for m in ("m1", "m2")),
            " per receptor ", Dict(r => count(e -> r in e["diff"], nat) for r in ("r7", "r8")))
end
# by schedule and the cells (S20b: B's second read) where each declared pair was realized
for sch in unique([r["schedule"] for r in d["runs"]])
    es = [e for r in d["runs"] if r["schedule"] == sch for e in r["events"] if !e["natural"]]
    println("  $sch: events m1 $(count(e -> e["m"] == "m1", es)) m2 $(count(e -> e["m"] == "m2", es)); realized ", sort(unique(["$(e["m"])->$r" for e in es for r in e["diff"]])))
end
if haskey(grid[1], "bcell")
    cells = Set(Tuple(e["bcell"]) for e in grid); println("  cells reached (own, other) ", length(cells), "/36")
    for pr in DECL
        ex = findfirst(e -> e["m"] == pr[1] && pr[2] in e["diff"], grid)
        ex === nothing || (e = grid[ex]; println("  example $(pr[1])->$(pr[2]): x=$(e["cell"]) cell=$(e["bcell"]) y2(C,B)=$(e["y2"])"))
    end
end
