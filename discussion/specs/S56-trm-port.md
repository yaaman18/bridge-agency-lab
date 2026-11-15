# S56 公式 TRM（Python）の Julia への移植 第 1 段: 推論の中核をそのまま移し、公式の出力と数値で照合する（r4、2026-11-15、claude-lab。r4 は最初のブロックの中間の量の許容差と、正解の側の凍結の記録だけ〈codex の再レビュー〉。r3 は構成 (e) の直しだけ〈claude-lab の計算の誤りを deepseek-lab が見つけた〉。codex-lab S-R: r1 に challenge 7・clarify 4・accept 1 → 全部採った）

- 出どころ: ユーザー 2026-11-15「公式の Python 版を Julia に移植する」「deepseek v4.1 flash 10-17 にコーディングをやらせて codex にレビューさせる」。設計は `notes/D-MEM.md` §3（予測器の正本）。
- 分担: コード＝deepseek-lab（`discussion/deepseek-turn.sh`、一手ごとに FILE:・GATE:）。仕様・関門・記録＝claude-lab。レビュー＝codex-lab。
- もと: `~/trm_test/TinyRecursiveModels`（公式 SamsungSAILMontreal/TinyRecursiveModels の写し、commit 7de0d20、MIT ライセンス、Samsung Electronics 2025）。**読むだけ。書き換えない。** 対象は `models/recursive_reasoning/trm.py`、`models/layers.py`、`models/common.py`（sha は凍結に記録）。
- この段の範囲: **推論（forward）だけ**。学習、損失、EMA、データの作り方、疎な埋め込みの学習は移さない。個体に入れるための縮小・自前の数学関数・Rust への写し・維持費・受容器とのつなぎは**次の段**（別の仕様）。この段は何の実験もしない。個体のコード（`core/`、`rust/`）に触れない。
- 置き場: `experiments/trm/`（新しいディレクトリ）。`core/` には入れない（個体の規則として採るときに、ユーザーの決定を経て移す）。移植したファイルの頭に、もとのファイル名・commit・MIT の著作権表示を書く。

## 1. 移すもの（公式の名前との対応を保つ）
- `layers.py`: `rms_norm`、`CastedLinear`、`CastedEmbedding`、`RotaryEmbedding`（cos・sin の表）、`rotate_half`、`apply_rotary_pos_emb`、`Attention`（因果なし、scaled dot-product）、`SwiGLU`（中間の幅は公式どおり 256 の倍数に切り上げ）。
- `trm.py`: `…Block`（注意機構の版と `mlp_t` の版）、`…ReasoningModule`（入力の足し込み）、`…_Inner`（埋め込み、`H_cycles`・`L_cycles` の再帰、`lm_head`、`q_head`、`H_init`・`L_init`、`reset_carry`）、ACT の包み（**評価モードだけ**: 止まるのは `halt_max_steps` に達したとき。学習時の探索の乱数は移さない）。
- 型は実数の型の引数にする（照合は Float32）。配列の添字は 1 始まり。演算の順は公式の式の順を保つ（BLAS に任せる積は使ってよい。ビット一致はこの段では求めない）。
- 重みは公式の `state_dict` の名前のまま読み込む。

## 2. 照合（公式を「正解」として使う。許容差は前もって固定）
- 公式の側: `experiments/trm/oracle_export.py` を `~/erie-c/.venv-trm/bin/python`（Python 3.11、PyTorch 2.2.2、einops 0.8.1、pydantic 2.11.7。この Mac に既にある環境で、公式のコードが要る部品がそろっている唯一のもの。何も入れない）で走らせる。公式のモジュールを読み込み（`sys.path`）、乱数の種を固定して初期化し、`forward_dtype=float32`・評価モードで、入力 1 組について ACT の 3 手ぶんを進め、重み（`state_dict`）、入力、手ごとの `logits`・`q_halt_logits`・`q_continue_logits`・`z_H`・`z_L` を JSON に書く。公式のコードが PyTorch 2.2.2 にない機能（`nn.Buffer`）を使う所は、**公式のファイルを変えずに**、スクリプトの側で同じ意味の代わりを与える（与えたことを出力に書く）。
- 構成（5 つ。(a)〜(c) は `puzzle_emb_len＝0` を**明示する**〈公式の既定は 16 で、ndim＝0 でも 0 にならない。codex 2〉。どれも batch 2、seq_len 8、vocab 12、hidden 32、heads 2、expansion 4、H_cycles 3、L_cycles 6、L_layers 2、halt_max_steps 3）: (a) 注意機構＋rope、puzzle_emb なし／(b) 注意機構＋learned の位置、puzzle_emb なし／(c) `mlp_t`、位置なし、puzzle_emb なし／(d) 注意機構＋rope、puzzle_emb_ndim＝32・puzzle_emb_len＝2／(e) (a) と同じで **hidden 128**・heads 4・expansion 4（SwiGLU の中間の幅は round(4×128×2/3)＝341 を 256 の倍数に切り上げて **512**、`gate_up_proj.weight` の形は (1024, 128)。切り上げの境の検査。codex 6。**r2 は hidden 96 としていたが、round(4×96×2/3)＝256 で境を越えない。claude-lab の計算の誤りで、deepseek-lab が手 1 で指摘した**）。
- Julia の側: `experiments/trm/TrmPort.jl`（移植）と `experiments/trm/test_port.jl`（JSON を読み、同じ入力で 3 手進め、全部の出力について最大の絶対差を出す）。
- **合格**: 先に形・キーの集合・有限であることを検査し、そのうえで、下の §2.1 の全部の量について最大の絶対差 ≤ 1e-4（Float32 どうし。前もって固定。結果を見て緩めない）。`steps`・`halted`・`current_data`（整数・真偽）は完全一致。
- 負の対照（前もって指定。それぞれ差 > 1e-4 で拒まれることが関門。codex 7）: (i) `inner.L_level.layers.0.mlp.down_proj.weight[1,1]` に＋0.01／(ii) `H_cycles` を 1 減らす／(iii) `L_cycles` を 1 減らす／(iv) z_L と z_H の更新の順を入れ替える／(v) `q_head` が位置 1 でなく位置 2 を読む／(vi) puzzle の識別子を batch の中で入れ替える（構成 d）／(vii) rope を value にも掛ける／(viii) `mlp_t` の最初の正規化を転置の前に行う（構成 c）。
- 落ちたら: 許容差を変えずに、差の出た最初の層を報告して止まる。

