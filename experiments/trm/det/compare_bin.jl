# S60 G-ii / G-iii comparator. Usage: julia compare_bin.jl BUNDLE A B [BUNDLE A B ...]
# Checks both outputs have exactly the 45 records of spec §2 in order with the expected type and shape (from the bundle
# cfg), then compares every element bitwise. Exit 0 only if every triple is structurally right and bit-identical.
include(joinpath(@__DIR__, "TrmDet.jl"))
using .TrmDet

function structure(recs, lay)
    length(recs) == length(lay) || return string("record count ", length(recs), " != ", length(lay))
    for (r, (n, t, d)) in zip(recs, lay)
        r.name == n || return string("record name ", r.name, " != ", n)
        r.tag == t || return string("record type of ", n, " ", r.tag, " != ", t)
        r.dims == d || return string("record shape of ", n, " ", r.dims, " != ", d)
        cnt = prod(d)
        (t == TrmDet.TAG_F32 ? length(r.f) : length(r.i)) == cnt || return string("record length of ", n)
        cnt > 0 || return string("empty record ", n)
    end
    return ""
end

function compare_one(io, bundle, a, b)
    tag = string(basename(a), " vs ", basename(b))
    try
        lay = TrmDet.expected_layout(TrmDet.read_recs(bundle, TrmDet.MAGIC_BUNDLE))
        ra = TrmDet.read_recs(a, TrmDet.MAGIC_OUT)
        rb = TrmDet.read_recs(b, TrmDet.MAGIC_OUT)
        for (side, r) in (("A", ra), ("B", rb))
            s = structure(r, lay)
            isempty(s) || (println(io, tag, " FAILED structure ", side, ": ", s); return (false, 0, 0))
        end
        nel, ndiff, maxabs, first = 0, 0, 0.0, ""
        for (x, y) in zip(ra, rb)
            if x.tag == TrmDet.TAG_F32
                for j in eachindex(x.f)
                    nel += 1
                    if reinterpret(UInt32, x.f[j]) != reinterpret(UInt32, y.f[j])
                        ndiff += 1
                        isempty(first) && (first = string(x.name, "[", j - 1, "] ", x.f[j], " vs ", y.f[j]))
                        d = abs(Float64(x.f[j]) - Float64(y.f[j]))
                        maxabs = isnan(d) ? Inf : max(maxabs, d)
                    end
                end
            else
                for j in eachindex(x.i)
                    nel += 1
                    if x.i[j] != y.i[j]
                        ndiff += 1
                        isempty(first) && (first = string(x.name, "[", j - 1, "] ", x.i[j], " vs ", y.i[j]))
                        maxabs = max(maxabs, abs(Float64(x.i[j]) - Float64(y.i[j])))
                    end
                end
            end
        end
        same_bytes = read(a) == read(b)
        ok = ndiff == 0 && same_bytes && nel > 0
        println(io, tag, " records ", length(ra), " elements ", nel, " differing ", ndiff, " max_abs ", maxabs,
                " bytes_identical ", same_bytes, ok ? " PASS" : " FAILED", isempty(first) ? "" : string(" first ", first))
        return (ok, nel, ndiff)
    catch e
        println(io, tag, " FAILED: ", sprint(showerror, e))
        return (false, 0, 0)
    end
end

function main(args)
    (!isempty(args) && length(args) % 3 == 0) || (println("usage: compare_bin.jl BUNDLE A B ..."); return 1)
    allok, npass, tot, totd = true, 0, 0, 0
    for j in 1:3:length(args)
        ok, nel, nd = compare_one(stdout, args[j], args[j+1], args[j+2])
        allok &= ok; npass += ok; tot += nel; totd += nd
    end
    println("compared pairs ", length(args) ÷ 3, " passed ", npass, " elements ", tot, " differing ", totd, allok ? " ALL IDENTICAL" : " NOT IDENTICAL")
    return allok ? 0 : 1
end
exit(main(ARGS))
