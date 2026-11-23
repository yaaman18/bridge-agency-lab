# S63 余地の監査（C0 の第 0 手：UNI 全歩記録上の予測余地とベイズ上限照合）— r3

- **改訂履歴**:
  - r1 → r2（2026-11-23、`claude-lab`・`codex-lab` 並列 S-R r1 の全指摘反映、`claude-lab` APPROVE）。
  - r2 → r3（2026-11-23、`codex-lab` S-R r2 の高指摘 P1「`obs` での行動選択尤度省略反例」を反映：外生行動トラック `exo` を追加して厳密ベイズ上限を保証し、`obs` トラックの停止主張射程を厳密限定）。
- **目的**: `(a, Y)` 履歴のみを入力とする `seq_len = 47` TRM 移植・学習（C0）へ進む前に、合成世界 2 族（定常 `stat`・逆転 `rev`）の上で、単一痕跡 `B1` を超えて予測精度を改善できる構造的余地 $\Delta = L(\mathrm{B1}) - L(\mathrm{BAYES\_raw})$ が実用上存在するかを事前凍結プロトコルで反証・検証する。
  - **2 トラック分離（r3 追加）**:
    - **`exo` トラック（外生行動・厳密上限検証）**: 毎歩の行動 $A_s \in \{1,2\}$ を `gen_bits(u)` から厳密外生（$A_s \perp (\theta, z, b_{\mathrm{rev}})$）に引く。選択尤度の省略がゼロであるため、`BAYES_raw` はこのトラック上で数学的に**厳密な最小対数損失上限**となる。
    - **`obs` トラック（正本 `L2 UNI` 身体軌道・実測基準検証）**: 正本 OneLife（`LawL2`・UNI 引き手・`core/` 無変更）の観測軌道上で同じ外生行動ベイズフィルタ `BAYES_raw` を評価する。行動発生・無行為が回路受容器を通じて潜在状態に依存しうるため、`obs` 上の `BAYES_raw` は「選択尤度をモデル化しない基準フィルタ」として扱い、厳密理論上限の主張は `exo` トラックに限定する。
- **対応する要件・出典**:
  - `discussion/notes/D-PRED-ARCH.md` §3（3 系統合意 C1・O27〜O29、2026-11-23）
  - `discussion/fable/20261123-101812-review.md` 提案 A（議決権なし、3 系統で改訂採択）
  - `discussion/notes/D-PRED.md` 第二部 §2（時刻順・UNI 記録・B1・`W=4` 表・24 種子）
  - `discussion/user-decisions.md`（2026-11-23: U2=`(ア)` 確定、U4=`(ア)`・U5=`(ア)` 確定、第一号切り出しは予測器系列まで、3 系統合意案開始承認）
  - `experiments/memory-transfer-c0/README.md`（S57 コード無変更ロード様式・`B1` の `P_DECAY = 8`）
- **依っている仮定**:
  - **H7**（`discussion/bp-proposals.md` BP10: 予測器は回路＋物質の法則の内側に置く臓器として扱い、BP 個体性・生死定義は変えない）。
  - `~/bridge-protocol`・`core/`・`rust/`・S57 コード（`freeze-draw-conf-code.txt` の 6 ファイル）は一切変更しない。
- **用語（decisions-log #36）**: 生活の比喩を使わず、条件 ID（法則 `L2`、腕 `UNI`、世界族 `stat` / `rev`、枠長 `STEPS = 10000`, `T0 = 800`, 評価窓 `s ∈ 0..9199`）で記す。

---

## 1. 対象集団・種子割り当て（予測と一緒に凍結）

- **主列未使用種子（次番 `1006` 起算、既存 `1..1005` および `52xxx` と完全に素）**:
  - 関門・開発（`dev`）: **`1006..1009`**（4 種子）
  - 学習（`train`、`RATE` と `TAB4` の経験確率推定のみに**世界族ごと個別**使用）: **`1010..1021`**（12 種子）
  - 評価（`eval`、一切の調整に使わない）: **`1022..1045`**（24 種子）
  - **次の未使用主列種子**: **`1046`**
