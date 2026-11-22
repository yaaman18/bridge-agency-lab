# S61b 個体内増殖＋コアなし CPC のオーバーシュート解消（M1 限界維持費フィードバック、r2）

- 作成: 2026-11-22（`neon-lab`、r1 への `codex-lab` APPROVE・`claude-lab` 2 指摘［更新順序明記・ラグ相関診断］を反映。3 系統体制 §1.3 改訂［案 A］・§1.4 準拠）
- ゲート確認済み: `~/bridge-protocol` `pending_A = 0, warning = false, hard_stop = false`（2026-11-22 確認済み）。
- 親仕様: `discussion/specs/S61-nesting-cpc.md`（r3、不変として保存。本 S61b は別ディレクトリ・新種子・新凍結で実施）。

---

## 1. 目的・S61 からの厳格な差分・非目標
- **目的**: S61（項番176）で `CPC-Prolif` が摂動前に 12〜14 モジュールへ過剰増殖して致死負債に達した（P-S61-2 外れ）原因に対し、**人為的なモジュール数上限 $N_{\max}$ も外部スコア `Φ_rich` も導入せず、許可された M1 身体状態（収穫の指数移動平均 $\bar{h}_t$ と体サイズ比例の維持費準備金）のみによる内生的分裂抑制**を導入したとき、E1（暴走対照との厳密分離）を含め全関門 G0〜G5 が同時に成立するかを新種子で検証する。
- **S61 r3 からの厳格な差分（これ以外のパラメータ・配線・更新則・`Runaway-Cancer` 力学はすべて S61 r3 と 100% 同一）**:
  - 参照する S61 r3 固定値：$c_{\mathrm{mod}} = 0.55$, $c_{\mathrm{split}} = 1.5$, $R_0 = 20.0$, $R_{\max} = 40.0$, $D_0 = 0.0$, $D_{\mathrm{lethal}} = 12.0$, $u_0 = 4.0$, $h_{\mathrm{base}} = 3.0$（$k \in [45,65]$ は $1.2$）。
  1. **M1 身体状態に収穫の指数移動平均 $\bar{h}_t$ を追加**: 初期値 $\bar{h}_0 = 3.0$。1 歩の確定順序は次の通り固定する：
     `step 1 (alive 検査) → step 2 (予測・連合行為) → step 3 (収穫 h_t 算出 → 直後に h̄_{t+1} = 0.75·h̄_t + 0.25·h_t を更新) → step 4 (CPC 残差更新) → step 5 (維持費・負債・u_{i,t+1} 帳尻 → R_{t+1}, D_{t+1} 確定) → step 6 (death → merge → split［h̄_{t+1}, R_{t+1}, D_{t+1}, u_{i,t+1} を参照］ → lethal)`。
     $\bar{h}_t$ は許可された M1 状態であり、G3（E2 非干渉・時間シフト）のビット一致比較にも含める。
  2. **`CPC-Prolif` 系の分裂条件を M1 限界維持費フィードバックへ変更**:
     - 対象：`CPC-Prolif`・`Fixed-Core`・`Rotating-*`・`Omitted-*`・`Hidden-Age-Control` の通常分裂（**負対照 `Runaway-Cancer` の力学・分裂費支払いは S61 r3 と 100% 同一のまま据え置き、対照を一切弱めない**）：
       $$\bar{h}_{t+1} > 1.25 \cdot c_{\mathrm{mod}}(|M_t| + 1) \;\land\; R_{t+1} > 6.0 \cdot c_{\mathrm{mod}}(|M_t| + 1) \;\land\; D_{t+1} == 0.0 \;\land\; u_{i, t+1} > 5.5$$
     - 初期可実現性確認（開発種子非依存の事前算術）：$|M_0|=4$ で $1.25 \cdot 0.55 \cdot 5 = 3.4375$、通常期待収穫 $h \approx 5.5\text{–}6.4$ より $\bar{h}_t$ は数歩で $> 3.44$、$R$ は $> 16.5$ に到達しうる。
  3. **診断行の追加（非合否・報告専用）**:
     - G2 補助診断：ラグ相関 $\mathrm{corr}(\mathrm{birth}_t, \mathrm{deficit}_{t+k})$（$k = 1..12$）、`D > 0` となった生存歩数、`CPC-Prolif` の $\max_t |M_t|$ 分布を併記する（同歩 $D_{t+1} == 0$ 条件による $k=0$ の自明負相関を補完）。
     - G4 補助診断：全辺 `local_link(k→i)` を単一の共有規則へ潰した場合の判定結果も並記する（主判定 G4 の規則粒度は S61 r3 と同じく辺単位の独立規則）。
