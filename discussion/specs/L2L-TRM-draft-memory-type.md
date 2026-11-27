# L2L-TRM 仕様 r7（紙上 S-R クローズ版・未凍結）: TRM 二層学習器（L2L §6）および `species_spec.toml` `[memory]` 最小型

- **改訂履歴**:
  - r1（2026-11-27、`neon-lab` 起草）→ r2（`claude` P1〜P9・`codex` P1〜P11）→ r3（`codex` r2 P1〜P8）→ r4（`codex` r3 P1〜P8）→ r5（`codex` r4 P1/P2/P4/P6）→ r6（`codex` r5 P1/P4/P6/P7）。
  - **r6 → r7（2026-11-27、`codex-lab` r6 S-R P1・P4 反映；P2・P6・P7 accept で紙上 S-R クローズ）**:
    - **P1 明確化（枠単位の原子性）**: ポート上限超過時の残高不変保証は **1 枠単位** とし、候補 2 枠・`N=1, B=[2], K_mem=1, port_old=2^40 - 1` では 1 枠目が確定して `B=[1], port=2^40` となり、2 枠目で例外停止する契約と期待終了状態を GM1 へ明記。
    - **P4 修正（コピー 1 回化）**: 擬似コードの `copy(w.B[body_post])` を `tentative_B = w.B[body_post]`（添字抽出 1 回のみで独立配列を得る＝要素コピー $N$ 演算 1 回）へ修正し、§1.1 の演算費積算と厳密一致させた。
- **根拠**:
  - ユーザー承認: J1 / `decisions-log.md` #89、J3（体ライン凍結維持）、U4 `(ア)`、推奨案 A 承認（2026-11-27）。L1〜L5 の 3 者合意は `decisions-log.md` #90 に記録（戻し方つき）。
  - レビュー記録: r1（`.claude-turns/20261127-204448-medium.json`、`.codex-turns/20261127-204447-medium.jsonl`）、r2（`.codex-turns/20261127-210123-medium.jsonl`）、r3（`.codex-turns/20261127-210833-medium.jsonl`）、r4（`.codex-turns/20261127-211644-medium.jsonl`）、r5（`.codex-turns/20261127-213933-medium.jsonl`）、r6（`.codex-turns/20261127-214431-medium.jsonl`）。
- **依っている仮定・非変更境界**:
  - H7（BP10）・H8（BP11）・H10（BP13）・H11（BP14）。`phenomenal_claim = :not_certified` 固定。
  - **非変更境界**: `~/bridge-protocol`・`core/`・`rust/`・`experiments/aue_seam/`・S64/S66/S67/S68/S69 関連ファイルは一切変更しない。
- **§0 問いの分離**:
  - **本仕様が定めること**: (1) `species_spec.toml` `[memory]` の最小スキーマと資源・演算・バイト会計、(2) 統計／技能層（TRM）と分離された固定長断片層 $M$ の最小型、(3) 読み出し・書込み・有界 $O(N_{\max})$ 厳密前払い維持費決済・退去を含む 1 歩の決定的遷移契約、(4) S89 の逆バイアス／非局所波及を再発させない構造制約、および「飾りではない効き」の検証設計。
  - **本仕様に含めないこと（段階分離）**: 退屈→探索／使用依存保護／干渉→分離の 3 自動調整（M2）、新規の調整閾値、驚き順競合上書き、TRACE-1 外側定義の変更（BP14/H11 維持）、DC の $\pi$ の解釈変更（BP 正本側）。

---

## 1. `species_spec.toml` `[memory]` セクションの型（#89 準拠）

既存の `species_spec.toml`（`[ports]`, `[budget]`, `[dormancy]`）と同型に `[memory]` セクションを定義する。全項目を種仕様として事前凍結し、結果を見て変えない。

```toml
# ゼロ容量（C_spec = 0、既存単層 TRM とのビット一致関門用）の例
[memory]
reserved_bytes = 8           # B >= H: 断片層 M 専用予約領域（バイト）
header_bytes = 8             # H == 8: 管理ヘッダの固定サイズ（バイト）
slot_bytes = 16              # s == 16: 1 スロットの固定サイズ（バイト）
upkeep_rate_per_slot = 0.002 # K_mem ∈ [2^-40, 2^40]: 保持中 1 枠・1 歩あたりの維持費単価
max_body_cells = 576         # N_max ∈ [1, 65536]: 生存身体セル数の種仕様上界（例: 24x24 = 576）
max_read_ops_per_step = 0    # C_spec == 0 のとき 0 可。C_spec > 0 では必須下限以上
```

### 1.1 導出容量と会計不変条件（GM1 で設定時検証）
1. **容量算式（#89）**:
   $$C_{\text{spec}} = \left\lfloor \frac{B - H}{s} \right\rfloor \quad (B \ge H,\ s > 0,\ C_{\text{spec}} \le \mathrm{typemax}(\mathrm{UInt32}))$$
   - $B < H$・$s \le 0$・$C_{\text{spec}} > \mathrm{typemax}(\mathrm{UInt32})$・`max_body_cells < 1`・`max_body_cells > 65536` はすべてロード時エラーで拒否する。
   - $C_{\text{spec}} = 0$（$B = H$ および余剰バイト付き $H < B < H + s$ の双方）を正当な最小構成として許容し、GM2 に用いる。