- **体と引き手（固定条件）**:
  - S57 の凍結コード 6 本（`draw_conf_grid.jl`, `check_draw_conf.jl`, `check_draw.jl`, `synth_world.jl`, `core/circuit.jl`, `core/body_org.jl`）を `memory-transfer-c0/c0.jl:29-42` と同じ無変更ロード方式で読み込み、SHA-256 を `freeze-draw-conf-code.txt` と照合する（関門 G0）。
  - 法則 `L2`（S57 `BASE`）、腕 `UNI`、乱数ビット `gen_bits(u)`（S55 規則、メモリ上のみ）。
  - 評価対象の例（`ex`）: 窓 `t >= T0` の中で `length(cs) >= 2` の引いた歩（`a ∈ {1, 2}`、`Y = (y[a] > 0)`）。
  - 更新入力: 窓 `t >= T0` の全歩における実際の行為と応え（`ON_STEP` 読み取り専用観察）。**歩 `t` の予測は必ず歩 `t-1` までの観測のみを読む**（`D-PRED.md:111`）。全更新歩で `length(acts) <= 1` であることを関門 G2 で全数検査する。
- **世界族（変動条件、2 族）**:
  1. **`stat`（定常合成世界、S57 同一族）**: `synth_world.jl:24-33` の `synth_table(u, P=1000, sigma=1.0, L=300, M=2.5)`（`ns = 9200`, ブロック `b = ⌊s/300⌋ ∈ 0..30`）。
     - 生成式（一次事実 `synth_world.jl:27-30`）: $x_{s,k} = M + 2.5\sin(2\pi(s+\theta_u)/P + \phi_k) + \sigma z_{u,k}(\lfloor s/L\rfloor)$、$\phi_1=0, \phi_2=\pi$。毎歩雑音はなく、ブロック雑音 $z_{u,k}(b) \sim \mathcal{N}(0,1)$ はブロック $b$・区画 $k$ ごとに独立。$\phi_2 = \phi_1 + \pi$ のため区画 1・2 は固定 $\theta$ の下で非交換（逆位相）であり、ブロック境界での反転が識別可能である。
  2. **`rev`（逆転合成世界）**: 同じ `synth_table` に対し、種子ごとに決定的に選んだブロック境界 $b_{\mathrm{rev}}(u) \in \{6, 7, \dots, 24\}$（$s_{\mathrm{rev}}(u) = 300 \cdot b_{\mathrm{rev}}(u) \in \{1800, 2100, \dots, 7200\}$、生成則 `6 + floor(Int, 19 * Mulberry(1_000_003 * u + 63)())`）以降（$s \ge s_{\mathrm{rev}}(u)$）で区画 1 と区画 2 の収量列を入れ替える（$g'_1(s)=g_2(s), g'_2(s)=g_1(s)$）。
- **一般化の範囲・明示的限界**:
  - 本実験の結論は「合成世界 2 族（`stat`, `rev`）・観測履歴 $(a_j, Y_j)_{j<t}$ のみを用いる予測」に限る。
  - **厳密上限の射程（r3 明文化）**: 外生行動トラック `exo`（$A_s \perp (\theta, z, b_{\mathrm{rev}})$ が構成上成立）でのみ `BAYES_raw` は数学的厳密上限となる。正本身体トラック `obs` では行動選択事象の尤度を省略しているため、`obs` の $\mathrm{CI}_{\mathrm{hi}} < \delta$ は「選択尤度非モデル化の逐次 `BAYES_raw` に対する実測利得 `< δ`」にとどまり、選択過程の隠れ情報を利用する予測器までは排除しない。
  - **停止判定の射程**: 本仕様の STOP は **「`(a, Y)` 履歴のみを入力とする C0（`seq_len = 47` TRM 移植・学習）」** にのみ及ぶ（`exo` 3 軸および `obs` 3 軸の判定を分けて報告し、STOP は **`exo`・`obs` 両トラックの全軸**で 95% CI 上限 `< δ` のときのみ発火させる）。受容器列 `r1..r8, rb` を入力に足す予測器、閉ループ（C1）、および S52 実電波換算後の世界は別評価とする。

