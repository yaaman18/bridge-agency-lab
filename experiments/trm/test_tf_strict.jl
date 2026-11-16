# S56 r5 strict layer over the frozen test_tf.jl (sha f5cfa951...). Adds:
# (1) zero-element comparisons fail, (2) per (config, W, step) round count == H_cycles
# and L record length == L_cycles * H_cycles (from the fixture config), (3) exit code 1 on failure.
# test_tf.jl ends with a bare `main()` that rewrites results-tf.out and results-r5-summary.txt,
# so it is loaded with include_string after stripping that one final call (file itself unchanged).
using SHA
const TF_PATH = joinpath(@__DIR__, "test_tf.jl")
const TF_SHA = "f5cfa9510cc28175bde0de763c5a26ad9b68395188fabb54a4c44382229526be"
const STRICT_OUT = joinpath(@__DIR__, "results-tf-strict.out")
const EXITCODE_SRC = "exitcode(ok::Bool) = ok ? 0 : 1"
include_string(Main, EXITCODE_SRC)

function load_test_tf()
    src = read(TF_PATH, String)
    bytes2hex(sha256(src)) == TF_SHA || error("test_tf.jl sha mismatch")
    body = rstrip(src)
    endswith(body, "\nmain()") || error("test_tf.jl does not end with main()")
    include_string(Main, body[1:end-length("main()")], TF_PATH)
end
load_test_tf()

nonempty(x) = x isa AbstractArray && length(x) > 0
strict_pass(x) = x.pass && nonempty(x.got) && nonempty(x.want)
strictify(points) = [merge(x, (pass=strict_pass(x),)) for x in points]

const STEPKEYS = ("step1", "step2", "step3", "step4", "mixed_reset")
steptrace(fx, k) = k == "mixed_reset" ? fx["trace"]["mixed_reset"]["step1"] : fx["trace"]["steps"][k]

# Structure of the reference record and of the G-TF points, against the fixture config.
function structure(fx, points)
    H, L = Int(fx["config"]["H_cycles"]), Int(fx["config"]["L_cycles"])
    bad = String[]
    for k in STEPKEYS
        rounds = steptrace(fx, k)["h_rounds"]
        nr = length(rounds)
        nl = sum((length(r["l_iters"]) for r in rounds); init=0)
        perround = all(length(r["l_iters"]) == L for r in rounds)
        nz = count(x -> x.gate == "G-TF" && occursin(Regex("^$(k)/round\\d+/z_H\$"), x.key), points)
        nr == H || push!(bad, "$k rounds=$nr!=H_cycles=$H")
        nl == L * H || push!(bad, "$k l_iters total=$nl!=L*H=$(L*H)")
        perround || push!(bad, "$k l_iters per round!=L_cycles=$L")
        nz == H || push!(bad, "$k G-TF z_H points=$nz!=H_cycles=$H")
    end
    return bad
end

function row(points, fx)
    sp = strictify(points)
    empties = count(x -> !(nonempty(x.got) && nonempty(x.want)), points)
    st = structure(fx, points)
    tf = all(x.pass for x in sp if x.gate == "G-TF")
    gb = all(x.pass for x in sp if x.gate != "G-TF")
    return (sp=sp, tf=tf, gb=gb, empties=empties, st=st, ok=tf && gb && empties == 0 && isempty(st))
end