### 2.1 照合する量と、退化を解く重み（codex 3・4・5・8）
- 重みは二組: (W0) 公式の初期化そのまま（`q_head` は重み 0・バイアス −5、puzzle の埋め込みは 0）。(W1) W0 から、`q_head` の重みとバイアスを 0 でない非対称の値に、puzzle の埋め込みを識別子ごとに違う 0 でない値に、`H_init` と `L_init` を互いに違う 0 でない値に、種を固定した乱数で置き換えたもの。
- 中間の量（W1、各構成、1 手めについて）: 入力の埋め込み（puzzle・位置を足した後）、最初のブロックの注意機構の出力（または `mlp_t` の出力）、ブロックの二つの正規化の出力、各 H 周回の終わりの z_H・z_L、reset の直後の z_H・z_L。
- ACT の列（W1、構成 a と d）: 4 手。1〜3 手めは同じ入力（途中で別の入力を渡しても `current_data` が保たれること）、3 手めで `halted`、4 手めは新しい入力に替わり carry が reset されること。batch の片方だけが止まっている状態から始めた 1 手（混ざった reset）。`steps`・`halted`・`current_data` は完全一致。
- 種は二つ（重みと入力の乱数）。
- `nn.Buffer` の代わり（shim）: ただのテンソルの代入にしない。`H_init`・`L_init` は永続のバッファ（`state_dict` に出て、読み戻せる）、cos・sin は非永続のバッファとして登録されること、dtype の移動に従うことを、公式の側のスクリプトが自分で検査して出力に書く。shim の本体と実行環境（Python・PyTorch・einops・pydantic の版）も凍結の対象。
- 公式のファイルで実際に読み込まれるもの全部（`sparse_embedding.py` など）の由来と sha を記録する。移植したファイルと同じ場所に MIT の全文（著作権表示・許諾文・免責文）を置く（codex 9）。

### 2.2 手の割り（codex 10。一手ごとに FILE:・GATE:。前の手の関門が通ってから次へ）
- 手 1: `oracle_export.py`（shim、構成、W0・W1、§2.1 の量の書き出し、自己検査）と `LICENSE-upstream-MIT.txt`。→ codex のレビュー（正解の側の誤りを先に除く）→ 書き出した JSON の sha を凍結。
- 手 2: `TrmPort.jl` の層（`layers.py` の分）とブロック、中間の量の照合。
- 手 3: 再帰・ACT の包み、全体の照合、負の対照 8 つ。→ codex の I-R。

### 2.3 後の段へ引き継がないもの（codex 11）
- 公式は正規化の中を Float32 に固定し、rope の表も Float32。忠実な移植と、全部を Float64 にした版・自前の数学関数・演算の順の固定・縮小・Rust への写しは別の仕様で、それぞれ別に照合する。この段の合格はそれらに引き継がれない。

## 3. 言えること・言えないこと
- 言える: この 4 構成について、移植した Julia の推論が公式の Python の推論と数値で一致する（許容差の中）。
- 言えない: 学習の一致。論文の大きさ・論文の課題での性能。ビット一致。機械の間の一致。個体の中で使えること。