---

## 2. 比較する予測器（4 種、訓練は世界族ごとに分離）

`RATE` と `TAB4` は **各世界族（`stat` / `rev`）の `train` 12 種子のみで別個に推定**し、同族の `eval` 24 種子で採点する（族を跨いだプールはしない）。

1. **`RATE`（行為ごとの定数割合）**: 同族 `train` 12 種子から行為 $a \in \{1,2\}$ ごとの応答率 $\hat{r}_a$ を Laplace 平滑 $(n_{1,a}+1)/(n_a+2)$ で推定し `[1/200, 199/200]` にクリップ。
2. **`B1`（単一痕跡・U2 `(ア)` 対照）**: 既存 `P_DECAY = 8` で $m_a \leftarrow m_a + (Y - m_a)/8$（初期 $m_1=m_2=0.5$）、予測は `[1/200, 199/200]` クリップ（主判定）。補助として非クリップ `B1_raw`（ガード `ε = 1e-12`）も記録する。
3. **`TAB4`（`W=4` 経験表）**: 直近 $W=4$ 暦歩（歩 $t-4 \dots t-1$、無行為歩を含む）の離散履歴列（各歩 5 値：`無行為または t<T0 境界=0`, `(a=1,Y=0)=1`, `(a=1,Y=1)=2`, `(a=2,Y=0)=3`, `(a=2,Y=1)=4`）＋現行為 $a \in \{1,2\}$ をキーとし（総数 1250）、同族 `train` 12 種子上の経験割合に事前凍結平滑 $\alpha=1.0$（$(n_1 + \alpha \hat{r}_a)/(n + \alpha)$）を当て `[1/200, 199/200]` にクリップ。
4. **`BAYES`（観測履歴 $(a_j, Y_j)_{j<t}$ 上の厳密逐次ベイズフィルタ）**:
   - **入力と非無視性（selection ignorability）の明示**: `BAYES` が受け取るのは世界時刻 $s$（既知時計）・現評価行為 $a_t$・過去観測 $(a_j, Y_j)_{j<t}$ のみ（未来の $Y_t$ や真の $(\theta_u, z_{u,k}, b_{\mathrm{rev}}(u))$ は一切渡さない）。回路の受容器・体状態に依存する選択／無行為事象（どの歩で `length(cs)>=2` になるか等）の周辺尤度はモデル化しないため、本予測器は「選択事象・受容器からの隠れ情報を除いた $(a_j, Y_j)_{j<t}$ 上の厳密逐次ベイズフィルタ」である。
   - **閉形式更新則（二重計上なし）**:
     - `synth_world.jl:30` により有限実数 $x$ に対し `clamp(round(x), 0.0, 5.0) > 0 ⇔ x > 0.5`（ties-to-even 境界 $x=0.5$ を含め厳密同値）。
     - 各仮説 $(\theta, r)$（`stat` は $r \equiv 0$、`rev` は $r \in \{0,1\}$）に対し、ブロック $b$ の入口重み $w_{\mathrm{entry}}(\theta, r)$ と、ブロック $b$ 内の区画 $k \in \{1,2\}$ ごとの切断区間 $(\ell_{b,k}(\theta,r), u_{b,k}(\theta,r)]$ を保持する（ブロック開始時 $(-\infty, +\infty)$）。
     - 歩 $s$ での予測直前の事後重みは $w_s(\theta, r) \propto w_{\mathrm{entry}}(\theta, r) \cdot \prod_{k=1}^2 (\Phi(u_{b,k}(\theta,r)) - \Phi(\ell_{b,k}(\theta,r)))$ とし、予測確率は $P(Y_s=1 \mid \mathcal{H}_{s-1}) = \sum_{\theta,r} w_s(\theta,r) P(Y_s=1 \mid \ell_{b,a_s}, u_{b,a_s}, \theta, r)$（ブロック内の現在閾値 $c_{a_s}(s,\theta,r) = (0.5 - M - 2.5\sin(2\pi(s+\theta)/P + \phi_{a_s \oplus r}))/\sigma$）。
     - 観測 $(a_s, Y_s)$ の後、当該区画の区間を $Y_s=1 \Rightarrow \ell \leftarrow \max(\ell, c)$、$Y_s=0 \Rightarrow u \leftarrow \min(u, c)$ で更新する。
     - ブロック境界 $s \bmod 300 = 0$（ブロック $b-1 \to b$）で、ブロック $b-1$ 終了時の $w_s$ を**1 回だけ** $w_{\mathrm{entry}}$ に確定し（二重計上禁止）、`rev` 族では $b \in \{6..24\}$ において未反転 $r=0$ から反転 $r=1$ へハザード $h_b = 1/(25-b)$（特に $b=24$ で強制遷移 $h_{24}=1$）で質量を移したのち、全区間を $(-\infty, +\infty)$ に初期化する。数値安定に log-sum-exp を用いる。
   - **クリップ方針（r1 高指摘反映）**: `[1/200, 199/200]` クリップは $-\log(199/200) \approx 0.0050\ \mathrm{nat} > \delta_{\mathrm{all}}$ の下限床を作るため、**主判定には `BAYES_raw`（数値ガード $\varepsilon = 10^{-12}$ のみ）** を用い、補助として `BAYES_clip`（`[1/200, 199/200]`）およびクリップ外確率の割合 `frac_outside_clip` を併記する。

