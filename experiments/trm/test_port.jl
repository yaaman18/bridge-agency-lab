# S56 ACT contract checks for SamsungSAILMontreal/TinyRecursiveModels, trm.py, commit 7de0d20.
# Copyright (c) 2025 Samsung Electronics Co., Ltd.; MIT: LICENSE-upstream-MIT.txt.
# Contract: discussion/notes/S56-progress.md, turn-3 API. References are never replaced.
include(joinpath(@__DIR__, "TrmPort.jl"))
using .TrmPort
const TOL = 1e-4
const OUT_KEYS = ("logits", "q_halt_logits", "q_continue_logits")
fixture(c, w) = load_fixture(joinpath(@__DIR__, "fixtures", string(c, "_", w, ".json")))
attr(cfg, key) = cfg.values[findfirst(==(key), cfg.names)]
# load_tensor restores row-major shapes; its bool fallback is Float32, so restore Bool explicitly.
reference(d) = d["dtype"] == "bool" ? Bool.(TrmPort.load_tensor(d)) : TrmPort.load_tensor(d)
function cfg_with(cfg, key)
    vals = copy(cfg.values)
    i = findfirst(==(key), cfg.names)
    vals[i] -= 1
    return (names = copy(cfg.names), values = vals)
end
function difference(got, want; exact=false)
    got isa AbstractArray && want isa AbstractArray || error("not an array")
    size(got) == size(want) || error(string("shape ", size(got), " != ", size(want)))
    all(isfinite, got) && all(isfinite, want) || error("non-finite array")
    exact && eltype(got) != eltype(want) && error(string("eltype ", eltype(got), " != ", eltype(want)))
    d = abs.(Float64.(got) .- Float64.(want))
    md = maximum(d; init=0.0)
    i = findfirst(x -> exact ? !iszero(x) : x > TOL, d)
    detail = i === nothing ? "" : string(" first=", i, " diff=", d[i], " reference=", want[i])
    return (i === nothing, md, detail)
end
function report(io, tag, got, want; exact=false)
    try
        ok, md, detail = difference(got, want; exact=exact)
        println(io, tag, " max_abs_diff=", md, exact ? " exact " : " ", ok ? "PASS" : "FAILED", detail)
        return ok
    catch e
        println(io, tag, " FAILED: ", sprint(showerror, e))
        return false
    end
end
function check_step(io, tag, carry, outputs, ref)
    ok = Set(keys(outputs)) == Set(OUT_KEYS)
    println(io, tag, " output_keys ", ok ? "PASS" : "FAILED")
    for q in OUT_KEYS
        ok &= report(io, string(tag, ".", q), get(outputs, q, nothing), reference(ref[q]))
    end
    for q in ("z_H", "z_L", "steps", "halted")
        ok &= report(io, string(tag, ".", q), getproperty(carry, Symbol(q)), reference(ref[q]); exact=q in ("steps", "halted"))
    end
    keys_ok = Set(keys(carry.current_data)) == Set(keys(ref["current_data"]))
    println(io, tag, " current_data_keys ", keys_ok ? "PASS" : "FAILED")
    ok &= keys_ok
    for q in sort!(collect(keys(ref["current_data"])))
        ok &= report(io, string(tag, ".current_data.", q), get(carry.current_data, q, nothing), reference(ref["current_data"][q]); exact=true)
    end
    return ok
end
function trajectory(model, fx, n; swap=false)
    carry = TrmPort.initial_carry(model, fx.inputs[fx.steps["step1"]["passed_input"]])
    states, outputs = Any[], Any[]
    for k in 1:n
        batch = deepcopy(fx.inputs[fx.steps[string("step", k)]["passed_input"]])
        swap && k == n && (batch["puzzle_identifiers"] = reverse(batch["puzzle_identifiers"]))
        carry, out = TrmPort.act_forward(model, carry, batch)
        push!(states, deepcopy(carry)); push!(outputs, deepcopy(out))
    end
    return states, outputs