2. **枠外無課金逃避の禁止（#89、`codex` r1 P4）**:
   - 断片に紐づく全実体（文脈キー・行為・結果・順序情報・パディング・余剰バイト）を $B$ バイト固定長バッファ内に厳密計上する。別配列・ハッシュ表・隠れタイムスタンプ等の枠外保持を禁止する。
   - 既存 TRM の 5.8 万重み・97 頭重み・4 歩入力窓・S72 再生輪 512 は断片専用予約領域 $B$ へ換算しない。
3. **維持費および資源の有限有界条件（`[dormancy]` 同型・r3 P1 / r4 P1 解消）**:
   - ロード時検査：`isfinite(K_mem) && 2.0^-40 <= K_mem <= 2.0^40` を必須とする（無料記憶・オーバーフロー域の完全排除。`C_spec == 0` でも単価定義は同域を要求する）。
   - 実行時検査：決済対象セル残高およびポート残高はすべて `isfinite(x) && 0.0 <= x <= 2.0^40` を要求し、逸脱時は即時 `InvalidResourceError` で停止する。
   - **算術契約（オーバーフロー排除＋非正規化残高の扱い）**: `K_mem` および `share = div_down(K_mem, N)`（$\ge 2^{-56}$）は常に正規化数であり、任意の $N \le N_{\max} \le 65536$ セル上の `two_sum`・`two_prod_no_fma` でオーバーフロー（$\le 65536 \cdot 2^{40} = 2^{56} \ll 2^{1024}$）は数学的に発生しない。セル残高・ポート残高は最小正非正規化数 $2^{-1074}$ を含み得るため、実行環境は **IEEE 754 段階的アンダーフロー（gradual underflow、FTZ/DAZ 禁止）** を必須とする。非正規化残高に対しては $m = \min(\mathrm{before}, \mathrm{share}) = \mathrm{before}$ より $\mathrm{after} = \mathrm{sub\_up}(\mathrm{before}, \mathrm{before}) = 0.0$、実減分は厳密に $\mathrm{before}$ であり、`two_sum` のアンダーフロー不在性により全 $[0, 2^{40}]$ で `add_down <= exact <= add_up` が成立する。
4. **演算枠の事前予約条件と厳密線形整数上界（`B_max` 整合、`codex` r1 P5・r2 P4・r3 P4・r4 P4）**:
   - **`C_spec == 0` のとき**: `ctx_key` 計算・読出し・決済・書込みを一切行わず、予約演算費・実演算費ともに厳密に **`0`** とする。
   - **`C_spec > 0` のとき**: 各プリミティブの基本演算数（加減乗除・比較・`min`/`prevfloat`/`nextfloat` 各 1 演算として保守計上：`two_sum` $= 6$、`add_down`/`add_up`/`sub_down`/`sub_up` 各 $8$、`two_prod_no_fma` $= 17$、`div_down` $= 23$）を実行経路どおり積算した確定整数式で上界を固定する：
     - `OPS_CTX_KEY = 16`（6 ビット文脈符号化）
     - `OPS_MEM_READ_WORST(C_spec) = 8 * C_spec + 8`（両行為の鍵・行為比較＋`R-MID`）
     - 1 枠あたりの決済最悪費（配列コピー $N_{\max}$ ＋ 第 1 パス $25 N_{\max}$［`min` 1＋`sub_up` 8＋`sub_down` 8＋`add_down` 8］＋ 第 2 パス $39 N_{\max}$［判定 2＋`sub_up` 8＋`min` 1＋`-` 1＋`sub_down` 8＋補正判定 2＋`prevfloat` 1＋`sub_down` 8＋`add_down` 8］＋ 確定/ポート上限検査/返還/書き戻し/`first_kept` 更新 $N_{\max} + 23$）$= 66 N_{\max} + 23$。
     - 決済全体（有界検査 $4 N_{\max} + 6$ ＋ `div_down` 23 ＋ $C_{\text{spec}}$ 枠ループ ＋ 連続末尾区間の 1 回前詰め/ゼロ化 $8 C_{\text{spec}} + 16$）：
       $$\mathrm{OPS\_MEM\_SETTLE\_WORST}(C_{\text{spec}}, N_{\max}) = 4 N_{\max} + 45 + C_{\text{spec}} \cdot (66 N_{\max} + 31)$$
     - `OPS_MEM_MANDATORY(C_spec, N_max) = OPS_CTX_KEY + OPS_MEM_READ_WORST(C_spec) + OPS_MEM_SETTLE_WORST(C_spec, N_max)`
     - `OPS_MEM_WRITE_WORST(C_spec) = 8 * C_spec + 16`（R1 判定＋`K-UNIQ-CLEAR` 検索・詰め・追加）
   - **ロード時検査（GM1）**: `max_read_ops_per_step >= OPS_MEM_READ_WORST(C_spec)` かつ
     $$B_{\max} - \mathrm{OPS\_MEM\_MANDATORY}(C_{\text{spec}}, N_{\max}) \ge \mathrm{OPS\_TRM\_MIN}$$
     （$\mathrm{OPS\_TRM\_MIN}$ は 0 巡フォールバックを含む TRM が有限予測を 1 回返せる最小演算費＝S66 §2.2 の `OPS_FIXED`）を必須とし、違反はロード時エラーで拒否する。実行時に `length(body_post) > N_max` が発生した場合も即時エラー停止とする。
   - **実行時配分**: 歩開始時に `OPS_MEM_MANDATORY(C_spec, N_max)` を `B_max` から先取り予約し、TRM は残枠内で実行する。任意処理（書込み候補生成）は、TRM 完了後の残枠が `OPS_MEM_WRITE_WORST(C_spec)` 以上ある歩のみ実行し、不足時は書込みをスキップする（必須の前払い決済・退去は必ず予算内で完遂する）。