---

## 3. 評価指標・統計手順・停止基準（すべて事前凍結）

- **損失関数**: 二値対数損失 $\ell(p, Y) = -(Y \log p + (1-Y) \log(1-p))$（自然対数、単位 nat、小さいほど良い）。主比較は $\Delta_u = L_u(\mathrm{B1}) - L_u(\mathrm{BAYES\_raw})$（正なら `BAYES_raw` が優れる）。
- **種子ごとのスコアと除外基準（軸ごと凍結）**:
  - 各評価種子 $u$・各軸について、行為 1 平均損失と行為 2 平均損失を等重み平均する。
  - **全歩軸（`all`）**: 行為ごとの観測数 $< 30$ の種子を除外。
  - **窓軸（`win`・`SHUF`、`rev` 族のみ、$k = 200$ 歩）**: 行為ごとの観測数 $< 15$ の種子を除外。`rev` の `win`・`SHUF`・`all` の対比較には、`rev` 3 指標すべてを満たす**共通の適格種子集合**を使う。残存種子数 $< 16$ の軸は検出力不足（未判定）とする。
- **3 軸定義と最小実用利得 $\delta$（事前凍結）**:
  1. **`stat all`**（`stat` 族 $s \in 0..9199$）: $\delta_{\mathrm{all}} = 0.002\ \mathrm{nat}$。
  2. **`rev all`**（`rev` 族 $s \in 0..9199$）: $\delta_{\mathrm{all}} = 0.002\ \mathrm{nat}$。
  3. **`rev win_spec`**（`rev` 族の逆転特異窓利得 $\Delta_{\mathrm{win,spec},u} = \Delta_{\mathrm{win,true},u} - \Delta_{\mathrm{win,shuf},u}$、$k=200$ 歩）: $\delta_{\mathrm{win}} = 0.010\ \mathrm{nat}$。
     - ※**理論上の注記**: 真の逆転時刻 $s_{\mathrm{rev}}(u)$ で条件づけた `win` 採点では、無条件の逐次フィルタ `BAYES_raw` が条件付き採点の数学的理論上限とは限らない（`codex P6`）。よって `rev win_spec` の $\mathrm{CI}_{\mathrm{hi}} < \delta_{\mathrm{win}}$ は「無条件逐次 `BAYES_raw` が `B1` に対し逆転特異窓で得る実測利得が $\delta_{\mathrm{win}}$ 未満」を意味する（一般の条件付き最適器の否定ではない）。