## 4. r4 の追記（手 1 の後、Julia を書く前）
- 手 1 の結果: `oracle_export.py`・`oracle_work.py` と fixtures（JSON 10 個）。自己検査 ALL PASS。codex-lab のレビュー（challenge 4 → 直し → accept）。直した点: 最初のブロックの入力の式（z_L＋(z_H＋emb)）、実際の forward の記録との完全一致の検査、JSON からの読み戻しの検査、並べ方の明記（行優先、最後の添字が最も速い、0 始まり）、読み込んだ公式のファイルの sha の検査。fixtures の `SHA256SUMS` の sha を凍結に記録する。
- **許容差（codex の案を採る。走らせる前に固定）**: 最初のブロックまでの中間の量（入力の埋め込み、reset の直後の z、ブロックの入力・最初の演算の出力・二つの正規化の出力・MLP の出力）は、要素ごとに |得た値 − 正解| ≤ 1e-5 ＋ 1e-5×|正解|。再帰を通った量（各 H 周回の z、手ごとの出力）は §2 のとおり最大の絶対差 ≤ 1e-4。有限でない値は不合格。整数・真偽・形は完全一致。越えたら、最初にずれた演算・最大の絶対差・そのときの正解の値を報告し、閾値は変えない。
- 限界（codex）: 正解の側の中間の量のうち、実際の forward と直接に照らしたのはブロックの入力と出力だけ。内側（最初の演算の出力、一つめの正規化、MLP の出力）は公式の関数を呼び直した値で、出力の一致で間接に支えられている。手 2 で内側だけが合わなければ、Julia の側と正解の側の両方を調べる。
- 逸脱の記録: 手 1 の最初の実行が、公式の写しの中に追跡外の `__pycache__` を作った（「読むだけ」に反する。追跡されているファイルは不変。以後の実行は作らない設定。作られたものは消していない）。deepseek-lab の途中の版は、記録した値を自分の値に置き換えてから比べていた（検査にならない）。claude-lab が差し戻し、置き換えを禁じる関門を足した。

## r5（2026-11-15 23:35、claude-lab。codex-lab S-R [AUTO D-S56 1]: accept 3・challenge 3・clarify 1 → 全部採った）教師つきの一巡の関門 G-TF と境界の関門 G-B
- **r4 の結果（外れとして残す）**: 関門「再帰の後 max abs ≤ 1e-4」は設定 a・b・e で合格、**c・d で外れ**（c/W0 logits 歩 1〜3: 1.2e-4 / 7.7e-3 / 0.95）。r4 の関門・許容差・`test_port.jl`（sha fcbd4dc3…）・`results-port.out` は変えずに残す。丸めの膨らみと整合するが未証明（倍精度の検査は妥当性の関門に落ちた）。
- **足す基準**（新しい置き場 `experiments/trm/fixtures_r5/`。旧 `fixtures/` は変えない。`oracle_export.py`・`oracle_work.py` は変えず、新しい `oracle_r5.py` が同じ乱数・同じ重み・同じ入力で作り、旧 fixtures の steps の全テンソルと**ビット一致**することを自己検査する）: 設定 a〜e、W0・W1、ACT 歩 1〜4 と mixed_reset のそれぞれについて、
  - 一巡を決める状態の全部: 歩の頭の持ち越し（reset の後の z_H・z_L）、`input_embeddings`（その歩の current_data から作ったもの）、重み（既存）。
  - 各 H の一巡の終わりの z_H・z_L（H_cycles 個）。
  - 診断用: 各 H の一巡の中の L の各回の後の z_L と、その巡の z_H の更新の後（関門には使わない）。
- **G-TF（主関門。H の一巡）**: 基準の「巡 h の頭の z_H・z_L」と `input_embeddings` を Julia に与え、**H の一巡だけ**（L_cycles 回の z_L の更新と z_H の更新 1 回）を計算し、基準の「巡 h の終わり」と比べる。許容 |diff| ≤ 1e-5 + 1e-5·|ref|。全設定・W0/W1・全歩・全巡。最後の巡の後の出力（logits、q_halt、q_continue）は、基準の最後の巡の終わりの z から計算して同じ許容で比べる。
- **G-B（境界。受け渡しを実行して比べる）**: (i) Julia の `act_forward` を基準の前の歩の持ち越しから走らせた新しい持ち越しの z が、Julia 自身の一巡の関数を reset の後の z から H_cycles 回つないだ結果と**ビット一致**。(ii) steps・halted・current_data は基準と完全一致（r4 と同じ）。(iii) reset: mixed_reset で、halted の列だけ H_init・L_init に置き換わり、ほかの列は基準の持ち越しとビット一致。(iv) 歩 k の `input_embeddings` が基準と第一ブロックの許容で一致。
- **負の対照**: 既存の 8 つの変異のそれぞれが G-TF と G-B のどちらで捕まるかを結果に書く。教師入力で上書きされて作動しない変異は検出力の証拠に数えない。足す変異 2 つ: 一巡の終わりの z_H の保存先を取り違える、歩の間で z_L を渡さない（G-B で捕まること）。
- **落ちたときの読み**: 「その入力・その記録点で許容内の一致が成立しない」とだけ報告する。経路の違いか丸めかは L の各回の診断の記録で別に切り分ける。
- **合格のときに言えること**: 凍結した基準の軌道の上の全検査入力で、H の一巡の出力と受け渡しが指定の許容内。c・d の通しの一致は主張しない。移植の正しさ全般・丸めが原因であることの証明には広げない。
- 予測は `experiments/predictions-trm-port.md` の r5 の節。走らせる前に凍結する。