---

## 2. 固定長メモリ配置（リトルエンディアン固定・Julia / Rust バイナリ一致）

配列自体を **先頭 `1` が最古・末尾 `count` が最新** の FIFO 詰め配列として保持し、別途の時刻カウンタなしで順序を固定長バッファ内へ完全計上する。全整数は **リトルエンディアン** で直列化する。

- **管理ヘッダ（$H = 8$ バイト、オフセット `0..7`）**:
  - `count::UInt32`（4 B）：現在有効なスロット数（$0 \le \text{count} \le C_{\text{spec}}$）
  - `pad_h::UInt32`（4 B）：常に `0` 固定
- **スロット配列（各 $s = 16$ バイト、添字 `1..C_spec`、オフセット `8 .. 8 + 16*C_spec - 1`）**:
  - `ctx_key::UInt64`（8 B）：離散文脈キー（§2.1）
  - `action::UInt8`（1 B）：行為 $a \in \{1, 2\}$
  - `outcome::UInt8`（1 B）：観測結果 $y \in \{0, 1\}$
  - `pad_s::NTuple{6, UInt8}`（6 B）：常に `0` 固定
- **空スロット・余剰バイト規約（`codex` r1 P4・r2 P5）**:
  - 添字 `count+1 .. C_spec` の全スロット、および予約末尾の余剰バイト `B - (H + C_spec * s)` バイト（$C_{\text{spec}} = 0$ で $B > H$ の場合を含む）は、初期化時・毎歩更新後に必ず全バイト `0x00` とし、`state_digest` の完全決定性を保証する。

### 2.1 離散文脈キー `ctx_key` の既定定義（L1 合意案 `(a)`）
- 初回既定は **S72/S86 互換の 6 ビット離散文脈**（$s > 0$ の 6 ビット値 `0..63`、および初期歩 $s = 0$ 用の `64`、全 65 値を `UInt64` へゼロ拡張格納）とする。
- **厳密条件**:
  - 6 ビットの各ビットの出所（`R1IDX[1..6]`）・観測時点（前歩 $s-1$ の受容体値）・ビット位置（bit 0..5）および初期歩 $s = 0 \mapsto 64$ を実験仕様で完全固定し、全 65 文脈を網羅照合可能にする。
  - 当歩の結果 $Y_s$ を観測する**前の入力のみ**から算出し、**行為 $a$ は含めない**（行為は別フィールド `action` で照合）。
- **反証・切替条件**: 保持中スロットの再照会が 0 件なら断片の効きは判定不能。事前に再照会率の記述確認を行い、不足する場合は候補 `(c)`（直近 1 歩入力トークン列パック）を次段で検討する。

---

## 3. 1 歩の厳密な遷移契約（因果順・有界 $O(N_{\max})$ 前払い会計・FMA 禁止 IEEE 算術）

各歩 $s$ の実行順序を以下に固定する（未来漏れゼロ）。予測・合成・比例写像は **IEEE 754 `binary32`・FMA 禁止・最近接偶数丸め**、身体資源会計および有向丸めプリミティブは **IEEE 754 `binary64`・FMA 禁止・最近接偶数丸め** とする。

### 3.1 推論・断片読み出し・行為選択（当歩の結果 $Y_s$ 観測前）
- ※ここで $M$ に保持されている全 `count` 枠は、**前歩 $s-1$ の末尾（§3.3）で歩 $s$ 分の維持費を前払い済み**である（出生時 `count = 0`）。無償読み出しは構造上 0 回となる。
1. **技能層（TRM）推論**:
   - 既存単層 TRM が演算残枠内（`C_spec == 0` なら全枠 `B_max`、`C_spec > 0` なら `B_max - OPS_MEM_MANDATORY(C_spec, N_max)`）で技能予測 $p_1^{\text{TRM}}, p_2^{\text{TRM}} \in [0.0\mathrm{f}0, 1.0\mathrm{f}0]$（および記録専用 $e_1, e_2$）を出力する。