function negatives(io, fxa, basea)
    res = Bool[]
    # (N1) one empty comparison mixed in: original near/exact accept it, strict row fails.
    e = Float32[]
    pts = vcat(basea, [(key="probe/empty", gate="G-TF", got=e, want=e, pass=near(e, e))])
    r = row(pts, fxa)
    n1 = near(e, e) && exact(e, e) && !r.ok && r.empties == 1 && !r.tf
    println(io, "strict negative (N1) empty array mixed in: near=$(near(e,e)) exact=$(exact(e,e)) strict row ok=$(r.ok) empties=$(r.empties); ", n1 ? "PASS" : "FAILED")
    push!(res, n1)
    # (N2) first round dropped from step2 (last round kept, so outputs still match): original G-TF must pass, structure must fail.
    fx2 = deepcopy(fxa)
    popfirst!(fx2["trace"]["steps"]["step2"]["h_rounds"])
    p2, _ = examine(mutant(fx2, 0), fx2)
    tf_orig = all(x.pass for x in p2 if x.gate == "G-TF")
    r2 = row(p2, fx2)
    n2 = tf_orig && !r2.ok && !isempty(r2.st)
    println(io, "strict negative (N2) step2 missing its first round: original G-TF=$tf_orig strict row ok=$(r2.ok) structure=$(join(r2.st, "; ")); ", n2 ? "PASS" : "FAILED")
    push!(res, n2)
    # (N3) one L record dropped from step1/round1: structure fails.
    fx3 = deepcopy(fxa)
    pop!(fx3["trace"]["steps"]["step1"]["h_rounds"][1]["l_iters"])
    st3 = structure(fx3, basea)
    n3 = !isempty(st3)
    println(io, "strict negative (N3) step1/round1 missing one L record: structure=$(join(st3, "; ")); ", n3 ? "PASS" : "FAILED")
    push!(res, n3)
    # (N4) exit code: a separate julia process running the same exitcode definition.
    jl = Base.julia_cmd()
    cf = run(ignorestatus(`$jl --startup-file=no -e "$EXITCODE_SRC; exit(exitcode(false))"`)).exitcode
    ct = run(ignorestatus(`$jl --startup-file=no -e "$EXITCODE_SRC; exit(exitcode(true))"`)).exitcode
    n4 = cf == 1 && ct == 0
    println(io, "strict negative (N4) exit code: fail->$cf pass->$ct; ", n4 ? "PASS" : "FAILED")
    push!(res, n4)
    return all(res)
end

function strict_main()
    ok = false
    open(STRICT_OUT, "w") do io
        println(io, "sha256 test_tf.jl ", TF_SHA, " (loaded without its final main() call)")
        try
            rows, fixtures = Dict(), Dict()
            for c in CONFIGS, w in ("W0", "W1")
                fx = fixture(c, w)
                p, _ = examine(mutant(fx, 0), fx)
                r = row(p, fx)
                rows[(c, w)], fixtures[(c, w)] = r, fx
                println(io, "S $c/$w: G-TF=$(r.tf) G-B=$(r.gb) empty_compares=$(r.empties) structure=$(isempty(r.st) ? "ok" : join(r.st, "; ")) H=$(fx["config"]["H_cycles"]) L=$(fx["config"]["L_cycles"]) points=$(length(p)) row=$(r.ok ? "PASS" : "FAILED")")
                for x in r.sp
                    x.pass || println(io, "  FAILED $c/$w $(x.gate) $(x.key)")
                end
            end
            caught = Bool[]
            for (id, name, c) in CONTROLS
                push!(caught, control(io, id, name, fixtures[(c, "W1")], rows[(c, "W1")].sp))
            end
            neg = negatives(io, fixtures[("a", "W1")], rows[("a", "W1")].sp)
            ctrl = all(caught)
            rows_all = all(rows[(c, w)].ok for c in CONFIGS for w in ("W0", "W1"))
            rows_noc = all(rows[(c, w)].ok for c in ("a", "b", "d", "e") for w in ("W0", "W1"))
            ok = rows_all && ctrl && neg
            println(io, "OVERALL incl c (a,b,c,d,e): rows=$rows_all controls=$ctrl strict_negatives=$neg -> ", ok ? "PASS" : "FAILED")
            println(io, "EXCLUDING c (a,b,d,e rows; controls as above, control 8 uses the c fixture): rows=$rows_noc controls=$ctrl strict_negatives=$neg -> ", rows_noc && ctrl && neg ? "PASS" : "FAILED")
        catch e
            ok = false
            println(io, "FAILED: ", sprint(showerror, e))
        end
        println(io, ok ? "ALL PASS" : "FAILED")
    end
    return ok
end

exit(exitcode(strict_main()))