end
function check_config(io, c, w)
    tag = string(c, " ", w)
    w == "W0" && println(io, tag, " h_round_end: not applicable (no reference in fixture); model's own h_round_ends shape+finite only")
    try
        fx = fixture(c, w)
        model = TrmPort.ACTModel(fx.config, fx.state)
        n = length(fx.steps)
        states, outputs = trajectory(model, fx, n)
        ok = true
        for k in 1:n
            ok &= check_step(io, string(tag, " step", k), states[k], outputs[k], fx.steps[string("step", k)])
        end
        if c in ("a", "d") && w == "W1"
            haskey(fx.steps, "step4") || error("missing step4")
            mr, first = fx.mixed_reset, deepcopy(states[1])
            # oracle_work.py run_mixed_reset: retain step1 z, steps and current_data; replace halted only.
            mixed = TrmPort.Carry(first.z_H, first.z_L, first.steps, Bool.(mr["start_halted"]), first.current_data)
            carry, out = TrmPort.act_forward(model, mixed, fx.inputs[mr["input"]])
            ok &= check_step(io, string(tag, " mixed_reset"), carry, out, mr["step1"])
        end
        hs = TrmPort.h_round_ends(model, fx.inputs["x1"])
        hs isa AbstractVector && length(hs) == attr(fx.config, :H_cycles) || error("h_round_ends count/type")
        refs = w == "W1" ? fx.intermediates["h_round_end"] : nothing
        refs === nothing || length(hs) == length(refs) || error("h_round_end reference count")
        for (r, pair) in enumerate(hs)
            pair isa Tuple && length(pair) == 2 || error("h_round_ends tuple")
            for (j, q) in enumerate(("z_H", "z_L"))
                rt = string(tag, " h_round_end ", r, ".", q)
                if w == "W1"
                    ok &= report(io, rt, pair[j], reference(refs[r][q]))
                else
                    v = pair[j]
                    good = v isa AbstractArray && size(v) == size(getproperty(states[1], Symbol(q))) && all(isfinite, v)
                    println(io, rt, " shape+finite ", good ? "PASS" : "FAILED")
                    ok &= good
                end
            end
        end
        return ok
    catch e
        println(io, tag, " FAILED: ", sprint(showerror, e))
        return false
    end
end
function injected(fx, id)
    cfg, state = fx.config, deepcopy(fx.state)
    id == "i" && (state["inner.L_level.layers.0.mlp.down_proj.weight"][1, 1] += Float32(0.01))
    id == "ii" && (cfg = cfg_with(cfg, :H_cycles))
    id == "iii" && (cfg = cfg_with(cfg, :L_cycles))
    return TrmPort.ACTModel(cfg, state; swap_update_order=id == "iv", q_head_pos=id == "v" ? 2 : 1,
                           bad_rope_value=id == "vii", bad_norm_order=id == "viii")
end
function control(io, label, id, c, step, quantities)
    tag = string(label, " ", c, " W1 step", step, " ", join(quantities, ","))
    try
        fx = fixture(c, "W1")
        _, normal = trajectory(TrmPort.ACTModel(fx.config, fx.state), fx, step)
        ref = fx.steps[string("step", step)]
        # Every compared normal quantity must match the official reference before injection.
        Set(keys(normal[end])) == Set(OUT_KEYS) || error("normal output keys: control not established")
        for q in quantities
            good, md, detail = difference(normal[end][q], reference(ref[q]))
            good || error(string("normal ", q, " diff=", md, detail, "; control not established"))
        end
        _, bad = trajectory(injected(fx, id), fx, step; swap=id == "vi")
        details, caught = String[], true
        for q in quantities
            _, md, detail = difference(bad[end][q], reference(ref[q]))
            caught &= md > TOL
            push!(details, string(q, " max_abs_diff=", md, detail))
        end
        println(io, label, caught ? " caught: " : " FAILED: ", c, " W1 step", step, " ", join(details, "; "))
        return caught
    catch e
        println(io, tag, " FAILED: ", sprint(showerror, e))
        return false
    end
end
function main()
    open(joinpath(@__DIR__, "results-port.out"), "w") do io
        ok, caught = true, 0
        try
            println(io, "S56 ACT: max_abs_diff <= ", TOL, "; shapes/keys exact; finite; integer/bool type+value exact")
            for c in ("a", "b", "c", "d", "e"), w in ("W0", "W1")
                ok &= check_config(io, c, w)
            end
            # Explicit IDs, configurations, steps and quantities; each control emits exactly one line.
            caught += control(io, "negative control (i)", "i", "a", 4, ("logits",))
            caught += control(io, "negative control (ii)", "ii", "a", 4, ("logits",))
            caught += control(io, "negative control (iii)", "iii", "a", 4, ("logits",))
            caught += control(io, "negative control (iv)", "iv", "a", 1, ("logits",))
            caught += control(io, "negative control (v)", "v", "a", 1, ("q_halt_logits", "q_continue_logits"))
            caught += control(io, "negative control (vi)", "vi", "d", 1, ("logits",))
            caught += control(io, "negative control (vii)", "vii", "a", 4, ("logits",))
            caught += control(io, "negative control (viii)", "viii", "c", 1, ("logits",))
        catch e
            println(io, "FAILED: unexpected exception: ", sprint(showerror, e))
            ok = false
        end
        ok &= caught == 8
        println(io, "negative controls caught: ", caught, "/8")
        println(io, ok ? "ALL PASS" : "FAILED")
        return ok
    end
end
ok = main()
abspath(PROGRAM_FILE) == (@__FILE__) && exit(ok ? 0 : 1)