2. **断片層 $M$ の鍵局所読み出し（非局所波及ゼロ）**:
   - `C_spec == 0` のときは一切の処理を飛ばし $p_a = p_a^{\text{TRM}}$（演算費 `0`）。
   - `C_spec > 0` のとき、`k = ctx_key(obs_s)` を計算し、各候補行為 $a \in \{1, 2\}$ について `i = 1..count` を昇順走査して一致集合 $M(k, a)$ を得る（`K-UNIQ-CLEAR` の下では $|M(k, a)| \in \{0, 1\}$）。
   - **合成規則 `R-MID`（L2 合意案、新規定数ゼロ）**:
     - $M(k, a) = \emptyset$ のとき: $p_a = p_a^{\text{TRM}}$（演算を挟まずビット完全一致）
     - $M(k, a) \neq \emptyset$ のとき（単一枠 $y_m \in \{0, 1\}$）:
       $$p_a = 0.5\mathrm{f}0 \cdot \left(p_a^{\text{TRM}} + \mathrm{Float32}(y_m)\right)$$
   - **境界仕様（`claude` r1 P4・P5、`codex` r1 P7・r2 P6）**:
     - $p_a^{\text{TRM}} = 0.5\mathrm{f}0$ で空なら R1 は書かない；保持値 $y_m = 1$ なら $p_a = 0.75\mathrm{f}0$（$y_m = 0$ なら $0.25\mathrm{f}0$）。
     - $p_a^{\text{TRM}} \in \{0.0\mathrm{f}0, 1.0\mathrm{f}0\}$ と逆向き 1 枠が一致すると $p_a = 0.5\mathrm{f}0$ となり当歩の R1 は発火しない。
     - `binary32` 丸め境界例：$p_a^{\text{TRM}} = \mathrm{Float32}(2^{-25})$ と $y_m = 1$ の加算は最近接偶数丸めで `1.0f0` となり $p_a = 0.5\mathrm{f}0$ となる（GM2 単体試験に収録）。
3. **行為抽選（U4 `(ア)` 凍結比例写像・演算順固定）**:
   - 厳密演算順（FMA 禁止 `Float32`）：
     1. `denom = p1 + p2`
     2. `denom == 0.0f0` なら `pi1 = 0.5f0; pi2 = 0.5f0`
     3. そうでなければ `pi1 = 0.125f0 + 0.75f0 * (p1 / denom)`、`pi2 = 0.125f0 + 0.75f0 * (p2 / denom)`
   - 凍結乱数ビットと `pi1` で行為 $a_s \in \{1, 2\}$ を抽選する。
   - **オフライン互換モード**: 固定入力列でも、与えられた $a_s$ で環境を進めつつ、同一乱数による仮想抽選結果 $\hat{a}_s$ および $(\pi_1, \pi_2)$ を記録して GM2 の抽選一致を照合する（`codex` r1 P11）。

### 3.2 環境・身体 1 歩および死亡吸収
- `core`（`OneLife`）を 1 歩進め、行為 $a_s$ の結果 $Y_s \in \{0, 1\}$ と歩終了後の生存身体 `body_post` を得る。
- **死亡吸収（S67 §2.2 同一）**: `isempty(body_post)` のときは、§3.3（書込み候補生成・次歩持ち越し前払い決済）を一切行わず、断片層 $M$ を最終状態で凍結して歩を終える。

### 3.3 書込み候補生成（R1＋`K-UNIQ-CLEAR`）と有界 $O(N_{\max})$ 前払い逐次決済（生存歩・$C_{\text{spec}} > 0$ のみ）
※既存の `K_head`（C2 の場合）決済の直後に実行する（C1 凍結頭では `K_head = 0`）。

1. **持ち越し候補リスト $M_{\text{cand}}$ の生成（演算残枠が `OPS_MEM_WRITE_WORST(C_spec)` 以上のときのみ更新、不足時は $M_{\text{cand}} = M$ のままステップ 2 へ）**:
   - 更新前の合成予測 $p_{a_s}$ と結果 $Y_s$ で R1（閾値ゼロ）を判定する：
     $$\mathrm{miss} \iff (Y_s = 1 \land p_{a_s} < 0.5\mathrm{f}0) \lor (Y_s = 0 \land p_{a_s} > 0.5\mathrm{f}0)$$
   - `miss == false` なら $M_{\text{cand}} = M$。
   - `miss == true` のとき、**`K-UNIQ-CLEAR`（L3 合意案、`codex` r2 P7 反映）**を適用する：
     - $M$ に同一鍵 `(k, a_s)` のスロットが既にある場合：
       - **観測前の技能予測 $p_{a_s}^{\text{TRM}}$** と新結果 $Y_s$ が一致している（$(Y_s = 1 \land p_{a_s}^{\text{TRM}} > 0.5\mathrm{f}0) \lor (Y_s = 0 \land p_{a_s}^{\text{TRM}} < 0.5\mathrm{f}0)$）なら、既存スロットを削除して前詰めするのみ（新規追加しない＝整合回復クリア）。
       - そうでなければ既存スロットを削除して前詰めし、末尾へ `(k, a_s, Y_s)` を追加する。
     - $M$ に同一鍵 `(k, a_s)` がない場合：
       - `length(M) < C_spec` なら退去せず、そのまま末尾へ `(k, a_s, Y_s)` を追加する。
       - `length(M) == C_spec` なら先頭（最古）1 件を D1 退去して前詰めした上で、末尾へ `(k, a_s, Y_s)` を追加する。
   - *注記（C2 での冗長枠、`claude` r1 P5）*: C2 で TRM 重みが後から断片と同向きへ学習した場合の冗長枠自動消去は初回最小型には入れず、C2 実測で冗長占有が確認された場合のみ追補検討する（反証条件：48 生／C2 で冗長枠占有が 0 件なら不要）。

