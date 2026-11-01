# core/ — 規則の正本（Julia）

2026-10-31 のユーザー決定（案 A）により、このラボの規則の正本は Julia の `core/` に置く。JavaScript のファイル
（`memory/`・`matter/`）は写しとして扱う。写しを残す理由は二つある。一つはアプリ（ブラウザで動く。ブラウザで動くのは
JavaScript だけ）、もう一つはこれまでの結果の来歴である。写しが正本と一致することは `core/check/` でビット単位で確かめる。

| Julia（正本） | 写し（JavaScript） | 内容 |
|---|---|---|
| `circuit.jl` | `memory/turn_sed.js`（contrast なし＝`memory/turn.js` 版2） | 組織の層の回路。三要素則・沈殿・定位反応と慣れ・待つこと・対比の規則（sed/learn/learn2/learn3/bin3/donly）。idle_first（項番72、既定オフ。アプリは v3.7 から bin3+idle＝`life.jl` RULES） |
| `life.jl` | `memory/life_turn.js` v3.5 | アプリの世界と一生（保育期・学校期・季節、相手・流し直し・盲検、自動セッション、記録）。保存された存在（JSON）をそのまま読み書きする |
| `matter.jl` | `matter/fmatter.js`（＝`matter2.js`、制御なしで `matter.js`） | 物質の層（保存場、構成体、A-gen、MaterialPort） |
| `evo.jl` | `matter/fevo.js`（＝`evo_trm.js`）。`wp=false, lineage=false` で `trm.js`、`lineage=false` で `trm2.js` | TRM 型の構成体（6つのモード、系統、観察フック、actGate、bindConst） |
| `body_org.jl` | `matter/body_org.js` | 組織の層を物質の身体に載せる（ORG/REPLAY/NONE/GREEDY と全オプション） |
| `jsmath.jl` | — | V8 と同じビットを返す exp・tanh・log（openlibm）、cos（fdlibm 5.3）、hypot、mulberry32、toFixed |

移していないもの: `life_turn.js` の v1/v2 の記録の移行（migrate。アプリの存在は 2026-10-30 から v3）、ページの表示（snapshot）、
各段の試験用の枠（`test_*.js`。必要になった段で Julia に書く）。

## 使い方

```julia
include("../core/LabCore.jl"); using .LabCore
b = newborn(true); st = init(b); r = Mulberry(1)
o = step!(st, b, [5.0, 0.0, 0.0]; noise = r, contrast = :bin3)
l = makelife(JSON.parse(read("memory/backup/being-state-pre-learn3-age86642.json", String); dicttype = Dict{String,Any}))
live!(l, 1000)
r = body_org_run("ORG", 1, (U = 0.02, MCOST = 0.004, STEPS = 10000))
```

添字は Julia では 1 始まり。保存された存在（`life.jl` の `L`）だけは、アプリと行き来できるように JavaScript の慣例
（0 始まり、NaN は null）のまま持つ。

## 照合（`sh core/check/run.sh`、約1分半）

1. `math.js` / `math.jl`: 40 万個の入力で、`jsmath.jl` の exp・tanh・log・cos・hypot が V8 とビット単位で一致するか。
   （Julia の Base の関数はおよそ 1〜12% の入力で V8 と最後の桁が違い、そのままでは軌跡が分かれる。）
2. `js_scenarios.js` / `jl_scenarios.jl` / `compare.js`: 同じ 42 の場面を両方で走らせ、出力を全値で比べる。
   回路 19（7 つの規則、相手あり／なし、記憶・定位・探索・失敗則を外した版、乏しい世界）、アプリの一生 5（保存された存在 3 つ、
   新生、v3.4 で動いた状態からの移行。身ぶり・自動セッション・入れ替え・停滞・途中保存と読み戻し・盲検を含む）、
   物質と構成体 14（段32 の場、自然発生の対照、trm.js、trm2.js、fevo の 6 モード、48×48、飢え、actGate・bindConst・観察フック）、
   身体 4（body_org の全条件とオプション）。
3. `app_embed.js`: アプリのページ `memory/index.html` が埋め込んでいる規則が、照合した `turn_sed.js + life_turn.js` と同一か。
4. `reproduce_body_org.jl`: 段42 の結果ファイル `matter/results-body-org.json`（10 種子 × 4 条件 × 10000 歩）を Julia で再現する。

照合が差を見分けることも確かめた（2026-10-31）。ALPHA を 0.05→0.0500001 にすると、対比の統計が動く 3 場面で差が出る。
EROSION を 0.002→0.0020000001 にすると、場と身体の場面で差が出る。減衰の位相をずらすと、回路と一生の場面で差が出る。
ただし ALPHA の変更は、body_org の結果だけでは見えなかった（結果に回路の統計が出ないため）。

## アプリの写し（Rust、v3.6 から）

アプリ（claude.ai の「記憶する回路」）の規則と描画は `rust/being-core` にある（no_std＋alloc。将来は小型の計算機・マイコンへ）。
`circuit.rs`・`life.rs` は `circuit.jl`・`life.jl` の写しで、回路と一生の 24 場面で Julia と全値一致する（`being-tools check`、
`compare.js --a rs --b jl`）。WebAssembly 版はネイティブ版と一致し（`wasm_equiv.js`）、`app/index.html` はその WebAssembly を
そのまま埋め込む（`app_embed.js`）。ページは `sh rust/build.sh` で作る。

## 規則を変えるとき

1. `core/` の Julia を変える（必要なら予測を凍結してから。Lean で証明する項目は Lean を先に）。
2. アプリに入れる場合は `rust/being-core` に同じ変更を入れ、`sh rust/build.sh` でページを作り直す。JavaScript の写しは v3.5 までの
   来歴なので、過去の結果を再現する必要があるときだけ直す。
3. `jl_scenarios.jl` と `js_scenarios.js` に、変更を通る場面を足す。
4. `sh core/check/run.sh` で全場面一致を確かめてから、実験や公開に使う（Rust の場面は `being-tools check` にも足す）。
