# S45 checker (spec discussion/specs/S45-trm-stageA.md r2 §6): the gates of the data, the format, the splits and the evaluator.
using JSON, SHA
const DIR = @__DIR__
R = JSON.parsefile(get(ENV, "RES", joinpath(DIR, "results-trm-data.json")))
gates = Tuple{String,Bool}[]
gate(n, ok) = (push!(gates, (n, ok)); println("GATE ", ok ? "ok  " : "FAIL", " ", n))
for l in readlines(joinpath(DIR, "freeze-trm-data.txt"))
    (startswith(l, "#") || isempty(strip(l))) && continue
    h, f = split(l; limit = 2); f = strip(f)
    gate("freeze sha $f", bytes2hex(sha256(read(joinpath(DIR, f)))) == h)
end
function read_npy(path)
    io = open(path); read(io, 6); read(io, 2); hl = ltoh(read(io, UInt16)); h = String(read(io, hl))
    T = occursin("|u1", h) ? UInt8 : Int32
    m = match(r"'shape': \((\d+),\s*(\d*)\)", h); n1 = parse(Int, m[1]); n2 = isempty(m[2]) ? 0 : parse(Int, m[2])
    data = ltoh.(reinterpret(T, read(io))); close(io)
    n2 == 0 ? collect(data) : permutedims(reshape(collect(data), n2, n1))
end
labels_ok(Y) = all(r -> all(==(0), Y[r, 1:end-9]) && all(x -> x in (1, 2), Y[r, end-8:end]), 1:size(Y, 1))

gate("replay: 240 trajectories (seeds 511-540 x 2 arms x 4 schedules) match g1_school.jl's record", R["replay"]["checked"] == 240 && R["replay"]["match"] == 240)
gate("at most one motor acts per update", R["max_acts_per_update"] <= 1)
const FIELDS = Set(["pad_id", "ignore_label_id", "blank_identifier_id", "vocab_size", "seq_len", "num_puzzle_identifiers", "total_groups",
                    "mean_puzzle_examples", "total_puzzles", "sets"])
for (k, v) in R["files"]
    variant, sp = split(k, "/")
    dir = joinpath(R["outdir"], variant, sp); meta = JSON.parsefile(joinpath(dir, "dataset.json"))
    Y = read_npy(joinpath(dir, "all__labels.npy")); X = read_npy(joinpath(dir, "all__inputs.npy"))
    gate("$k: read back, source times <= u and teacher u+1, labels only on the last 9", v["readback"] && v["source_times_ok"] && v["labels_only_last9"])
    gate("$k: dataset.json has exactly the PuzzleDatasetMetadata fields; seq_len $(variant == "IR" ? 89 : 105)",
         Set(keys(meta)) == FIELDS && meta["seq_len"] == (variant == "IR" ? 89 : 105) && size(X, 2) == meta["seq_len"] && size(X, 1) == v["N"])
    gate("$k: labels re-checked from the file", labels_ok(Y))
    pidx = read_npy(joinpath(dir, "all__puzzle_indices.npy")); gidx = read_npy(joinpath(dir, "all__group_indices.npy")); pid = read_npy(joinpath(dir, "all__puzzle_identifiers.npy"))
    gate("$k: index arrays (codex I-R 1 #3): total_puzzles = length(puzzle_indices) - 1 = N, total_groups = length(group_indices) - 1, both start at 0, end at N, non-decreasing",
         meta["total_puzzles"] == length(pidx) - 1 == size(X, 1) && meta["total_groups"] == length(gidx) - 1 && pidx[1] == 0 && gidx[1] == 0 &&
         pidx[end] == size(X, 1) && gidx[end] == size(X, 1) && issorted(pidx) && issorted(gidx))
    ids = JSON.parsefile(joinpath(R["outdir"], variant, "identifiers.json"))
    gate("$k: identifiers.json (codex I-R 1 #6) = [\"<blank>\"], its length = num_puzzle_identifiers, every puzzle identifier = blank_identifier_id",
         ids == ["<blank>"] && length(ids) == meta["num_puzzle_identifiers"] && all(==(meta["blank_identifier_id"]), pid) && length(pid) == size(X, 1))
    if k == "IR/explore"
        Yb = copy(Y); Yb[1, 1] = 2
        gate("negative: a label put on an input position fails the label check", !labels_ok(Yb))
    end
end
seeds(sp) = Set(R[sp])
gate("splits are disjoint by seed", isempty(intersect(seeds("train"), seeds("explore"))) && isempty(intersect(seeds("train"), seeds("confirm"))) &&
     isempty(intersect(seeds("explore"), seeds("confirm"))))
rh = R["raise_hash"]
hs(sp) = Set(rh["$s-$arm"] for s in R[sp] for arm in ("std", "swap"))   # codex I-R 1 #5: both arms together
shared = Dict("$a-$b" => length(intersect(hs(a), hs(b))) for (a, b) in (("train", "explore"), ("train", "confirm"), ("explore", "confirm")))
println("raised circuits shared across splits (both arms together): ", shared, "  (hash of raised q, sg, lastM: content, not the seed)")
gate("no raised circuit is shared between any two splits (both arms together)", all(==(0), values(shared)))
fi = R["future_invariance"]
gate("future invariance (codex I-R 1 #4): IR and IRC, R/C/A rewritten at u+1.., input unchanged and teacher changed; >= 5 examples each",
     all(values(fi)) && count(k -> startswith(k, "IR-"), keys(fi)) >= 5 && count(k -> startswith(k, "IRC-"), keys(fi)) >= 5)
gate("future invariance negative: a builder reading the core at v+1 is caught", R["future_invariance_negative_caught"])
gate("auxiliary: the shifted build fails the source-time check", R["shift_diag_fails"])
gate("evaluator unit tests (O1 const = 0, L_b = 0 undecided, by hand; Brier by hand)", all(values(R["evaluator_unit"])))
gate("no e / O1 on the confirm seeds", R["confirm_metrics_computed"] == false && Set(keys(R["baselines_explore"])) == Set(["B0", "B1", "B2", "B2p"]))
ex = R["excluded"]
println("excluded examples (u+1 dead) by arm: std ", sum(v for (k, v) in ex if occursin("-std-", k)), ", swap ", sum(v for (k, v) in ex if occursin("-swap-", k)))
allok = all(last, gates); println("all gates: ", allok ? "ok" : "FAIL"); allok || exit(1)