2. **次歩 $s+1$ 持ち越し分の有界 $O(N_{\max})$ 前払い逐次決済（L4 合意案、`codex` r3 P1・P2・P3・P4・P6 反映）**:
   - **固定 $O(1)$ 有向丸めプリミティブ（FMA 禁止 `Float64`、動的配列ゼロ、`while` ループゼロ、有界域 $[0, 2^{40}]$ 上でオーバーフロー・非正規化なし）**:
     ```text
     two_sum(a, b):                  # 厳密に a + b == x + y（有界域でオーバーフローなし）
         x = a + b
         bv = x - a; av = x - bv
         y = (a - av) + (b - bv)
         return (x, y)

     add_down(a, b):                 # 数学的に厳密に add_down(a, b) <= a + b
         (x, y) = two_sum(a, b)
         return y < 0.0 ? prevfloat(x) : x

     add_up(a, b):                   # 数学的に厳密に add_up(a, b) >= a + b
         (x, y) = two_sum(a, b)
         return y > 0.0 ? nextfloat(x) : x

     sub_down(a, b) = add_down(a, -b)  # 厳密に sub_down(a, b) <= a - b
     sub_up(a, b)   = add_up(a, -b)    # 厳密に sub_up(a, b)   >= a - b

     # K_mem / N の下向き丸め商（厳密に N * share <= K_mem、P2 解消）
     # N ∈ 1..65536 は 17 bit 以下のため Veltkamp/Dekker 分割なしで exact 乗算検算可能:
     # (K_mem - share * N) の下向き丸め、より一般に FMA 禁止 Dekker two_prod(share, Float64(N))
     two_prod_no_fma(a, b):          # FMA 禁止 Dekker 分割（c = 2^27 + 1 = 134217729.0）
         p = a * b
         ca = 134217729.0 * a; ah = ca - (ca - a); al = a - ah
         cb = 134217729.0 * b; bh = cb - (cb - b); bl = b - bh
         err = ((ah * bh - p) + ah * bl + al * bh) + al * bl
         return (p, err)             # 厳密に a * b == p + err（|a|,|b| <= 2^40 でオーバーフローなし）

     div_down(K_mem, N::Int):        # 厳密に Float64(N) * share <= K_mem
         share = K_mem / Float64(N)
         (p, err) = two_prod_no_fma(share, Float64(N))
         # p + err > K_mem なら 1 ulp 下げる（RN 商の誤差は <= 0.5 ulp ゆえ高々 1 回で厳密成立）
         if p > K_mem || (p == K_mem && err > 0.0):
             share = prevfloat(share)
         return share
     ```
   - **逐次決済ループ（$M_{\text{cand}}$ が空なら引落 `0.0` で終了；非空なら新しい順に 1 枠ずつ仮計算・確定）**:
     ```text
     # 実行時有界チェック（GM1）
     N = length(body_post)
     (1 <= N <= max_body_cells) || throw(InvalidResourceError)
     all(i -> isfinite(w.B[i]) && 0.0 <= w.B[i] <= 2.0^40, body_post) || throw(InvalidResourceError)
     (isfinite(port_balance(w.port)) && 0.0 <= port_balance(w.port) <= 2.0^40) || throw(InvalidResourceError)

     first_kept = length(M_cand) + 1  # 購入済み連続末尾区間の開始添字（O(C_spec) 前詰め用、r5 P4 解消）
     share = div_down(K_mem, N)       # 厳密に N * share <= K_mem
     for j = length(M_cand) downto 1:
         tentative_B = w.B[body_post]  # 添字抽出 1 回のみで独立配列を得る（コピー 1 回＝N 演算、r6 P4 解消）
         paid_lo = 0.0                # 不変条件: paid_lo <= exact_sum(before_i - after_i)
         # 第 1 パス: セル均等仮引落（各セル実減分 <= share かつ総和 E_1 <= K_mem を厳密保証、r4 P2 解消）
         for idx in 1..N:
             before = tentative_B[idx]
             m = min(before, share)
             after = sub_up(before, m)          # 厳密に after >= before - m ⇒ before - after <= share
             dec_lo = sub_down(before, after)
             tentative_B[idx] = after
             paid_lo = add_down(paid_lo, dec_lo)
         # 第 2 パス: paid_lo < K_mem のとき添字順で補充（P3 厳密補正つき）
         for idx in 1..N:
             paid_lo >= K_mem && break
             before = tentative_B[idx]
             before <= 0.0 && continue
             rem_up = sub_up(K_mem, paid_lo)        # 厳密に paid_lo + rem_up >= K_mem
             m = min(before, rem_up)
             after = before - m
             dec_lo = sub_down(before, after)
             if dec_lo < m && after > 0.0:          # RN 丸め不足（P3 反例含む）を 1 ulp 補正
                 after = prevfloat(after)           # 数学的に厳密に before - after >= m
                 dec_lo = sub_down(before, after)
             tentative_B[idx] = after
             paid_lo = add_down(paid_lo, dec_lo)
         # 誤差許容ゼロの厳密購入判定（paid_lo >= K_mem ⇒ exact_E >= paid_lo >= K_mem）
         if paid_lo >= K_mem:
             # ポート受け側丸め切り上げによる物質創造を遮断（P6 解消）かつ上限超過を確定前に検査（r5 P1 解消）
             port_old = port_balance(w.port)
             target_port = add_down(port_old, paid_lo)          # <= port_old + paid_lo
             (isfinite(target_port) && target_port <= 2.0^40) || throw(InvalidResourceError)
             paid_arg = sub_down(target_port, port_old)         # <= target_port - port_old <= paid_lo
             w.B[body_post] .= tentative_B
             port_give!(w.port, paid_arg)                       # port_after - port_before <= paid_lo <= exact_E
             first_kept = j                                     # O(1) 記録のみ（連続末尾区間）
         else:
             break   # 以降のより古い枠は購入せず打ち切り（端数・部分引落ゼロ）
     # ループ後に 1 回だけ連続末尾区間 M_cand[first_kept..end] を先頭へ前詰めし、空スロット・余剰バイトを 0x00 ゼロクリア
     ```
   - **数学的不変条件**:
     - **無償購入ゼロ（P1 解消）**: 帰納的に `paid_lo <= exact_E` が常に成立するため、`paid_lo >= K_mem` は `exact_E >= K_mem` を数学的に含意する。反例 `K_mem = 1.0, w.B = [0.5, prevfloat(0.5)]` では `paid_lo = prevfloat(1.0) < 1.0` となり購入失敗・全キャンセルされる（境界ギリギリで下向き丸めの累積により不足判定される場合は安全側の保守棄却であり、無料保持・物質創造は起きない）。
     - **第 1 パス過剰引落ゼロ（r3 P2・r4 P2 解消）**: `div_down` により $N \cdot \mathrm{share} \le K_{\text{mem}}$、かつ第 1 パスの `after = sub_up(before, m)` により各セル実減分 $\le \mathrm{share}$ ゆえ、第 1 パス総実減分 $E_1 \le K_{\text{mem}}$ が厳密成立する（反例 `N=4, before=3*2^12, K_mem=2.5*2^-39` では第 1 パス実減分 0、第 2 パス 1 セルで $E = 3\cdot 2^{-39} \le K_{\text{mem}} + u$）。
     - **第 2 パス丸め誤拒否ゼロ（r3 P3 解消）**: `dec_lo < m && after > 0.0` で `after = prevfloat(after)` とすることで `dec_lo >= m` となり、`before >= rem_up` なセルが残っていれば `add_down(paid_lo, dec_lo) >= add_down(paid_lo, rem_up) >= K_mem` が 1 回で必ず成立する（反例 `u=2^-53, K_mem=2.5u, B=[0,1]` で購入成功）。
     - **物質創造ゼロ（r3 P6・r4 P6 解消）**: ポート更新前の残高 `port_old` に対して `paid_arg = sub_down(add_down(port_old, paid_lo), port_old)` を渡すことで、既存 `port_give!` の通常 `Float64` 加算後も `exact_diff(port_after, port_before) <= paid_lo <= exact_E` が厳密保証される（反例 `port_old = 1.0, paid_lo = 3*2^-54` では `target_port = 1.0, paid_arg = 0.0`・実増分 `0.0 <= 3*2^-54`；`port_old = 1.0, paid_lo = 5*2^-54` では `target_port = 1.0 + 2^-52, paid_arg = 2^-52`・実増分 `2^-52 <= 5*2^-54`）。
     - **二重請求ゼロ・課金額境界（r3 P2・r4 P2 解消）**: 1 保持期間あたりの課金回数は厳密 1 回。確定 1 枠の厳密実減分和 $E$ は常に $K_{\text{mem}} \le E \le K_{\text{mem}} + \mathrm{ulp}(\max B_i) + (2N + 1)\cdot\mathrm{ulp}(K_{\text{mem}})$（1 セルかつ `before - K_mem` が厳密表現可能なら $E = K_{\text{mem}}$）。
     - 決済後、`kept_slots` を $M$ へ格納し、`count = length(kept_slots)`、空スロットおよび余剰バイトを `0x00` ゼロクリアする。

