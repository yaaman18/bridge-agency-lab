# `rust/onelife-trm/` — Phase 3 最小 4 継ぎ目・床スケルトン（独立 Cargo ワークスペース）

- **位置づけ**: [PLAN-PI5-TRM-DEPLOY.md](../../discussion/notes/PLAN-PI5-TRM-DEPLOY.md) Phase 3 および [D-AUE-SPECIES-AND-GAPS.md](../../discussion/notes/D-AUE-SPECIES-AND-GAPS.md) O30〜O32 に基づき、TRM 重み確定（S64 C0 完了）を待たずに先行実装した **依存ゼロ（`std` のみ）の最小 4 継ぎ目床スケルトン＋S68 r2 電波換算・`stale`・`rand_u64` モジュール**。
- **非変更対象**: `rust/Cargo.toml`・`rust/being-core`・`rust/being-tools`・`rust/trm-det`・`core/`・`~/bridge-protocol` は一切変更していない。
- **範囲限定（厳守）**:
  - 本スケルトンが裏づけるのは「4 継ぎ目床・`species_spec.toml` 解析・監査鎖再生・S68 換算・Pi 5 向け `aarch64-unknown-linux-musl` 静的クロスビルドの成立」まで。
  - **Rust 床の多型汎用性は Phase 6 で第 2 種（実種）が同じ Rust 床を無変更で通るまで未主張（保留）** とする。`phenomenal_claim = :not_certified`。

## 構成
- `src/sha256.rs`: 依存ゼロ FIPS 180-4 SHA-256。
- `src/spec.rs`: Seam 1 `species_spec.toml` パーサ（Julia `experiments/aue_seam/species_aue_{a,b}.toml` と `spec_sha256` ビット完全一致を単体テスト照合）。
- `src/bed.rs`: Seam 2〜4 種非依存の床（`Port`・`Ledger` 3 区分終了コード・`Budget` 1 歩／瞬間レート／3,600 秒スライディング窓・休眠会計・死後 `commit` 0 件・監査鎖テキスト単一正本からの完全再生・共有媒体 `event_ref` 二重取得検査）。
- `src/c4_radio.rs`: S68 r2 凍結 C4 換算（`f64::round_ties_even`）・NTP 耐性 `stale` 判定（`same_row_streak >= 14`＋`CLOCK_MONOTONIC > 120.0`）・`rand_u64` 決定導出。
- `src/main.rs`: 最小 CLI (`verify-spec`, `version`) および全単体テスト。

## テスト＆Pi 5 クロスビルド
```sh
cd /Users/yamaguchimitsuyuki/bridge-agency-lab/rust/onelife-trm
cargo test --offline
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --release --offline --target aarch64-unknown-linux-musl
```
