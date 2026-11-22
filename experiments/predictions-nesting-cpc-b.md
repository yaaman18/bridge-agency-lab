# S61b 予測と反証条件（r2・実行前に凍結）

- 対象仕様: `discussion/specs/S61b-nesting-cpc-bounded.md`（r2）
- 評価種子: `914..933`（20 種子、開発用 `910..913` および S61 評価用 `890..909` と完全分離）
- 規律: 結果を見た後に本ファイルを書き換えない。外れた予測は外れたと報告する。`phenomenal_claim = :not_certified`。

## 予測（P-S61b-1〜P-S61b-5）

- **P-S61b-1（G0・G1：Lean 継承・Stage 0/1 分離・R2 整形式）**:
  - `formal/NestingLineage.lean` が無変更で `sh formal/check.sh` を通過し、Julia 側で 7 構成×20 評価種子×120 歩にわたり R2 違反 0 件、負試験 2 件とも 20/20 検出。

- **P-S61b-2（G2：E1 オーバーシュート解消・暴走対照への厳密優越）**:
  - 20 評価種子（`914..933`）において、`CPC-Prolif` の生存種子集合は S61 と同一力学の `Runaway-Cancer` の生存種子集合を**厳密に包含**する（`survivors(CPC-Prolif) ⊋ survivors(Runaway-Cancer)`）。
  - `CPC-Prolif` の平均最大負債は `Runaway-Cancer` の平均最大負債より厳密に小さい。
  - `CPC-Prolif` の全生存歩プール（死後打ち切り）における同歩 `birth_t` と `deficit_t` のピアソン相関 $r$ が非ゼロ分散で定義され、厳密に負（$r < 0$）となる（あわせてラグ相関 $k=1..12$・`D>0` 歩数・$\max_t |M_t|$ を診断報告）。

- **P-S61b-3（G3：E2 外部非干渉＋絶対時計時間シフト）**:
  - `CPC-Prolif` は外部禁止入力変化および開始時刻シフト（`t_start = 0` vs `20`）の両方で 20/20 ビット一致（$\bar{h}_t$ を含む全許可状態・turnover・$L_t$）。
  - `Hidden-Age-Control` は同一時間シフトで 20/20 検出（歩 15）。

- **P-S61b-4（G4：E3′ 厳格分離・優先順位 `unresolved > core_present > no_core_witnessed`）**:
  - 全 20 評価種子で適格交代歩 $t^*$ が 20/20 存在し（M1 限界維持費フィードバック下でも分裂が少なくとも 1 回起き、$t^*$ 欠落なし）、偽摂動 $\delta=0$ 差分は `0.0`。
  - `CPC-Prolif` 20/20 `no_core_witnessed`、3 負対照すべて 20/20 `core_present`、`Omitted-Cache-Control` 20/20 `unresolved`。
  - （診断・非合否）全辺を単一共有規則へ潰した診断では `CPC-Prolif` も `core_present` になることを確認・記録。

- **P-S61b-5（G5：決定性・凍結整合）**:
  - 2 回独立実行ビット一致、凍結 SHA-256 一致。

## 反証条件
1. P-S61b-2 の (a) 厳密優越、(b) 平均最大負債低下、(c) $r < 0$（非ゼロ分散）のいずれか 1 つでも不成立（例：分裂が全く起きず分散 0 で `NaN`、または依然としてオーバーシュート死する）。
2. P-S61b-1・P-S61b-3・P-S61b-4・P-S61b-5 のいずれかが 1 種子でも外れる（特に M1 抑制が強すぎて適格 $t^*$ が 1 種子でも欠落した場合は P-S61b-4 外れ）。
3. `phenomenal_claim` 逸脱、または既存 S61 ファイル・`core/`・`~/bridge-protocol` への無断変更。