- **非目標**: S61 の既存ファイル（`experiments/nesting_cpc/`, `freeze-nesting-cpc.txt`, `results-nesting-cpc.out`）・`core/`・`rust/`・`~/bridge-protocol` の変更、`phenomenal_claim` の主張。

---

## 2. 対象集団・種子（S61 と完全分離・凍結対象）
- **環境再生テープ**: S61 r3 §3.1 と同一生成器（$T=120$、基礎周期 12 `111222333444`、雑音 `0.05`、$k=41,81$ 巡回置換、$k \in [45,65]$ で $h_{\mathrm{base}}=1.2$）。
- **種子割当（主列 910〜、S61 評価種子 `890..909` と完全分離）**:
  - 開発・煙確認用（評価集計外）: **`910..913`**（4 種子）
  - 本評価用（予測凍結後に 1 回評価）: **`914..933`**（20 種子）
  - 次回の未使用主列種子: **`934`**
- **一般化の範囲**: 本仕様の合成環境・M1 限界維持費フィードバック規則・20 評価種子（`914..933`）および 7 構成に限る。

---

## 3. 関門（GATE: S61 r3 §4 と同一基準）
- **G0（Lean）**: 既存 `formal/NestingLineage.lean` が無変更のまま `sh formal/check.sh` を PASS すること（エラー 0、`sorry` 0、標準公理のみ）。
- **G1（Stage 0/1 分離・R2 整形式＋負試験 2 件）**: 3 証人分離、7 構成×20 評価種子×120 歩で R2 違反 0 件、`deepcopy`・スロット再利用の 2 負試験とも 20/20 検出。
- **G2（E1 暴走分離、P-05 準拠）**: 20 評価種子（`914..933`）において、(a) `CPC-Prolif` の生存種子集合 $\supsetneq$ `Runaway-Cancer` の生存種子集合（厳密優越）、(b) `CPC-Prolif` の平均最大負債 $<$ `Runaway-Cancer` の平均最大負債、(c) `CPC-Prolif` の全生存歩プール（死後打ち切り）での同歩 `birth_t` と `deficit_t` のピアソン相関 $r < 0$（非ゼロ分散、NaN なら失敗）。あわせてラグ相関 $k=1..12$・`D>0` 歩数・$\max_t |M_t|$ を診断出力。
- **G3（E2 非干渉＋絶対時計時間シフト）**: `CPC-Prolif` 20/20 ビット一致（$\bar{h}_t$ も許可状態に含めて比較）、`Hidden-Age-Control` 20/20 検出（歩 15）。
- **G4（E3′ 厳格分離・独立目録監査）**: 全 20 評価種子で適格交代歩 $t^*$ が 20/20 存在（欠落は即 FAIL）、偽摂動 $\delta=0$ 差分 `0.0`、`CPC-Prolif` 20/20 `no_core_witnessed`、`Fixed-Core`・`Rotating-Mediator-Failover`・`Rotating-Mediator-Redundant` 各 20/20 `core_present`、`Omitted-Cache-Control` 20/20 `unresolved`。＋共有規則診断行を並記。
- **G5（決定性・凍結 SHA-256 照合）**: 2 回独立実行ビット一致、`experiments/freeze-nesting-cpc-b.txt` の SHA-256 一致。

---

## 4. `FILE:` 許可範囲
- `experiments/nesting_cpc_b/NestingCPCB.jl`（新規）
- `experiments/nesting_cpc_b/run_gates.jl`（新規）
- 出力：`experiments/results-nesting-cpc-b.out`
- 既存の `experiments/nesting_cpc/`・`formal/`・`core/`・`rust/`・`~/bridge-protocol` は一切変更しない。