- **決定的 `SHUF` 対照窓（ブロック境界リセットの統制）**:
  - 各 `rev` 適格種子 $u$ に対し、ブロック境界 $b_{\mathrm{ctrl}}(u) = 6 + ((b_{\mathrm{rev}}(u) - 6 + 9) \bmod 19) \in \{6..24\}$（$s_{\mathrm{ctrl}}(u) = 300 \cdot b_{\mathrm{ctrl}}(u)$）を偽の逆転時刻とする。$x = b_{\mathrm{rev}}(u) - 6 \in \{0..18\}$ について $x \le 9 \Rightarrow |b_{\mathrm{ctrl}} - b_{\mathrm{rev}}| = 9$、$x \ge 10 \Rightarrow |b_{\mathrm{ctrl}} - b_{\mathrm{rev}}| = 10$ なので、全種子で必ず 9〜10 ブロック（2700〜3000 歩）離隔し非一致失敗がない。
  - 通常のブロックリセット効果 $\Delta_{\mathrm{win,shuf}} - \Delta_{\mathrm{all}}$ は診断量として報告し、進行判定の窓軸はブロックリセットを差し引いた特異利得 $\Delta_{\mathrm{win,spec}}$ に対して行う。
  - **監査器妥当性の負対照（`STAT_PSEUDO`）**: `stat` 族（反転なし）の同一評価種子集合 `1022..1045` に対し、`rev` と同じ決定的時刻 $s_{\mathrm{rev}}(u)$ と $s_{\mathrm{ctrl}}(u)$ で計算した偽の特異差 $\Delta_{\mathrm{stat,spec},u} = \Delta_{\mathrm{stat,rev-t},u} - \Delta_{\mathrm{stat,ctrl-t},u}$ を評価する。反転が存在しない `stat` 上で 95% CI の下限 $\mathrm{CI}_{\mathrm{lo}}(\Delta_{\mathrm{stat,spec}}) \ge \delta_{\mathrm{win}}$ となった場合、窓集計器不良として `win` 判定を無効とする。
- **不確実性・多重性（種子単位ペアード Bootstrap `B = 5000`, `Mulberry(630001)`）**:
  - `exo`（外生行動・厳密上限）・`obs`（正本 `L2 UNI` 軌道）の 2 トラックそれぞれで 3 軸（`stat all`, `rev all`, `rev win_spec`、計 6 軸）を評価し、種子単位の復元抽出（モデル対・窓対を保持）で **95% CI** および **Bonferroni 補正 99.17% CI**（$\alpha/6 = 0.05/6$、両側 0.417% / 99.583% 点）を算出する。補助として両側 5% 符号検定も全対で報告する。
- **TOST 型停止・進行基準（事前凍結）**:
  - **STOP（`(a,Y)` 入力限定 C0 停止）**: `exo`・`obs` 両トラックの全 6 軸**すべて**で **95% CI 上限 `< δ`**（交差結合 TOST 検定のため多重補正不要。なお `exo` 3 軸での厳密上限 STOP と `obs` 3 軸での基準フィルタ STOP の個別結果も必ず併記する）。
  - **PROCEED（C0 進行）**: 全 6 軸の**いずれか**で **Bonferroni 99.17% CI 下限 `> δ`** かつ両側符号検定 $p < 0.05/6$（勝ち過半）かつ当該トラックの `STAT_PSEUDO` 負対照を通過。
  - **UNDECIDED（未判定）**: 上記以外（検出力不足等）。誤停止せずユーザーへ報告する。

---

## 4. 関門（全合格必須）

