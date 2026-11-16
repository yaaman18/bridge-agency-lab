# S60 gate G-i (spec discussion/specs/S60-trm-det.md §3): the deterministic Julia inference vs the S56 port (TrmPort.jl)
# and vs the frozen official fixtures. Tolerances of S56 r4: max abs <= 1e-4 after recursion; first block
# |d| <= 1e-5 + 1e-5|ref|. Writes experiments/results-trm-det-i.out; exit 1 on any failure.
include(joinpath(@__DIR__, "..", "TrmPort.jl"))
include(joinpath(@__DIR__, "TrmDet.jl"))
using .TrmDet

const TOL = 1e-4
const BUNDLES = [("a", "W0"), ("a", "W1"), ("b", "W0"), ("b", "W1"), ("e", "W0"), ("e", "W1")]
const CASES = ["step1", "step2", "step3", "step4", "mixed"]
const FQ = ["logits", "q_halt", "q_continue", "z_H", "z_L"]
const IQ = ["steps", "halted", "cd_inputs", "cd_pid"]
const BLOCKQ = ["input_embeddings", "reset_z_H", "reset_z_L", "block_input_h", "block_first_op_out",
                "block_norm1_out", "block_mlp_out", "block_norm2_out"]
const FIX_KEY = Dict("logits" => "logits", "q_halt" => "q_halt_logits", "q_continue" => "q_continue_logits",
                     "z_H" => "z_H", "z_L" => "z_L", "steps" => "steps", "halted" => "halted")

reference(d) = d["dtype"] == "bool" ? Bool.(TrmPort.load_tensor(d)) : TrmPort.load_tensor(d)

"Expected item set, enumerated independently of the checks."
function expected_items()
    s = Set{NTuple{4,String}}()
    for (c, w) in BUNDLES, case in CASES
        for q in FQ, ref in ("port", "fixture")
            push!(s, (c * "_" * w, case, q, ref))
        end
        for q in IQ
            push!(s, (c * "_" * w, case, q, "fixture"))
        end
    end
    for (c, w) in BUNDLES
        w == "W1" || continue
        for q in BLOCKQ
            push!(s, (c * "_" * w, "step1", q, "fixture"))
        end
        for r in 1:3, q in ("z_H", "z_L")
            push!(s, (c * "_" * w, "step1", string("h_round_end", r, ".", q), "fixture"))
        end
    end
    return s
end

mutable struct Tally
    seen::Vector{NTuple{4,String}}
    nfail::Int
    nel::Int
end

"Compare det (Julia array) with ref. kind: :abs (max abs <= TOL), :block (elementwise), :exact."
function check!(io, T::Tally, key, got, want, kind)
    push!(T.seen, key)
    tag = join(key, " ")
    try
        size(got) == size(want) || error(string("shape ", size(got), " != ", size(want)))
        length(got) > 0 || error("empty")
        if kind == :exact
            g = Int64.(got); r = Int64.(want)
            nd = count(g .!= r)
            T.nel += length(g)
            ok = nd == 0
            println(io, tag, " n=", length(g), " exact_mismatch=", nd, ok ? " PASS" : " FAILED")
            ok || (T.nfail += 1)
            return ok
        end
        all(isfinite, got) && all(isfinite, want) || error("non-finite")
        d = abs.(Float64.(got) .- Float64.(want))
        md = maximum(d)
        T.nel += length(d)
        if kind == :block
            lim = 1e-5 .+ 1e-5 .* abs.(Float64.(want))
            nbad = count(d .> lim)
            ratio = maximum(d ./ lim)
            ok = nbad == 0
            println(io, tag, " n=", length(d), " max_abs=", md, " max_ratio=", ratio, " over=", nbad, ok ? " PASS" : " FAILED")
        else
            ok = md <= TOL
            println(io, tag, " n=", length(d), " max_abs=", md, ok ? " PASS" : " FAILED")
        end
        ok || (T.nfail += 1)
        return ok
    catch e
        println(io, tag, " FAILED: ", sprint(showerror, e))
        T.nfail += 1
        return false
    end
end

