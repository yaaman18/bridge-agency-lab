# S90 negative controls NC1-NC7 (spec r2 §3): each mutation must fail its intended gate; a pass is an error exit.
# Includes l2l_trm.jl unchanged. A mutation re-evaluates one function's source text from mem_core.jl / l2l_trm.jl with one
# anchored replacement (exactly one occurrence), runs the shared gate function, then restores the original text.
# Each gate is first run unmutated and must pass. usage: julia --project=. experiments/s90_l2l_trm/neg_controls.jl
include(joinpath(@__DIR__, "l2l_trm.jl"))
const SRC_MC = read(joinpath(@__DIR__, "mem_core.jl"), String)
const SRC_L = read(joinpath(@__DIR__, "l2l_trm.jl"), String)
const NCBAD = Ref(0)
for f in NCFILES; println("sha256 $f ", bytes2hex(open(sha256, joinpath(@__DIR__, f)))); end   # checked by run90 (nc_log_check)
flush(stdout)

function fdef(src, head)                      # text of the top-level `function head...` up to its column-0 `end`
    i = findall("\nfunction " * head, src); length(i) == 1 || error("anchor: function $head")
    a = first(i[1]) + 1; e = findnext("\nend\n", src, a); e === nothing && error("anchor: end of $head")
    return src[a:last(e)]
end
ncok(msg, want, after) = msg !== nothing && occursin(want, msg) && after === nothing
runmsg(gate) = try; Base.invokelatest(gate); nothing; catch e; sprint(showerror, e); end

function nc(name, mod, src, head, from, to, gatename, gate, want)
    t0 = time()
    base = runmsg(gate)
    base === nothing || error("$name: gate $gatename fails unmutated: $(first(base, 200))")
    f = fdef(src, head); length(findall(from, f)) == 1 || error("$name: mutation anchor not unique in $head")
    Base.include_string(mod, replace(f, from => to))
    msg = runmsg(gate)
    Base.include_string(mod, f)
    after = runmsg(gate)
    ok = ncok(msg, want, after)
    ok || (NCBAD[] += 1)
    println("$name: $gatename passes unmutated; mutated ", msg === nothing ? "PASSED (control failed)" : "failed with \"$(first(msg, 140))\"",
            "; restored passes: $(after === nothing) -> ", ok ? "ok (expected \"$want\")" : "NOT OK (expected \"$want\")",
            @sprintf(" [%.0f s]", time() - t0))
    flush(stdout)
end

const t00 = time()
MC.frozen90()
LV = lives83(); length(LV) == 48 || error("48 lives")
const X1 = LV[findfirst(v -> v.id == "st2 life 1", LV)]
const SS = setup90(X1; tmax = 9104, only = Set([TS[1]]))           # the smoke prefix (G6(d) twin at TS[1])
const SQ = setup90(X1; tmax = 800, only = Set{Int}())               # short prefix for GM2 / G6(a)
const MN1 = main90(SS)                                              # NC5 mutates only the twin path: G6(d) on the C1 twin only
@printf("setup (lives, smoke prefix, main 5 capacities x %d steps): %.0f s, threads %d\n", SS.N, time() - t00, Threads.nthreads()); flush(stdout)

nc("NC1 (postpaid free read: candidate committed without the prepaid settlement)", MC, SRC_MC, "memory_step!(",
   "    st = settle_upkeep!(cfg, M, B_vec, body_post, port_ref; cand = cand, use_naive_add = use_naive_add)",
   "    M.slots = cand.slots; st = (dead = false, purchased = length(M.slots), upkeep_evicted = 0, paid_total = 0.0, port_delta = 0.0, ops = 0, trace = NamedTuple[])",
   "GM4", () -> MC.run_gm4(), "(a)")

nc("NC2 (plain Float64 sum instead of add_down in the settlement)", MC, SRC_MC, "settle_upkeep!(",
   "adddn = use_naive_add ? (+) : add_down", "adddn = (+)",
   "GM4", () -> MC.run_gm4(), "(b) P1 boundary")

nc("NC3 (non-local R-MID: other contexts mixed in)", MC, SRC_MC, "read_memory_pair_key(",
   "if x.ctx_key == k && x.action == a", "if x.action == a",
   "GM5", () -> MC.run_gm5(), "GM5")

nc("NC4 (future leak: Y_t written before the read)", MC, SRC_MC, "memory_step!(",
   "    p1, p2, rops, h1, h2 = read_memory_pair_key(cfg, M, k, p1_trm, p2_trm)",
   "    write_memory_candidate!(cfg, M, k, a, y, a == 0x01 ? p1_trm : p2_trm, a == 0x01 ? p1_trm : p2_trm; remaining_ops = remaining_ops)\n    p1, p2, rops, h1, h2 = read_memory_pair_key(cfg, M, k, p1_trm, p2_trm)",
   "GM3", () -> gate_gm3(SS), "GM3(a) step-t output depends on Y_t")

nc("NC5 (twin reads the main trajectory's cached TRM predictions)", Main, SRC_L, "twin_trace(",
   "    return trt", "    return Trace(trt.b0, trt.t1, trm.P[:, (trt.b0 - trm.b0 + 1):(trt.t1 - trm.b0)], trt.O, trt.St, trt.LH)",
   "G6(d)", () -> gate_g6d(SS, MN1, twin90(SS, MN1, TS[1]; keeprecs = true); check_main = false, names = ("C1",)), "G6(d)")

nc("NC6 (C0 computes ctx_key and books OPS_CTX_KEY)", Main, SRC_L, "mem_read_c0(",
   "    return (p1, p2, 0)", "    kfn(); return (p1, p2, MC.OPS_CTX_KEY)",
   "GM2", () -> gate_gm2(SQ, main90(SQ; caps = CAPS90[1:2], hashes = true), SQ.N), "GM2")

nc("NC7 (ctx_key bit position shifted by one: bit i mod 6)", Main, SRC_L, "ctx_key(",
   "(k |= UInt64(1) << (i - 1))", "(k |= UInt64(1) << (i % 6))",
   "G6(a)", () -> (mn = main90(SQ; caps = CAPS90[3:5]); gate_g6a(SQ, mn.recs)), "G6(a)")

@printf("time: %.0f s\n", time() - t00)
println(NCBAD[] == 0 ? "negative controls: all 7 failed at their intended gates" : "negative controls: $(NCBAD[]) NOT OK")
NCBAD[] == 0 || exit(1)
