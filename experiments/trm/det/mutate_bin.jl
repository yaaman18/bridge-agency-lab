# S60 negative-control inputs. Usage:
#   julia mutate_bin.jl m3 IN OUT            bundle: rope.cos[1,0] one ulp up
#   julia mutate_bin.jl m4 IN OUT            bundle: embed_tokens[t,0] one ulp up, t = x1.inputs[0,0]
#   julia mutate_bin.jl flipbit IN OUT NAME IDX BIT   output: flip bit BIT of f32 element IDX (0-based) of record NAME
#   julia mutate_bin.jl settag IN OUT NAME   output: mark f32 record NAME as i32 (payload bytes unchanged)
include(joinpath(@__DIR__, "TrmDet.jl"))
using .TrmDet
function main(a)
    mode, inp, out = a[1], a[2], a[3]
    magic = mode in ("m3", "m4") ? TrmDet.MAGIC_BUNDLE : TrmDet.MAGIC_OUT
    recs = TrmDet.read_recs(inp, magic)
    d = TrmDet.recdict(recs)
    function bump!(name, idx)
        r = d[name]
        old = r.f[idx+1]
        r.f[idx+1] = nextfloat(old)
        println(mode, ": ", name, "[", idx, "] ", old, " -> ", r.f[idx+1])
    end
    if mode == "m3"
        hd = d["rope.cos"].dims[2]
        bump!("rope.cos", 1 * hd + 0)
    elseif mode == "m4"
        H = d["inner.embed_tokens.embedding_weight"].dims[2]
        t = Int(d["x1.inputs"].i[1])
        bump!("inner.embed_tokens.embedding_weight", t * H + 0)
    elseif mode == "flipbit"
        r = d[a[4]]; idx = parse(Int, a[5]); bit = parse(Int, a[6])
        old = r.f[idx+1]
        r.f[idx+1] = reinterpret(Float32, reinterpret(UInt32, old) ⊻ (UInt32(1) << bit))
        println(mode, ": ", a[4], "[", idx, "] bit ", bit, " ", old, " -> ", r.f[idx+1])
    elseif mode == "settag"
        j = findfirst(r -> r.name == a[4], recs)
        r = recs[j]
        recs[j] = TrmDet.RecI(r.name, r.dims, reinterpret(Int32, r.f) |> collect)
        println(mode, ": ", a[4], " tag f32 -> i32")
    else
        error("mode")
    end
    TrmDet.write_recs(out, magic, recs)
end
main(ARGS)
