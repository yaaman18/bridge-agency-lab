# `rust/onelife-trm/` — Phase 3 統合ランタイム基盤（最小 4 継ぎ目床＋TRM 決定推論＋C2 頭学習＋S68 電波・復電）

- **位置づけ**: [PLAN-PI5-TRM-DEPLOY.md](../../discussion/notes/PLAN-PI5-TRM-DEPLOY.md) Phase 3 および [D-AUE-SPECIES-AND-GAPS.md](../../discussion/notes/D-AUE-SPECIES-AND-GAPS.md) O30〜O32 に基づく、**依存ゼロ（`std` のみ）独立 Cargo ワークスペース**。
- **非変更対象**: `rust/Cargo.toml`・`rust/being-core`・`rust/being-tools`・`rust/trm-det`・`core/`・`~/bridge-protocol` は一切変更していない。
- **範囲限定（厳守）**:
  - 本実装が裏づけるのは「4 継ぎ目床・`species_spec.toml` 解析・監査鎖再生・内蔵 TRM 決定推論（Julia `TrmDet.jl` ビット完全一致）・C2 97 パラメータ頭学習・S68 `SIN_TABLE_1000`/換算/`stale`/断電復電 A〜D・Pi 5 `aarch64-unknown-linux-musl` 実機動作」まで。
  - **Rust 床の多型汎用性は Phase 6 で第 2 種（実種）が同じ Rust 床を無変更で通るまで未主張（保留）** とする。`phenomenal_claim = :not_certified`。

## モジュール構成
- `src/sha256.rs`: 依存ゼロ FIPS 180-4 SHA-256。
- `src/spec.rs`: Seam 1 `species_spec.toml` パーサ（Julia `species_aue_{a,b}.toml` と `spec_sha256` ビット完全一致）。
- `src/bed.rs`: Seam 2〜4 種非依存の床（`Port`・`Ledger` 3 区分終了コード・`Budget` 1 歩／瞬間レート／3,600 秒スライディング窓・休眠会計・死後 `commit` 0 件・監査鎖テキスト単一正本からの完全再生・共有媒体 `event_ref` 二重取得検査）。
- `src/trm_infer.rs`: S60 `TrmDet.jl` ビット完全一致の内蔵 TRM 決定推論ライブラリ＋`B_max` 枠付き `forward_budgeted`（0 巡フォールバック `H_init` 完備）。
- `src/head_c2.rs`: S67 r2 97 パラメータ C2 オンライン頭学習（`lm_head` ゼロ `exp` 閉形式 `stablemax` 勾配・S60 `exp_det` 共有・`0.875` 薄れ・死亡凍結・予算スキップ・`NaN` 停止）。
- `src/sin_table.rs`: S68 r2 Julia 生成の凍結 1,000 項 `SIN_TABLE_1000`（raw IEEE 754 `u64` ビット、`SHA-256 = 170c65df...c58a`）。
- `src/c4_radio.rs`: S68 r2 凍結 C4 換算（`f64::round_ties_even`）・NTP 耐性 `stale` 判定・`rand_u64` 決定導出。
- `src/recovery.rs`: S68 r2 S49d 整合の断電復電ケース A〜D 状態機械。
- `src/main.rs`: CLI (`verify-spec`, `verify-sin`, `run-trm`, `version`) および全 9 単体テスト。

## テスト＆Pi 5 クロスビルド
```sh
cd /Users/yamaguchimitsuyuki/bridge-agency-lab/rust/onelife-trm
cargo test --release --offline
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=rust-lld cargo build --release --offline --target aarch64-unknown-linux-musl
```
