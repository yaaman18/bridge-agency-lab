# S56 r5: frozen teacher inputs, boundary checks, and paired negative controls.
# Copyright (c) 2025 Samsung Electronics Co., Ltd.; MIT: LICENSE-upstream-MIT.txt.
include(joinpath(@__DIR__, "TrmPort.jl"))
using .TrmPort
using SHA
const RESULT = joinpath(@__DIR__, "results-tf.out")
const SUMMARY = joinpath(@__DIR__, "results-r5-summary.txt")
const CONFIGS = ("a", "b", "c", "d", "e")
ref(d) = d["dtype"] == "bool" ? Bool.(TrmPort.load_tensor(d)) : TrmPort.load_tensor(d)
fixture(c, w) = TrmPort._json_plain(TrmPort.JSON.parsefile(joinpath(@__DIR__, "fixtures_r5", "$(c)_$(w).json")))
cdict(d) = Dict{String,Array{Int}}(q => Int.(ref(d[q])) for q in ("inputs", "puzzle_identifiers"))
state(fx) = Dict(k => ref(v) for (k,v) in fx["state_dict"])
function from_step(s; halted=Bool.(vec(ref(s["halted"]))))
    TrmPort.Carry(ref(s["z_H"]), ref(s["z_L"]), Int.(vec(ref(s["steps"]))), halted, cdict(s["current_data"]))
end
function valid(g, w)
    g isa AbstractArray && w isa AbstractArray && size(g) == size(w) &&
        eltype(g) == eltype(w) && all(isfinite, g) && all(isfinite, w)
end
function exact(g, w)
    valid(g, w) || return false
    eltype(w) <: AbstractFloat && return reinterpret(UInt8, vec(copy(g))) == reinterpret(UInt8, vec(copy(w)))
    return g == w
end
near(g, w) = valid(g, w) && all(abs.(Float64.(g) .- Float64.(w)) .<= 1e-5 .+ 1e-5 .* abs.(Float64.(w)))
function record!(points, key, gate, got, want; bits=false)
    push!(points, (key=key, gate=gate, got=copy(got), want=copy(want),
                   pass=bits ? exact(got, want) : near(got, want)))
end
function swapped(b)
    d = deepcopy(b)
    d["puzzle_identifiers"] = reverse(d["puzzle_identifiers"])
    d
end