---

## 4. 必須関門（GM1〜GM5、反例 1 件で差し戻し）

1. **GM1（予算・有界域・固定長・ロード時拒否・枠外逃避ゼロ）**:
   - $B < H$・$s \le 0$・$C_{\text{spec}} > \mathrm{typemax}(\mathrm{UInt32})$・$K_{\text{mem}} \notin [2^{-40}, 2^{40}]$・非有限 $K_{\text{mem}}$・`max_body_cells ∉ [1, 65536]`・`C_spec > 0` での `max_read_ops_per_step < OPS_MEM_READ_WORST(C_spec)` および `B_max - OPS_MEM_MANDATORY(C_spec, N_max) < OPS_TRM_MIN` をすべてロード時エラーで拒否すること。実行時 `length(body_post) > N_max` や残高・ポートの `[0, 2^40]` 逸脱も即時エラー。
   - **r5 P1 / r6 P1 ポート上限超過の枠単位原子性テスト**:
     - 単枠例: `N = 1, w.B = [1.0], K_mem = 1.0, port_old = 2.0^40`（`target_port = 2.0^40 + 1.0 > 2.0^40`）で、当該枠の `w.B` と `w.port` を変更する前に `InvalidResourceError` で停止すること（停止後も `w.B == [1.0], port == 2.0^40`）。
     - 2 枠原子性例（枠単位契約の固定）: 候補 2 枠、`N = 1, w.B = [2.0], K_mem = 1.0, port_old = 2.0^40 - 1.0` では、1 枠目が確定して `w.B == [1.0], port == 2.0^40` となり、2 枠目で `InvalidResourceError` 停止すること（終了状態 `w.B == [1.0], port == 2.0^40`；ループ後の前詰め前の異常停止のため `M` バッファ自体は更新されず前歩末状態のまま、歩自体が異常終了となる）。
   - 毎歩 `H + C_spec * s <= B`、空スロット・余剰バイト全 `0x00`、リトルエンディアン直列化、`ops_total <= B_max` を照合すること。
