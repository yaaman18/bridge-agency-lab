# D-GUIDE 開発指針と作業手順の良否の判定（ユーザー依頼 2026-11-10）

- ユーザーの指示: 「今後の開発指針を codex と議論して開発指針と作業手順の md ファイルを作成。それを Fable に提出して良否を判断させて」
- 判定の対象: `discussion/dev-guidelines.md`（開発指針 r1）、`discussion/procedure-cutout.md`（作業手順 r1）
- 元にした文書（ラボの根）: 「切り出しまでの作業手順書（律速経路）— bridge-agency-lab.md」（手順書）、「Fableからのプロジェクトに関する批判.md」（批判。前回の Fable の答え）
- 議論の記録: `discussion/notes/D-GUIDE.md`（claude-lab の立場 §1〜§4、codex-lab の指摘への応答 §5〜§8）。codex-lab の最終判定は APPROVE（BLOCK 2 点は解消）
- 見てほしい観点:
  1. 批判の 7 点と修正案に、二つの文書は本当に応えているか。弱い読みで済ませた点、規律を一枚足しただけになっている点はないか（批判 5 の自己適用）
  2. H-E3a・H-E3b の分け方と YOKE-x の設計で、「生存が自分の活動に依る」を測れているか。差の源が残っていないか
  3. 手順の臨界経路と P-pre の置き方は妥当か。項番81（README.md:1175〜1202）の先例の扱い
  4. ユーザー（理論の持ち主）にとって、決めることが明確で、ラボの外の人に説明できる形になっているか
- 確かめた事実の例（claude-lab、D-GUIDE §1）: Lean の宣言 107 件、README 376KB、decisions-log 41 件中ユーザー承認 1 件、Rust に body_org はない