# Each point retains its own baseline verdict and observed value. No aggregate
# failure can establish a control at a point where the normal model already fails.
function examine(model, fx; pid_swap=false)
    points, diagnostics = NamedTuple[], String[]
    for k in ("step1", "step2", "step3", "step4", "mixed_reset")
        mixed = k == "mixed_reset"
        t = mixed ? fx["trace"]["mixed_reset"]["step1"] : fx["trace"]["steps"][k]
        s = mixed ? fx["mixed_reset"]["step1"] : fx["steps"][k]
        inputkey = mixed ? fx["mixed_reset"]["input"] : s["passed_input"]
        batch = cdict(fx["inputs"][inputkey])
        pid_swap && (batch = swapped(batch))
        prev = if mixed
            from_step(fx["steps"]["step1"]; halted=Bool.(fx["mixed_reset"]["start_halted"]))
        elseif k == "step1"
            TrmPort.initial_carry(model, batch)
        else
            from_step(fx["steps"]["step$(parse(Int, k[5:end])-1)"])
        end
        # Teacher forcing supplies the reference embedding and BOTH incoming z.
        rounds = t["h_rounds"]
        for (h, r) in enumerate(rounds)
            zh, zl, lit = TrmPort.h_round(model, ref(r["z_H_in"]), ref(r["z_L_in"]), ref(t["input_embeddings"]))
            record!(points, "$k/round$h/z_H", "G-TF", zh, ref(r["z_H_out"]))
            record!(points, "$k/round$h/z_L", "G-TF", zl, ref(r["z_L_out"]))
            if !(points[end-1].pass && points[end].pass)
                firstbad = findfirst(j -> j > length(lit) || !near(lit[j], ref(r["l_iters"][j])), eachindex(r["l_iters"]))
                push!(diagnostics, "$k/round$h: L first over tolerance=$(firstbad === nothing ? "none" : firstbad) (diagnostic only)")
            end
        end
        outputs = TrmPort.act_outputs_from_z(model, ref(rounds[end]["z_H_out"]))
        for (q, rq) in ((:logits,"logits"), (:q_halt,"q_halt_logits"), (:q_continue,"q_continue_logits"))
            record!(points, "$k/round$(length(rounds))/output/$q", "G-TF", getproperty(outputs,q), ref(t["outputs"][rq]))
        end
        # Boundary chain starts from reset, independently of act_forward.
        reset = TrmPort.act_reset_carry(model, deepcopy(prev), batch)
        emb = TrmPort.act_input_embeddings(model, reset.current_data)
        zh, zl = copy(reset.z_H), copy(reset.z_L)
        for _ in 1:Int(fx["config"]["H_cycles"])
            zh, zl, _ = TrmPort.h_round(model, zh, zl, emb)
        end
        new, _ = TrmPort.act_forward(model, deepcopy(prev), batch)
        record!(points, "$k/z_H", "G-B(i)", new.z_H, zh; bits=true)
        record!(points, "$k/z_L", "G-B(i)", new.z_L, zl; bits=true)
        record!(points, "$k/steps", "G-B(ii)", new.steps, Int.(vec(ref(s["steps"]))); bits=true)
        record!(points, "$k/halted", "G-B(ii)", new.halted, Bool.(vec(ref(s["halted"]))); bits=true)
        for q in ("inputs", "puzzle_identifiers")
            record!(points, "$k/$q", "G-B(ii)", new.current_data[q], ref(s["current_data"][q]); bits=true)
        end
        if mixed
            for q in (:z_H, :z_L), stopped in (true, false)
                rows = prev.halted .== stopped
                # Halted rows use frozen reset state; continuing rows use previous output.
                want = stopped ? ref(t["carry_in"][string(q)]) : getproperty(prev,q)
                record!(points, "$k/reset/$q/halted=$stopped", "G-B(iii)", getproperty(reset,q)[rows,:,:], want[rows,:,:]; bits=true)
            end
        end
        record!(points, "$k/embedding", "G-B(iv)", emb, ref(t["input_embeddings"]))
    end
    return points, diagnostics
end
function mutant(fx, id)
    cfg, st = deepcopy(fx["config"]), state(fx)
    # The eight existing mutations retain test_port.jl's definitions.
    id == 1 && (st["inner.L_level.layers.0.mlp.down_proj.weight"][1,1] += Float32(0.01))
    id == 2 && (cfg["H_cycles"] -= 1)
    id == 3 && (cfg["L_cycles"] -= 1)
    TrmPort.ACTModel(TrmPort._named(cfg), st; swap_update_order=id==4,
        q_head_pos=id==5 ? 2 : 1, bad_rope_value=id==7, bad_norm_order=id==8,
        swap_round_store=id==9, drop_zl_between_steps=id==10)
end
const CONTROLS = ((1,"perturbed state","a"), (2,"H_cycles-1","a"),
    (3,"L_cycles-1","a"), (4,"swap_update_order","a"), (5,"q_head_pos=2","a"),
    (6,"puzzle_identifiers swapped","d"), (7,"bad_rope_value","a"),
    (8,"bad_norm_order","c"), (9,"swap_round_store","d"), (10,"drop_zl_between_steps","d"))
