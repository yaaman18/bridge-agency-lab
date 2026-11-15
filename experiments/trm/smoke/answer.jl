# deepseek-loop の動作の試し: 1 から 20 までの整数のうち 3 の倍数の二乗の和を
# experiments/trm/smoke/answer.out に「sum=<値>」の 1 行で書く（値は計算で出す）。
# ライセンス: このラボの規約に従う（experiments/trm/smoke/answer.jl、新規作成）。
Core.eval(Main.Sys, :(dont_write_bytecode = true))

function main()
    total = 0
    for n in 1:20
        if n % 3 == 0
            total += n * n
        end
    end
    path = joinpath(@__DIR__, "answer.out")
    open(path, "w") do io
        println(io, "sum=", total)
    end
end

main()