2. **GM2（$C_{\text{spec}} = 0$ ビット一致：余剰 0 および余剰あり両例）**:
   - **`B = H = 8`（余剰 0）** および **`B = 9, H = 8, s = 16`（余剰 1 バイトあり、初期化時および全歩で余剰 `0x00` 維持）** の双方において、既存単層 TRM と $(p_1, p_2)$・$(\pi_1, \pi_2)$・乱数抽選行為 $a_s$（オフライン時は同一乱数による仮想抽選 $\hat{a}_s$）・TRM 完了巡数・メモリ演算費（厳密 `0`）・乱数状態・身体資源 $w.B$ が全歩ビット完全一致すること（`codex` r2 P5）。
   - 加えて `R-MID`・$\pi_a$ の `binary32` 境界例（`p_TRM ∈ {0, 2^-25, 0.5, 1}`、`denom == 0`）を単体ビット照合すること。
3. **GM3（未来漏れゼロ）**:
   - 履歴・身体状態・乱数を完全固定し、**学習器に渡る当歩結果 $Y_s$ のみ**を反転したとき、当歩の $(p_1, p_2)$・$(\pi_1, \pi_2)$・$a_s$ がビット完全一致すること（負対照：結果参照バグで不一致を検知）。
4. **GM4（有界 $O(N_{\max})$ 前払い会計・無料記憶遮断・二重請求ゼロ・ポート厳密非創造・死亡吸収）**:
   - (a) **初回書込み無償遮断**: 空 $M$・生存・残高 0 の歩で miss が起きても歩末前払いで購入失敗して `count = 0` となり、次歩 §3.1 で 1 回も読まれないこと。
   - (b) **浮動小数境界の固定テスト（r2/r3 反例の回帰関門）**:
     - **P1 境界**: `K_mem = 1.0, w.B = [0.5, prevfloat(0.5)], port = 0.0` で**購入失敗・両セル残高不変・ポート実増分 `0.0`**。
     - **P1 有界拒否**: `K_mem = floatmax(Float64)` や `K_mem = 2.0^-1074` は GM1 ロード時エラー拒否。
     - **P2/P3 境界**: `K_mem = 2.5 * 2^-40, w.B = [0.0, 2.0^13]`（比 $K_{\text{mem}} / \mathrm{ulp}(B_2) = 2.5$ の有界版 P3 反例）で第 2 パス 1 ulp 補正により購入成功し、`exact_E >= K_mem` かつポート実増分 $\le \mathrm{paid\_lo} \le E$。
     - **r4 P2 境界（第 1 パス上向き丸め）**: `N = 4, w.B = fill(3.0 * 2.0^12, 4), K_mem = 2.5 * 2.0^-39`（$u = \mathrm{ulp}(3\cdot 2^{12}) = 2^{-39}$）で第 1 パス実減分 `0`、第 2 パス 1 セルで $E = 3\cdot 2^{-39} \le K_{\text{mem}} + u$（購入成功・過剰引落なし）。
     - **均等割境界**: `N = 3, w.B = [1.0, 1.0, 1.0], K_mem = 0.002` で第 1 パス `div_down`＋`sub_up` が過剰引落を起こさず、第 2 パス補充で購入成功、$K_{\text{mem}} \le E \le K_{\text{mem}} + \mathrm{ulp}(1.0) + 7\cdot\mathrm{ulp}(0.002)$。
     - **P6 ポート非創造境界（r5 P6 分離）**:
       - *ポート算術単体試験*: `port_old = 1.0, paid_lo = 3 * 2^-54`（`target_port = 1.0, paid_arg = 0.0`, 増分 `0.0 <= 3*2^-54`）および `port_old = 1.0, paid_lo = 5 * 2^-54`（`target_port = 1.0 + 2^-52, paid_arg = 2^-52`, 増分 `2^-52 <= 5*2^-54`）。
       - *決済経由試験（$K_{\text{mem}} \in [2^{-40}, 2^{40}]$ 到達例）*: `port_old = 2.0^14, K_mem = 3 * 2.0^-40, w.B = [1.0]` で購入成功し、ポート更新前後の厳密差 `exact_diff(port_after, port_before) <= paid_lo <= E` であること。
   - (c) **逐次部分不足（端数不奪取）**: 保持候補 2 枠・残高 `1.5 * K_mem`（2 進厳密例 `K_mem = 0.25, B = [0.375]`）のとき、最新 1 枠のみ購入され実引落厳密和 $E = 0.25$（端数 `0.125` は 1 ビットも奪われない）、最古 1 枠は退去、ポート実増分 $= 0.25 \le E$。
   - (d) **二重請求ゼロ（回数・金額の分離検査）**: 1 枠を 1 歩保持して次歩で読んだ後（書込みなし・退去）の課金回数が厳密 1 回（2 歩保持なら 2 回）。2 進厳密 1 セル（例 `K_mem = 0.25, B = [1.0]`）では累計実引落が厳密 `1 * K_mem`（2 歩なら `2 * K_mem`）、一般多セル／高残高では各期間 $K_{\text{mem}} \le E \le K_{\text{mem}} + \mathrm{ulp}(\max B_i) + (2N + 1)\cdot\mathrm{ulp}(K_{\text{mem}})$ かつポート実増分 $\le E$。
   - (e) **死亡吸収**: 死亡歩で引落・退去・書込みすべて 0、最終状態凍結。
