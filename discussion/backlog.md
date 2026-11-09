# backlog（上から順に。終わったら [x]、足すときは理由を一行）

議題の細目は `agenda.md`（T1〜T10）。論文の番号は `papers/index.tsv`。

## 第1部 読みと要件の厳密化（D は対等で合意して確定 → decisions-log「読み」。bridge-protocol の理論に触れる点は bp-proposals／仮定 H）

- [x] D0 立ち位置と観察者の位置、移行と個体の同一性。`promise-cutout.md`（ユーザーの約束、変えない）を前提に、
      系統の側の作業で「同じ個体か」をどう扱うか（ラボの読み）を詰める。理論に触れる核は BP1（ユーザー待ち）。
      （2026-11-05 足した: 規則や数値を決める前に、作る側の立ち位置を詰めておくため）
      → 2026-11-05 済（往復8で締めた）: notes/D0.md、decisions-log #1、BP2・BP3
- [x] D1 要件の出どころの順位と、`requirements.md` の骨組みを決める。列は notes/D0.md §4（C22 の列案）、最初の行群は決7 の対象ごとの対応表（2026-11-06 締め: notes/D1.md、requirements.md、decisions-log #2）
- [x] D2 R1 自己維持：M1（最大不動点、precariousness）、DC の hSelf・hBound の回路での読み（formal/README.md D1〜D6）、
      制約の閉包（P004 要手取得）・adaptivity（P011 要手取得）。本文あり: P033, P078
      → 2026-11-07 済（往復10 で締めた）: notes/D2.md、decisions-log #3、formal/SelfMaintenance.lean。論文の読み（P004・P011・P033・P078）は取り込んでいない（adaptivity は T の言わないことに置いた）
- [x] D3 R2 環境への応答：M2・M3、hSMC、α/σ の読み（D4）、感覚運動随伴性。本文あり: P031, P040, P102
      → 2026-11-07 済（往復6 で締めた）: notes/D3.md、decisions-log #4、formal/Environment.lean、requirements R-BODY-5
- [x] D4 R3 習慣と沈殿：確かさ・沈殿・FORGET・sed_fade の意味、習慣＝くり返しで自分を保つ型（P033 p.5, p.11）、
      習慣は価値に鈍い（P033 p.13）。本文あり: P033（P034 要手取得）
      → 2026-11-07 済（往復3 で締めた）: notes/D4.md、decisions-log #5、requirements R-BODY-6
- [x] D5 R4 価値と主体性：L2・ValueNeeded・SelfProducing（formal-experiments/Agency.lean）、主体性の条件（P012 要手取得）、
      生存に基づく意味情報（P078）、情報理論的な主体性（P101, P104）、対照（P080, P082）
      → 2026-11-07 済（往復3 で締めた）: notes/D5.md、decisions-log #7、requirements R-BODY-7。P012 は未取得で整合は未評価
- [x] D6 R5 層の分離：対象層とメタ層、快・不快は下層の上の別の層（2026-11-03 ユーザー方針）、LLM は読み取り専用
      → 2026-11-07 済（往復3 で締めた）: notes/D6.md、decisions-log #9。軛の定義は notes/D3b-yoke.md、#8
- [x] S1 `discussion/requirements.md` を起草（Claude）→ レビュー（Codex）→ 確定。D で確定した読み（decisions-log）から要件を立てる。仮定 H に依る要件はその印を付ける
      → 2026-11-08 済（往復6 で締めた）: requirements.md r2、notes/S1-requirements.md。未承認の読みは「順位3 候補」、H1 に依る 4 行に印
- [x] S2 要件と今の実装のずれの一覧（`discussion/gaps.md`）。項番86 の判断（sed_fade・KC 0.0015）に関わるものを先頭に
      → 2026-11-08 済（往復3 で締めた）: gaps.md G1〜G16（A: G1・G2・G3・G4・G7、B: G5・G6・G8・G15、C: G9〜G14・G16）。次は G7 → G8

## 第2部 ずれを一つずつ埋める（仕様 → レビュー → 実装 → レビュー → 記録）

- [x] T1 沈殿だけの結びつきと維持費（agenda T1）。候補：沈殿を「駆動されたこと」で保つ sed_fade の変種（P033 の読み、既定オフ）
      → 2026-11-08 済（S25、notes/T1.md §3）: 変種 SFD を作り比べた。L2 は同じ、R3-b′ が初めて成立（2 走 5 点）。採否はユーザー判断
- [x] T2 固定化と、報酬を最大化しない探索（agenda T2）
      → 2026-11-08 済（読み、codex と締めた）: notes/T2.md §3
- [x] T3 手がかりの競合と常時点いている受容器（agenda T3）
      → 2026-11-08 済（読み、codex と締めた）: notes/T3.md §3
- [x] T4 組み合わせを表せない基体（agenda T4）
      → 2026-11-08 済（読み、codex と締めた）: notes/T4.md §3
- [x] T5 自分で減らした溜まりを読む交絡（agenda T5）
      → 2026-11-08 済（読み、codex と締めた）: notes/T5.md §3
- [x] T6 判定と文献の定義のずれ（agenda T6）— 第1部の結果しだいで S2 に吸収
      → 2026-11-08 済（吸収と取得待ち）: notes/T6.md §3。P004・P011・P012・P028 は本文の取得待ち。L3R の適用対象は未決（gaps G19）
- [x] T7 生と流し直しを区別しない件（agenda T7）
      → 2026-11-08 済（読み、codex と締めた）: notes/T7.md §3
- [x] T8〜T10（agenda）
      → 2026-11-08 済（既存の記録への吸収）: notes/T8-T10.md。T8→D6 R5-d′、T9→G13・G14、T10→D6 LL2′

## 足された項目
