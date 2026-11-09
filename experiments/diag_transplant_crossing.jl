cd(ENV["LABEXP"])
src = read("transplant.jl", String); include_string(Main, src[1:findfirst("res = Dict", src)[1]-1])
su = LBA.setup_with(H)
for a in (:std, :swap), s in parse.(Int, split(get(ENV, "DSEEDS", "431,432,433,434,435,436,437,438,439,440"), ","))
    o = org(s, su, a); b = o.b; q(r, m) = o.raised.q[edge_of(b, r, m)]
    println(rpad(a, 6), s, "  m1<- r1,r2,r7,r8 q=", [q(r, "m1") for r in ("r1","r2","r7","r8")], "  m2<- ", [q(r, "m2") for r in ("r1","r2","r7","r8")],
            "  m1/m2 in-edge q,sg,h equal to 432: ", deq([getf(o.raised, f, k) for k in targets(b), f in FIELDS], (p = org(parse(Int, get(ENV, "DREF", "432")), su, a); [getf(p.raised, f, k) for k in targets(p.b), f in FIELDS])))
end