"S56 port trajectory exactly as test_port.jl does it (steps 1..4, then mixed from step-1 carry)."
function port_run(fx)
    model = TrmPort.ACTModel(fx.config, fx.state)
    carry = TrmPort.initial_carry(model, fx.inputs[fx.steps["step1"]["passed_input"]])
    carries, outs = Any[], Any[]
    for k in 1:4
        batch = deepcopy(fx.inputs[fx.steps[string("step", k)]["passed_input"]])
        carry, out = TrmPort.act_forward(model, carry, batch)
        push!(carries, deepcopy(carry)); push!(outs, deepcopy(out))
    end
    mr, first = fx.mixed_reset, deepcopy(carries[1])
    mixed = TrmPort.Carry(first.z_H, first.z_L, first.steps, Bool.(mr["start_halted"]), first.current_data)
    carry, out = TrmPort.act_forward(model, mixed, fx.inputs[mr["input"]])
    push!(carries, deepcopy(carry)); push!(outs, deepcopy(out))
    return carries, outs
end

port_q(c, o, q) = q == "logits" ? o["logits"] : q == "q_halt" ? o["q_halt_logits"] :
                  q == "q_continue" ? o["q_continue_logits"] : q == "z_H" ? c.z_H : c.z_L

function fixture_case(fx, case)
    case == "mixed" && return fx.mixed_reset["step1"]
    return fx.steps[case]
end

function fixture_q(ref, q)
    q == "cd_inputs" && return reference(ref["current_data"]["inputs"])
    q == "cd_pid" && return reference(ref["current_data"]["puzzle_identifiers"])
    return reference(ref[FIX_KEY[q]])
end

det_arr(r::TrmDet.Rec) = r.tag == TrmDet.TAG_F32 ? TrmDet.to_jl(r.f, r.dims) : TrmDet.to_jl(r.i, r.dims)

function bundle_checks(io, T, c, w, bitdiff)
    name = c * "_" * w
    fx = TrmPort.load_fixture(joinpath(@__DIR__, "..", "fixtures", string(c, "_", w, ".json")))
    recs = TrmDet.read_recs(joinpath(@__DIR__, "bundles", name * ".bin"), TrmDet.MAGIC_BUNDLE)
    m = TrmDet.Model(recs)
    out, _, _ = TrmDet.run_bundle(m, recs)
    od = TrmDet.recdict(out)
    pc, po = port_run(fx)
    nb, nt = 0, 0
    for (ci, case) in enumerate(CASES)
        ref = fixture_case(fx, case)
        for q in FQ
            g = det_arr(od[case * "." * q])
            p = port_q(pc[ci], po[ci], q)
            check!(io, T, (name, case, q, "port"), g, p, :abs)
            check!(io, T, (name, case, q, "fixture"), g, fixture_q(ref, q), :abs)
            if size(g) == size(p)
                nb += count(reinterpret(UInt32, Float32.(vec(g))) .!= reinterpret(UInt32, Float32.(vec(p))))
                nt += length(g)
            end
        end
        for q in IQ
            check!(io, T, (name, case, q, "fixture"), det_arr(od[case * "." * q]), fixture_q(ref, q), :exact)
        end
    end
    bitdiff[name] = (nb, nt)
    w == "W1" || return
    it = TrmDet.step1_intermediates(m, recs)
    dims3 = (m.B, m.S, m.H)
    for q in BLOCKQ
        check!(io, T, (name, "step1", q, "fixture"), TrmDet.to_jl(getproperty(it, Symbol(q)), dims3), fx.intermediates[q], :block)
    end
    refs = fx.intermediates["h_round_end"]
    length(refs) == 3 || error("h_round_end reference count")
    for r in 1:3, (j, q) in enumerate(("z_H", "z_L"))
        check!(io, T, (name, "step1", string("h_round_end", r, ".", q), "fixture"),
               TrmDet.to_jl(it.h_round_end[r][j], dims3), reference(refs[r][q]), :abs)
    end
end

