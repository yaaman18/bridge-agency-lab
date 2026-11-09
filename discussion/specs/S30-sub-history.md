# S30 元の基体 SUB での履歴介入の比較契約（R-SUB-1）と死・回復の診断（R-SUB-2）（gaps G11）

- 状態: r1・実施済み（README 項番129）（2026-11-08、gaps C 往復6〜7 の codex を反映。r0 の文は下の「確定」が優先）。bp は変えない（判定を変える部分はない。開始状態の差し替えはラボの側の `@eval AS` の上書きで、CLAUDE.md の手順どおり）。
- 事実: SUB（`bp:tools/AgencySubstrate`）は決定的で、試しは毎回 `initial_state(s, p)`（初期の活動・強さ strength0・資源 resource0・t＝0）から始まる（`substrate.jl:49–51`、`:128–136`）。生涯や育ちがないので、履歴の介入はラボで定める必要がある。
  テンプレート（`fixtures/templates.toml`）: agent・static-agent・reflex・thermostat・alternator・no-loop（凍結、sha は bp の freeze と一致）。
- **R-SUB-1 比較契約（案）**: 出生状態 B＝`initial_state(s, p)`。履歴＝B から K 歩を前段の予定表 X で走らせる（`AS.step!`、何も黙らせない）。試しの開始状態＝その後の状態の写しで、**活動と強さ（履歴の跡）を引き継ぎ、t は 0 に、資源は試しの Params の resource0 に戻す**（試しの予定表の位相と資源の条件を揃える）。
  腕: X＝p1-high と X＝p2-high（凍結の生存の予定表から）、K＝凍結の horizon（60）。同じに保つもの: テンプレート・Params・試しの予定表・判定の式（AS.evaluate をそのまま）。変えるもの: X だけ。
  実装: ラボで `@eval AS initial_state(s::Substrate, p::Params) = …` を上書き（前段の結果の表を引く、表が空なら元の定義と同じ）。対照: K＝0 の上書きが元の evaluate と全テンプレートで同じ。
  観測: AS.evaluate の全欄（L2・L3・L3R・core・選択・survival の表）を腕ごとに。H の支持＝同じテンプレートで二つの腕の観測が違う。
- **R-SUB-2 診断（案）**: 凍結の生存の予定表の各試しで、(i) dead の時刻、(ii) 末尾 alive_window の各時刻の活動する非感覚ユニットの数、(iii) 有限救出: 終点で survives が偽の試しについて、終点の状態の写しに資源 rmax を与え R＝alive_window×4 歩を同じ予定表で進め、末尾 alive_window で survives の条件を満たすか（回復の真偽と時刻）。survives の判定は変えない（別の診断として併記、決4）。
- 予測（案、凍結前）: SH0（対照）K＝0 で全テンプレートの evaluate が元と同じ。SH1 少なくとも 1 つのテンプレートで二つの腕の evaluate の欄が違う。SR1 dead は agent・static-agent では起きない（凍結の結果の L2・L3 の表から）…（往復で詰める）。
- 問い: 開始状態で何を引き継ぎ何を戻すか、K と X の選び方、救出の量と期間、予測の形。

## 確定（往復6〜7）
- 開始状態: 引き継ぐ欄＝active・strength・dead、戻す欄＝t（0）・resource（試しの Params の resource0）。上書きした `initial_state` は保存した前段の状態の deepcopy を呼ぶたびに返す（関門: 一つの試しの変更が保存状態や別の試しに伝わらないこと）。
- H の対比較は**両腕とも前段の終わりで dead でないテンプレート**に限る。前段で死んだ腕は腕別に件数と対象を記録し、片腕だけ適格な例を H に入れない。
- SH0: 上書き前の元の evaluate の**返却欄全体**を、K＝0 の上書きと全テンプレートで照合。不成立なら履歴の解釈を止める。
- SH1: 比べる欄＝agency・self_producing・self_repairing・core・core_enables_action・alive_somewhere・differentiated・value_needed・value_tracking・二つの選択の予定表での choice・生存の予定表 4 つでの survives。どれか一つでも違えば「違う」。
- R-SUB-2（予測なし、ラベルを凍結）: 対象＝出生の対照（K＝0）と二つの腕の、生存の予定表 4 つの試し。(i) dead の時刻（規則上、死亡の後は回復しない: `substrate.jl:66–72`、死亡は救出の対象外として別に集計）。(ii) 末尾 alive_window の各時刻の活動する非感覚ユニットの数。
  (iii) 救出: 終点で dead でなく survives が偽の試しに限り、終点の写しに救出の始めに一度だけ resource＝rmax を置き、予定表の時刻を続けて **R＝alive_window×4 歩**（観測の上限）進める。最初の再活動の歩と、救出後だけの窓で alive_window 連続の条件を初めて満たした歩を記録。上限まで未達なら「この操作・期間で未達」と書き、回復不能とは読まない。
- テンプレートは凍結の 6 つ（agent・static-agent・reflex・thermostat・alternator・no-loop）、K＝60、腕 X＝p1-high・p2-high。種子はない（決定的）。
