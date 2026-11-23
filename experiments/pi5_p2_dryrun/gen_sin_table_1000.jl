# S68 r2 §2: Generate canonical frozen SIN_TABLE_1000 (1000 Float64 IEEE-754 raw bits) from Julia
# and emit rust/onelife-trm/src/sin_table.rs + exact SHA-256 verification.
using SHA
using Printf

const ROOT = abspath(joinpath(@__DIR__, "..", ".."))
const RUST_OUT = joinpath(ROOT, "rust", "onelife-trm", "src", "sin_table.rs")

vals = [sin(2.0 * pi * Float64(idx) / 1000.0) for idx in 0:999]
bits = [reinterpret(UInt64, v) for v in vals]

io_bin = IOBuffer()
for b in bits
    write(io_bin, htol(b))
end
table_sha = bytes2hex(sha256(take!(io_bin)))

open(RUST_OUT, "w") do io
    println(io, "//! S68 r2 §2: Canonical frozen 1000-entry `SIN_TABLE_1000` generated from Julia `sin(2π * idx / 1000.0)`.")
    println(io, "//! Exact raw IEEE 754 binary64 bits guarantee zero libm trig drift between Julia and Rust (Mac & Pi 5).")
    println(io, "")
    println(io, "use crate::sha256::sha256_hex;")
    println(io, "")
    println(io, "pub const SIN_TABLE_SHA256: &str = \"", table_sha, "\";")
    println(io, "")
    println(io, "pub const SIN_TABLE_BITS: [u64; 1000] = [")
    for row in 0:199
        print(io, "    ")
        for col in 0:4
            idx = row * 5 + col + 1
            @printf(io, "0x%016x,", bits[idx])
            col < 4 && print(io, " ")
        end
        println(io)
    end
    println(io, "];")
    println(io, "")
    println(io, "pub fn sin_table_1000() -> [f64; 1000] {")
    println(io, "    let mut t = [0.0f64; 1000];")
    println(io, "    for i in 0..1000 {")
    println(io, "        t[i] = f64::from_bits(SIN_TABLE_BITS[i]);")
    println(io, "    }")
    println(io, "    t")
    println(io, "}")
    println(io, "")
    println(io, "pub fn verify_sin_table_sha256() -> String {")
    println(io, "    let mut raw = Vec::with_capacity(8000);")
    println(io, "    for &b in &SIN_TABLE_BITS {")
    println(io, "        raw.extend_from_slice(&b.to_le_bytes());")
    println(io, "    }")
    println(io, "    sha256_hex(&raw)")
    println(io, "}")
end

println("Generated ", RUST_OUT)
println("SIN_TABLE_SHA256=", table_sha)
@printf("idx=0:   %.17g (0x%016x)\n", vals[1], bits[1])
@printf("idx=250: %.17g (0x%016x)\n", vals[251], bits[251])
@printf("idx=500: %.17g (0x%016x)\n", vals[501], bits[501])
@printf("idx=750: %.17g (0x%016x)\n", vals[751], bits[751])