"Negative control: a mutated det run must leave the tolerance against both the port and the fixture."
function control(io, label, c, case, q, build)
    try
        fx = TrmPort.load_fixture(joinpath(@__DIR__, "..", "fixtures", string(c, "_W1.json")))
        recs = TrmDet.read_recs(joinpath(@__DIR__, "bundles", c * "_W1.bin"), TrmDet.MAGIC_BUNDLE)
        out = build(recs)
        g = det_arr(TrmDet.recdict(out)[case * "." * q])
        pc, po = port_run(fx)
        ci = findfirst(==(case), CASES)
        dp = maximum(abs.(Float64.(g) .- Float64.(port_q(pc[ci], po[ci], q))))
        df = maximum(abs.(Float64.(g) .- Float64.(fixture_q(fixture_case(fx, case), q))))
        caught = dp > TOL && df > TOL
        println(io, label, caught ? " caught: " : " FAILED (not caught): ", c, "/W1 ", case, " ", q,
                " max_abs vs port=", dp, " vs fixture=", df)
        return caught
    catch e
        println(io, label, " FAILED: ", sprint(showerror, e))
        return false
    end
end

function run_mut(recs; swap=false)
    m = TrmDet.Model(recs; swap_order=swap)
    return TrmDet.run_bundle(m, recs)[1]
end

function main()
    path = joinpath(@__DIR__, "..", "..", "results-trm-det-i.out")
    ok = open(path, "w") do io
        println(io, "S60 G-i: deterministic Julia (det/TrmDet.jl) vs TrmPort.jl and vs fixtures; max abs <= ", TOL,
                "; first block |d| <= 1e-5+1e-5|ref|; integers exact")
        T = Tally(NTuple{4,String}[], 0, 0)
        bitdiff = Dict{String,Tuple{Int,Int}}()
        for (c, w) in BUNDLES
            try
                bundle_checks(io, T, c, w, bitdiff)
            catch e
                println(io, c, "_", w, " FAILED: ", sprint(showerror, e))
                T.nfail += 1
            end
        end
        exp_items = expected_items()
        seen = Set(T.seen)
        ndup = length(T.seen) - length(seen)
        missing_ = setdiff(exp_items, seen)
        extra = setdiff(seen, exp_items)
        set_ok = ndup == 0 && isempty(missing_) && isempty(extra)
        println(io, "items expected ", length(exp_items), " checked ", length(T.seen), " duplicates ", ndup,
                " missing ", length(missing_), " extra ", length(extra), set_ok ? " PASS" : " FAILED")
        for x in first(collect(missing_), min(5, length(missing_)))
            println(io, "  missing ", join(x, " "))
        end
        println(io, "elements compared ", T.nel, " item failures ", T.nfail)
        # non-vacuity: exp_det differs from Base.exp somewhere; det differs bitwise from TrmPort in every bundle
        grid = Float32[Float32(-87 + 175 * j / (2^20 - 1)) for j in 0:(2^20 - 1)]
        nexp = count(x -> TrmDet.exp_det(x) != exp(x), grid)
        println(io, "exp_det != Base.exp(Float32) at ", nexp, " of ", length(grid), " grid points", nexp > 0 ? " PASS" : " FAILED")
        bd_ok = length(bitdiff) == length(BUNDLES)
        for (c, w) in BUNDLES
            nb, nt = get(bitdiff, c * "_" * w, (0, 0))
            println(io, "bitwise det != TrmPort ", c, "_", w, ": ", nb, " of ", nt, " f32 output elements", nb > 0 ? " PASS" : " FAILED")
            bd_ok &= nb > 0
        end
        caught = 0
        caught += control(io, "negative control n1 (swap z_L/z_H update order)", "a", "step1", "logits", r -> run_mut(r; swap=true))
        caught += control(io, "negative control n2 (layers.0.mlp.down_proj.weight[0,0] += 0.01)", "a", "step4", "logits",
                          r -> begin
                              d = TrmDet.recdict(r)
                              d["inner.L_level.layers.0.mlp.down_proj.weight"].f[1] += Float32(0.01)
                              run_mut(r)
                          end)
        caught += control(io, "negative control n3 (exp_det polynomial truncated at degree 1)", "e", "step1", "logits",
                          r -> try
                              TrmDet.EXP_MUT[] = :exp_lin
                              run_mut(r)
                          finally
                              TrmDet.EXP_MUT[] = :none
                          end)
        println(io, "negative controls caught: ", caught, "/3")
        allok = T.nfail == 0 && set_ok && nexp > 0 && bd_ok && caught == 3
        println(io, allok ? "ALL PASS" : "FAILED")
        allok
    end
    print(read(path, String))
    return ok
end

abspath(PROGRAM_FILE) == (@__FILE__) && exit(main() ? 0 : 1)