5. **GM5（鍵局所・非局所波及ゼロ）**:
   - 同一の TRM 出力 $(p_1^{\text{TRM}}, p_2^{\text{TRM}})$ に対し、照会対象の枠のみが異なる 2 状態（$M$ あり vs $M$ 空）を比較し：
     - **別文脈 `k' != k`**: 全行為の $(p_1, p_2)$ および $(\pi_1, \pi_2)$ がビット完全一致すること。
     - **同一文脈 `k`・別行為 `a' != a`**: **生予測 $p_{a'}$ がビット完全一致すること**（同文脈の $\pi_{a'}$ の変動は U4 比例写像の分母 $p_1+p_2$ 共有の必然的帰結として別記する）。

---

## 5. 「飾りではない効き」の検証設計（3 層分離、`codex` r1 P10・r2 P8・r3 P8 反映）

結果反転は 4 歩窓・可塑頭にも効き、また正容量側の演算予約は `B_max` 打ち切り下の TRM 巡数を変え得る。以下を明確に分離して測る。

1. **層 1：配線必要条件（内部監査・型外、`READ_ON/OFF` 分岐）**:
   - 事前指定した「主保持かつ同一 `(k, a)` 再照会」ステップにおいて、同一履歴・同一資源・同一 TRM 状態（同一巡数）・同一乱数から読み出しだけを切った版（`READ_OFF`：$p_a = p_a^{\text{TRM}}$）と通常版（`READ_ON`）を分岐し、行為分布 $\pi_a$ の差 $|\pi^{\text{ON}}_a - \pi^{\text{OFF}}_a|$ を個別記録する。
   - **反証条件（配線棄却）**: 事前指定した再照会例で生予測 $p_a$ が変わっても行為分布 $\pi_a$ が同じ（または両方同じ）なら、その例での行為分布への読み出し効果は棄却する（該当例 0 件は判定不能）。
2. **層 2：実効性比較（内部監査・型外、事前凍結指標）**:
   - 層 1 と同一の事前指定再照会例集合において、`READ_ON` と `READ_OFF` の実結果 $Y$ に対する Brier 損失（および的中率）の対応差を凍結予測として検証する（結果を見て指標を選ばない）。
3. **層 3：型内双子試験（BP14 / H11 準拠・双模倣不変）**:
   - 入出力の型の中の操作のみで、結果 1 件 $Y_s$ を反転し共通後続入力列を与えた双子との出力差 $D_s$（予測 $p$ および行為分布 $\pi$ の双方）を、$C_{\text{spec}} > 0$ 対 $C_{\text{spec}} = 0$ で閾値なしの符号条件により比較する。
   - **交絡規約（`codex` r2 P8・r3 P8）**: 層 3 の $C_{\text{spec}} > 0$ 対 $C_{\text{spec}} = 0$ 差には、正容量側の演算予約に伴う TRM 巡数変化や 4 歩窓・可塑頭の応答差も含まれ得るため、層 3 は**「二層構成系全体の入出力差」**として報告する。断片読み出し単独への帰属主張は、同じ再照会歩（同一巡数）で分岐した層 1・層 2 の結果を対応づけて併記した範囲に限る。内部状態 $M$ の直接操作は層 3 に一切持ち込まない。

---

## 6. 次段（最小検証の土台・L5 合意案 `(α)`）

- **第 1 段（L5 `(α)`、J3 体ライン凍結に非接触）**: 既見 48 生のうち S87 同一の TRM 4 生（`st2 life 1..4`）＋既存 `TrmL` 上で、本仕様 r7 の `[memory]` 1 歩契約＋比例写像 $\pi_a$（同一乱数での仮想抽選一致を含む）＋模擬残高フィクスチャ（GM1〜GM5・層 1〜3）を検証する小仕様（S90）を起草・凍結する（未使用種子は開封しない）。
- **第 2 段（L5 `(β)`、ユーザー承認待ち）**: 第 1 段の関門・反証条件を通過した後、ユーザー承認を得て `experiments/aue_seam/`（4 継ぎ目床）および実身体統合（C1/C2）へ `[memory]` 契約を拡張する。
