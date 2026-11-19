# memory-transfer-pilot — 未知記号への転移の予備実験（2026-11-18、claude-lab）

根拠: `discussion/notes/memory-transfer-roadmap.md`、`discussion/reviews/memory-transfer-design.md`、`discussion/notes/D-memory-transfer-codex.md`。
既存個体・アプリの db・`~/bridge-protocol` は使っていない（Lean の型検査はそのビルドを読むだけ）。

## 手順（実際に行った順）

1. 予測 `predictions.toml` → `shasum -a 256` を `../freeze-memory-transfer-pilot.txt` に記録（d674f98a…569a、走らせる前）。
2. Lean `formal/MemoryTransfer.lean`: statement（`sorry`）→ `sh formal/check.sh` → 証明 → 再検査（`sorry` なし。公理は propext・Classical.choice・Quot.sound）。
3. Julia `mt_core.jl`・`pilot.jl` → `results.tsv`。関門 `check.jl` → `check.out`。
4. 別プロセスでの再実行 `results-rerun.tsv`（SHA-256 一致 57f64996…65dd）、`shasum -c` の凍結照合 OK、`sh core/check/run.sh` → `core-check.out`（exit 0）。

## 課題

A・B で訓練（AA・BB・AB・BA、二条件で共通）、未知の C・D で四問（CC・DD・CD・DC）。割当て SX は 同→X・異→Y、SY はラベルの反転。
左右に別のポート、各試行は常に二件。s>0→X、s<0→Y、s=0 は同点で不正解。有理数の厳密計算、乱数なし、初期結合 0、一括 LMS（1/16、200 周）。
移植するのは列挙した結合（w, b）だけ。直前の入力・教師信号の控え・更新回数・誤差の跡は新しい個体で初期化し、各問を複製から一回読む。

## 比較機能の設計由来

| モデル | 読み出し | 同異の比較は何から来るか |
|---|---|---|
| ADD | u·f(L)+v·f(R)+b | 比較なし（Lean の命題で四問は上限 3） |
| P（陽性対照） | w·[L==R]+b | 設計。記号 ID の一致を比較器として与える |
| LP | w·(f(L)⊙f(R))+b | 積の演算子は設計。どのチャネルをどの符号で読むかを w・b の結合学習で得る。どの未知対に効くかは特徴符号の共有が決める |

符号 H4 は C⊙D = A⊙B（設計上の共有）、O8 は C⊙D が 1 とも A⊙B とも直交。

## 四問の予測と観測（TRANS = 訓練→移植）

| モデル・符号 | SX 予測 | SX 観測 | SY 予測 | SY 観測 |
|---|---|---|---|---|
| ADD（H4・O8） | 0/4 全同点 | 0/4 全同点 | 0/4 全同点 | 0/4 全同点 |
| P（H4・O8） | 4/4 X,X,Y,Y | 4/4 X,X,Y,Y | 4/4 Y,Y,X,X | 4/4 Y,Y,X,X |
| LP H4 | 4/4 X,X,Y,Y | 4/4 X,X,Y,Y | 4/4 Y,Y,X,X | 4/4 Y,Y,X,X |
| LP O8 | 2/4 X,X,同,同 | 2/4 X,X,同,同（CD・DC の s = 0//1） | 2/4 Y,Y,同,同 | 2/4 Y,Y,同,同 |

対照: INIT・FROZEN は全モデルで全問同点、割当てに依存しない。SELF（移植なし）のスコアは移植後と厳密に一致。
非同点の応答は SX と SY で全部反転。C≠D を特徴で確認（X/Y を使わず）。ADD は訓練対も全部同点（目標が加算の張る空間に直交し、勾配が 0）。
反証条件 F1〜F6 はどれも成立しなかった。外れた予測はない。

負の対照: N1（移植せず教師信号の控えを読む漏れを仕込む）は 18 の検査で落ちた。N2（LP H4 SY の CD を一つ反転）は予測照合とラベル反転の検査で落ちた。

## 解釈の限界

- 確認した事実: 列挙した結合（w, b）だけを新しい個体へ移すと、P と LP_H4 は両割当てで未知の四問に正解し、LP_O8 は同じ対だけ正解した。加算の読み出しでは四問同時の正解はできない（Lean で証明）。
- 推論: LP の転移は特徴符号の共有（H4 で C⊙D = A⊙B）が運んでいる。O8 では異なる対の積が訓練の積と直交するので、学習した結合は CD・DC に何も言わない。
  したがって LP_H4 の合格は「比較機能の獲得」ではなく、設計した積の演算子と符号の上での対応の学習を示すにとどまる。P も同じく設計の比較器を使う。
- 主張しないもの: 比較機能の獲得、未知の記号対一般への転移、局所更新一般の不可能性（LP_O8 の失敗から）、結合と他の状態との協働、`phenomenal_claim`。
- 提案（未実施）: 次の段では積の演算子そのものを設計から外す候補（例: 特徴の比較を学習する二層、または符号を学習する系）を立て、
  反証条件「O8 型の直交符号でも CD・DC が両割当てで正解する」を加える。採用は合意とユーザーの判断。
