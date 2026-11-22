# S61 予測と反証条件（r3・実行前に凍結）

- 対象仕様: `discussion/specs/S61-nesting-cpc.md`（r3）
- 評価種子: `890..909`（20 種子、開発用 `886..889` と完全分離。偽摂動校正 $\delta=0$ も同一の 20 評価種子 890..909 すべてで実施）
- 規律: 結果を見た後に本ファイルを書き換えない。外れた予測は外れたと報告する。`phenomenal_claim = :not_certified`。

## 予測（P-S61-1〜P-S61-5）

- **P-S61-1（Lean 形式証明・Stage 0/1 分離・R2 整形式）**:
  - `formal/NestingLineage.lean` が `sh formal/check.sh` に含まれてエラー 0・`sorry` 0・標準公理のみで通過し、5 つの名前つき定理（`stage0_isomorphic`, `stage1_separates_persist_and_replace`, `split_continuant_unique`, `merge_fusion_no_continuant`, `body_death_irreversible`）が検証される。
  - Julia 側で全 20 評価種子・全歩にわたって R2 違反 0 件、かつ `deepcopy` 2 継続出力・スロット再利用コピーの 2 負試験が 100% 検出される。

- **P-S61-2（E1 暴走対照との分離・P-05 準拠）**:
  - 20 評価種子（890..909）において、`CPC-Prolif` の生存種子集合は `Runaway-Cancer` の生存種子集合を厳密に包含する（論理的優越：期待は `CPC-Prolif` 20/20 生存 vs `Runaway-Cancer` 0/20 生存）。
  - `CPC-Prolif` の平均最大負債は `Runaway-Cancer` の平均最大負債より厳密に小さい。
  - `CPC-Prolif` の全生存歩プール（20 種子合算、死後打ち切り）における同歩誕生数 `birth_t` と維持費赤字 `deficit_t` のピアソン相関 $r$ が定義され（非ゼロ分散）かつ厳密に負（$r < 0$）となる。

- **P-S61-3（E2 外部非干渉＋絶対時計時間シフト不変性）**:
  - 同一許可初期状態・同一 `tape` 上で、`CPC-Prolif` は外部禁止入力変化および開始絶対時刻シフト（`t_start = 0` vs `20`）の双方について 20/20 評価種子で全許可状態・turnover・$L_t$ がビット一致する。
  - `Hidden-Age-Control` は同一時間シフト操作（`t_start = 0` のみ `t_abs == 15` 強制分裂を通過）により 20/20 評価種子で `L_t` の不一致が検出される。

- **P-S61-4（E3′ 厳格分離・優先順位 `unresolved > core_present > no_core_witnessed`）**:
  - 全 20 評価種子で適格交代歩 $t^*$（前後プローブ窓が完全かつ生存・$|M| \ge 3$）が 20/20 存在し、偽摂動（$\delta = 0$）の差分は厳密に `0.0` である。
  - 身体隔離下で `CPC-Prolif` は 20/20 で **`no_core_witnessed`**（$t^*$ 前後・位相切替前後とも窓 $\Delta = 2$ 内の残差伝播 $|\Delta \hat{p}_j| > 10^{-9}$、正の迂回証人、ホスト/規則両粒度で最小頂点カット $\ge 2$）。
  - `Fixed-Core`、`Rotating-Mediator-Failover`、`Rotating-Mediator-Redundant`（キャッシュ記載正対照）の 3 系はすべて 20/20 で **`core_present`**（いずれかが `unresolved` や `no_core_witnessed` を返せば予測外れ）。
  - `Omitted-Cache-Control` は 20/20 で **`unresolved`** を返す。

- **P-S61-5（決定性・凍結整合）**:
  - 20 評価種子の 2 回独立実行が全出力ビット一致し、`experiments/freeze-nesting-cpc.txt` の SHA-256 と一致する。

## 反証条件
1. `formal/NestingLineage.lean` の 5 定理のいずれかが通らない、標準外公理が出る、または R2 負試験を取りこぼす。
2. `CPC-Prolif` が `Runaway-Cancer` に対して生存優越・最大負債低下・$r < 0$（非ゼロ分散）のいずれか 1 つでも満たさない。
3. `CPC-Prolif` で外部禁止入力または時間シフトの差分が 1 件でも出る、または `Hidden-Age-Control` を 1 種子でも見逃す。
4. 適格 $t^*$ が 1 種子でも欠落、偽摂動差分が非ゼロ、3 負対照（キャッシュ記載正対照を含む）が 1 件でも `core_present` 以外を返す、`Omitted-Cache-Control` が `unresolved` 以外を返す、または `CPC-Prolif` が誤棄却される。
5. 決定性不一致、凍結 SHA-256 不一致、または `phenomenal_claim` 逸脱（P-11 違反）。
