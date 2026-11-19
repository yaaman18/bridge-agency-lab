# S54 garden: 体と回路の値の書き出し（仕様 r1、2026-11-17）

ユーザー決定（2026-11-17「1,2,3 はそのまま実行して OK」）: (1) Julia で書き出し、書き手は lab-coder、レビューは codex-lab。
(2) 置き場所は `viewer/s54-of/data/`。(3) 間引く。
これは観察の道具（UI-AUE.md §2、X6: 観察は存在に書き戻さない）。理論・規則・個体には触れない。`core/` を変えない。

## 1. 何をするか
S54 の二つの命（種子 669、試-1 = LawL2「669-L2」、試-2 = LawL2SF「669-L2SF」）の基準を、Mac の Julia `core/` で誕生から計算し直す。
毎歩の状態の SHA-256 が基準のファイルと合っていることを確かめながら、間引いたフレームを書き出す。

- 誕生: `onelife_birth(669, LawL2)` と `onelife_birth(669, LawL2SF)`。
- 収量: `experiments/trial-data/drives-669.txt`（行 n+1 = 歩 n の "g1 g2"）。
- 基準: `experiments/trial-data/ref-669-<tag>.sha`（"n sha"、n = 0..60480。`bytes2hex(sha256(onelife_save(s)))`、作り方は `experiments/trial/make_trial.jl` の walk_ref）。
- 歩: `s, e = onelife_step(s, g)`。e は常に false のはず（true なら止まって失敗）。
- 終わり: `s.dead` が初めて true になった n（dead_at）で止める。make_trial.json の値は L2 20515、L2SF 11343 で、合わなければ失敗。
  60480 歩に達しても死ななければ、そこで止める。

## 2. 間引き
- 書き出すのは n % 6 == 0 の歩（6 歩 = 試運転の 1 分）。加えて n = dead_at（6 の倍数でなくても）。
- n = 0（誕生）も書く。

## 3. ファイル（命ごとに 2 つ、`viewer/s54-of/data/`）
`body-669-<tag>.json`（見出し）と `body-669-<tag>.bin`（フレームの並び）。

見出し（JSON、一行でなくてよい）:
- `format`: 1、`seed`: 669、`tag`、`law`: LAW_L2 / LAW_L2SF の文字列、`W`: 24、`H`: 24、`every`: 6
- `nframes`、`frame_bytes`、`dead_at`（なければ null）、`death`（s.death）
- `layout`: フレームの中の欄の順・型・個数の一覧（下の表と同じ）
- `circuit`: 回路のつくり（命の間で変わらない。誕生の `s.b` から）。`names`・`kind`（文字列）・`feat`・`theta`・`patch`・`edges`（[from, to, w] の 1 始まり）・`initial`
- `sources`: drives-669.txt・ref-669-<tag>.sha・`core/` の各 .jl・このスクリプトの sha256
- `site_index`: 「site i（1 始まり）= (y, x)、i − 1 = y·W + x」

フレーム（little-endian、固定長、詰め物なし）:

| 欄 | 型 | 個数 | 中身 |
|---|---|---|---|
| n | Int32 | 1 | 歩 |
| sha | UInt8 | 32 | その歩の状態の SHA-256（基準と同じ値） |
| reservoir | Float32 | 1 | `s.w.port.reservoir` |
| pool | Float32 | 2 | `s.pool` |
| born, died | Int32 | 2 | `s.w.born`、`s.w.died` |
| alive | UInt8 | 1 | dead なら 0、そうでなければ 1 |
| C | UInt8 | 576 | `s.w.C` |
| B | Float16 | 576 | `s.w.B` |
| A | Float16 | 576 | `s.w.A` |
| active | UInt8 | NU | `s.circuit.active`（NU = 回路の unit の数） |
| q, sg, h | Int32 | NE ずつ | `s.circuit.q`・`sg`・`h`（長さ NE が q0 と同じであることを確かめる。違えば仕様への問いとして止まる） |
| acts | UInt8 | 2 | `onelife_acts(s)` の区画 1・2 が動いたか |

Float16 の値は丸めなので、表示用。正の値は正確な値ではない、と見出しの `note` に書く。

## 4. 書いてよいもの
- `viewer/s54-of/tools/export_body.jl`（書き出し）
- `viewer/s54-of/tools/read_body.jl`（読み戻しの検査）
- `viewer/s54-of/tools/export_gate.sh`（関門の一本のスクリプト）
- `viewer/s54-of/data/` の出力
- 走りの記録 `viewer/s54-of/tools/export-gate.out`
ほかは読むだけ。`core/`・`experiments/` は変えない。

使い方は `cd experiments && julia --project=.. ../viewer/s54-of/tools/export_body.jl [--max-steps N] [--ref FILE] [OUTDIR]`。
`--max-steps` と `--ref` は関門の負の対照のため。既定は全部の歩と本物の基準。

## 5. 関門（export_gate.sh で一度に走らせ、最後に合否の要約を数行書く）
- E1 基準との一致: 誕生から dead_at までの毎歩で、sha が基準の行と一致する（両方の命）。一つでも違えば非零で終わり、出力を残さない（一時の名前に書いて、最後に名前を変える）。
- E2 死の歩: dead_at が make_trial.json と同じ（L2 20515、L2SF 11343）。
- E3 読み戻し: `read_body.jl` で見出しとフレームを読む。次を確かめる。
  - ファイルの大きさ = nframes × frame_bytes。
  - n の並びは 0, 6, 12, … と dead_at。
  - 各フレームの sha が基準の行の sha と同じ。
  - 独立に計算し直した最初の 300 歩の状態と比べる（n ≤ 300 のフレーム）。C は完全に一致、Float16 の欄は `Float16(x)` と完全に一致、回路の欄は完全に一致。
- 負の対照（それぞれ落ちることを確かめる。短く `--max-steps 50` で）:
  - N1: 基準の一行の 16 進の一文字を変えたコピーを `--ref` に渡す → E1 で落ちる。
  - N2: 書き出した .bin のコピーの C の 1 バイトを変える → E3 で落ちる。
  - N3: .bin のコピーを 1 バイト短くする → E3 で落ちる。
- 大きさ: 二つの .bin の大きさを報告する。予想は合わせて約 10 MB（L2 約 3400 フレーム、L2SF 約 1900 フレーム、1 フレーム約 2 KB＋回路）。予想から大きく外れたら報告する（外れても失敗ではない）。

## 6. 報告
- 書いたファイルと行数、関門と負の対照の結果、大きさ、かかった時間。
- 仕様への問い（NE と q の長さ、acts の意味など、仕様で決めきれていなかった点）。