function control(io, id, name, fx, base)
    try
        mut, _ = examine(mutant(fx,id), fx; pid_swap=id==6)
        length(base) == length(mut) || error("point count changed")
        hits, active = String[], false
        for (b,m) in zip(base,mut)
            (b.key,b.gate) == (m.key,m.gate) || error("point identity changed")
            changed = !exact(b.got,m.got) || !exact(b.want,m.want)
            active |= changed
            # Exceptions, invalid shapes and nonfinite outputs do not count as detection.
            if b.pass && !m.pass && changed && valid(m.got,m.want)
                push!(hits, "$(m.gate):$(m.key)")
            end
        end
        required = id == 9 ? any(startswith(x,"G-TF:") for x in hits) :
                   id == 10 ? any(startswith(x,"G-B(i):") for x in hits) : !isempty(hits)
        witness = isempty(hits) ? "none" : first(hits)
        println(io, "negative control ($id) $name: caught by $witness; mutation active in gated span=$active; normal PASS -> mutant FAIL=$( !isempty(hits)); required gate=$required; ", required ? "PASS" : "FAILED")
        return required
    catch e
        println(io, "negative control ($id) $name: caught by none; mutation active in gated span=unverified; normal PASS -> mutant FAIL=false; FAILED: ", sprint(showerror,e))
        return false
    end
end
function summary(pred, firstfail, diagnostics, issue)
    open(SUMMARY,"w") do io
        for i in 1:4
            v = pred[i]
            println(io, "PT5-$i: ", v === nothing ? "未評価" : v ? "true（予測どおり）" : "false（予測は外れ）")
        end
        println(io, "G-TF 最初の不合格: ", firstfail)
        for line in diagnostics; println(io,line); end
        for name in ("TrmPort.jl", "test_tf.jl")
            println(io, "sha256 $name ", bytes2hex(sha256(read(joinpath(@__DIR__,name)))))
        end
        println(io, "不安な点: ", issue)
        println(io, "r4 の判定は維持。原因を経路の違い・丸めと断定しない。")
    end
end
function main()
    pred = Any[nothing,nothing,nothing,nothing]
    firstfail, diagnostics = "none", String[]
    open(RESULT,"w") do io
        ok = false
        try
            base, fixtures = Dict(), Dict()
            tf, gb = Dict(), Bool[]
            for c in CONFIGS, w in ("W0","W1")
                fx = fixture(c,w)
                p,d = examine(mutant(fx,0),fx)
                base[(c,w)], fixtures[(c,w)] = p, fx
                tf[(c,w)] = all(x.pass for x in p if x.gate == "G-TF")
                push!(gb, all(x.pass for x in p if x.gate != "G-TF"))
                println(io,"G $c/$w: G-TF=$(tf[(c,w)]) G-B=$(last(gb)) points=$(length(p))")
                for x in p
                    if !x.pass
                        println(io,"  FAILED $c/$w $(x.gate) $(x.key)")
                        if firstfail == "none" && x.gate == "G-TF"
                            firstfail = "$c/$w $(x.key)"
                        end
                    end
                end
                append!(diagnostics, ["$c/$w $line" for line in d])
            end
            pred[1] = all(tf[(c,w)] for c in ("a","b","d","e") for w in ("W0","W1"))
            pred[2] = all(tf[("c",w)] for w in ("W0","W1"))
            pred[3] = all(gb)
            caught = Bool[]
            for (id,name,c) in CONTROLS
                push!(caught,control(io,id,name,fixtures[(c,"W1")],base[(c,"W1")]))
            end
            pred[4] = all(caught)
            for line in diagnostics; println(io,"diagnostic ",line); end
            ok = all(pred)
            summary(pred,firstfail,diagnostics,"test_layers・r4 再照合は別の GATE。G-TF の合格は凍結軌道上の検査入力に限る。")
        catch e
            ok = false
            msg = sprint(showerror,e)
            println(io,"FAILED: ",msg)
            summary(pred,firstfail,diagnostics,"実行中の例外: " * msg)
        end
        println(io,ok ? "ALL PASS" : "FAILED")
        return ok
    end
end
main()
