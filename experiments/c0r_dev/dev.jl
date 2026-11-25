# S71 dev experiments A and B (discussion/specs/S71-draft-c0-redesign.md). Dev only: S64's TRAIN seeds train, S64's VAL seeds score; no eval seed is read.
# Usage (from the lab root), one training per process:
#   julia --project=. -t 4 experiments/c0r_dev/dev.jl run <stat|rev> <TRM|1x1> <full|ay|r1|r8|rall> <lr> <wd> <nsteps> <tag>
# Appends one line to experiments/c0r_dev/out/results.tsv; the loss trace every 100 updates goes to out/<tag>.trace.
# A (G-LEARN): mask full, several lr and nsteps.  B (receptor path): masks r1 (TAB_R1's six receptors only), r8, rall, ay.
include(joinpath(@__DIR__, "lib.jl"))
const OUTD = joinpath(@__DIR__, "out"); mkpath(OUTD)
function main(args)
    mode = args[1]
    mode == "run" || error("mode run")
    fam, model, mask, lr, wd, nsteps, tag = args[2], args[3], args[4], parse(Float64, args[5]), parse(Float64, args[6]), parse(Int, args[7]), args[8]
    cfg = model == "TRM" ? CFG_TRM : model == "1x1" ? CFG_1X1 : error("model")
    t0 = time()
    useeds = vcat(TRAIN, VAL)
    streams = tmapv(u -> obs_stream(u, fam), useeds)
    st = Dict(u => s for (u, s) in zip(useeds, streams))
    recept = mask != "ay"
    es = Dict(u => applymask(exset(st[u], recept), mask) for u in useeds)
    pool = catsets([es[u] for u in TRAIN])
    println("streams ", round(Int, time() - t0), " s; pool ", size(pool.tok, 2), " examples, distinct inputs ", length(unique(eachcol(pool.tok))))
    tf = open(joinpath(OUTD, tag * ".trace"), "w")
    p, trace = train_model(pool, cfg, lr, wd, nsteps; log = (t, l) -> (println(tf, t, "\t", l); flush(tf)))
    close(tf)
    ttrain = time() - t0
    vs = Float64[]; sds = Float64[]; rate = Float64[]; tabr1 = Float64[]; nu = Int[]
    ctrl = ctrl_train([st[u] for u in TRAIN])
    for u in VAL
        pr = predict_set(p, cfg, es[u])
        push!(vs, score(clip.(pr.p), es[u].act, es[u].Y).sc)
        push!(sds, std(pr.p)); push!(nu, pr.nuniq)
        c = ctrl_scores(ctrl, st[u]); push!(rate, c.RATE); push!(tabr1, c.TAB_R1)
    end
    line = join(["tag=$tag", "fam=$fam", "model=$model", "mask=$mask", "lr=$lr", "wd=$wd", "nsteps=$nsteps",
                 @sprintf("val=%.5f", mean(vs)), @sprintf("RATE=%.5f", mean(rate)), @sprintf("TAB_R1=%.5f", mean(tabr1)),
                 @sprintf("p_std=%.2e", mean(sds)), @sprintf("train_last100=%.5f", mean(trace[max(1, end-99):end])),
                 @sprintf("sec=%.0f", time() - t0)], "\t")
    println(line)
    open(joinpath(OUTD, "results.tsv"), "a") do io; println(io, line); end
end
main(ARGS)
