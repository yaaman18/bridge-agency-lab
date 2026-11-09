# G16 (notes/G16.md): the record check of the default matter rule (spontaneous = false, MATTER_DEF, torus 4-neighbours,
# sources = evo_sources from the port, Ctl with recording hooks only — they do not write C). Every birth (on_divide(i, j))
# has j a 4-neighbour of i and i a constituent at that time; every site that is 0 -> 1 across a step has a birth event in
# that step; deaths followed by a birth at the same site within one step are counted (new lineage nodes, D-b).
# Lineage: a node starts at the founders (seed!) or a birth, and ends at the death of its site. No predictions (a check).
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, ".."))
out = Any[]
for (k, (res0, steps)) in enumerate(((2000.0, 3000), (300.0, 3000), (2000.0, 6000)))
    w = LC.make_world(; reservoir = res0); LC.seed!(w, 12, 12, 1)
    node = zeros(Int, LC.nsites(w)); nid = 0; parent = Dict{Int,Int}(); ended = Set{Int}()
    for i in eachindex(w.C); w.C[i] != 0 && (nid += 1; node[i] = nid); end
    births = 0; deaths = 0; bad_nb = 0; bad_parent = 0; unexplained = 0; reoccupied_same_step = 0; reborn_node_reused = 0
    for t in 0:steps-1
        before = copy(w.C); ev_b = Set{Int}(); ev_d = Set{Int}()
        ctl = LC.Ctl(on_death = i -> (push!(ev_d, i); push!(ended, node[i]); node[i] = 0),
                     on_divide = (i, j) -> begin
                         push!(ev_b, j)
                         j in w.nb4[:, i] || (global bad_nb += 1)
                         w.C[i] != 0 || (global bad_parent += 1)
                         nid += 1; node[j] = nid; parent[nid] = node[i]
                     end)
        LC.step!(w, LC.evo_sources(w, t), ctl)
        births += length(ev_b); deaths += length(ev_d)
        for i in eachindex(w.C)
            (before[i] == 0 && w.C[i] != 0 && !(i in ev_b)) && (unexplained += 1)
            (i in ev_d && i in ev_b) && (reoccupied_same_step += 1)
        end
    end
    reborn_node_reused = count(n -> n in ended, node)   # a live site carrying an ended node would break D-b
    row = Dict("world" => k, "reservoir" => res0, "steps" => steps, "births" => births, "deaths" => deaths, "bad_neighbour" => bad_nb, "bad_parent" => bad_parent,
               "unexplained_0to1" => unexplained, "reoccupied_same_step" => reoccupied_same_step, "live_sites_with_ended_node" => reborn_node_reused, "end_constituents" => LC.nconstituents(w), "born_counter" => w.born, "died_counter" => w.died)
    push!(out, row); println(row)
end
write(joinpath(LAB, "experiments", "results-con-lineage.json"), JSON.json(out, 2))