- **G0（凍結コード不変）**: S57 6 ファイルの SHA-256 が `freeze-draw-conf-code.txt` と一致。
- **G1（S57 再現性）**: 既存種子 `686` の `L2 UNI stat` が S57 記録（4983 引き）と一致。
- **G2（全更新歩単一行為・例整合・反転確認）**: `stat`・`rev` 全種子の**全更新歩**（`t >= T0`）で `length(acts) <= 1` であること（`TAB4` 5 値符号化の前提）。全評価例で `acts == [a]`・`Y == (y[a] > 0)`、1 歩シフト負対照で不一致。`rev` 族で $s < s_{\mathrm{rev}}$ は `stat` と一致し $s \ge s_{\mathrm{rev}}$ は区画 1・2 が厳密反転。
- **G3（未来漏れゼロ）**: `dev` 種子（`1006..1009`）の各 25 例（計 100 例）で $Y_t$ を反転しても `RATE`・`B1`・`TAB4`・`BAYES_raw`・`BAYES_clip` の歩 $t$ 予測 $p_t$ がビット一致し、`B1`・`BAYES` の次歩以降が変化すること。意図的未来漏れ負対照 `LEAK` では $p_t$ が変化すること。
- **G4（実 `synth_world.jl` 経路でのベイズ厳密性検証）**: 縮小版（$P=4, L=4$、実 `synth_table` 関数を経由して生成）で、総当たり数値積分（ガウス・エルミートまたは高密度グリッド積分）と `BAYES_raw` 閉形式の予測確率が **$10^{-5}$ 以内**で一致すること。検証範囲は必ず次の 3 局面をすべて含む：(i) ブロック内部分観測途中、(ii) 反転開始境界 $b=6$（混合ハザード $h_6 = 1/19$ を跨ぐ遷移）、(iii) 最終強制反転境界 $b=24$（$h_{24}=1$）。かつ全歩で事後重み和が $1 \pm 10^{-12}$。
- **G5（種子素集合）**: `dev`・`train`・`eval` が互いに素かつ既存 `1..1005`・`52xxx` と非交差。
- **G6（決定性再実行）**: 2 プロセス（`-t 8` と `-t 1`）で結果 TSV と記録の SHA-256 が完全一致。
- **G7（予測凍結一致）**: `experiments/freeze-headroom-audit.txt` の SHA-256 と実行時ファイルが一致。
- **G8（`core/`・BP 非変更）**: `sh core/check/run.sh` PASS、`~/bridge-protocol` 差分 0。

---

## 5. 予測と反証条件（S-R APPROVE 後に `experiments/headroom_audit/predictions.toml`・`experiments/freeze-headroom-audit.txt` へ凍結）

- **P-S63-1（関門）**: G0〜G8 がすべて合格する。
- **P-S63-2（`B1 > RATE`）**: `stat all`・`rev all` の双方で `B1` が `RATE` に優越（両側符号検定 $p < 0.05$、勝ち過半）。
- **P-S63-3（`BAYES_raw ≥ B1`）**: `stat all`・`rev all` の双方で $\bar{\Delta} = \overline{L(\mathrm{B1}) - L(\mathrm{BAYES\_raw})} \ge 0$。
- **P-S63-4（主検証：余地見込み）**: `stat all` の余地は小さく（$\bar{\Delta}_{\mathrm{all}} \le 0.01\ \mathrm{nat}$）、`rev win_spec` では `BAYES_raw` が反転を検知し `B1` に対し正の特異利得を示す見込み（外れた場合はそのまま正直に報告し、STOP / PROCEED / UNDECIDED を機械判定する）。
- **P-S63-5（監査器負対照）**: `STAT_PSEUDO` の 95% CI 下限は $\delta_{\mathrm{win}}$ 未満に収まり、監査器の偽陽性がない。

## 6. 影響範囲・非目標

- **新規作成のみ**: `experiments/headroom_audit/` 配下（`audit.jl`, `predictions.toml`, `README.md`）および `experiments/freeze-headroom-audit.txt`。
- **非目標**: TRM の `seq_len = 47` 移植、閉ループ（C1）、受容器列 `r1..r8, rb` の入力追加、S52 電波換算（別トラックで並行）。`phenomenal_claim` には一切触れない。
