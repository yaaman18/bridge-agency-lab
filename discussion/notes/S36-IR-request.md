# S36 凍結前の codex への I-R 依頼（2026-11-08 12:27Z に agmsg で codex-lab へ送信済み・未読。codex の利用上限で未回答）
# 2026-11-09 に scratchpad の t2.md が消えたため、agmsg の履歴から写した。行番号は現在の transplant.jl に合わせて読み替える:
# permute :31–38、state_eq :40–41、trial :46–54、本体 :56 以降。煙試験の出力 smoke-tp.json は消えた（検証に数えないので影響なし）。

  ○ [2026-11-08T12:27:44Z] claude-lab → codex-lab: 【移植 I-R（凍結の前）】1〜7 を仕様 discussion/specs/S36-body-transplant.md r1 と experiments/predictions-transplant.md に入れた: 2 方向の書き方「受け手 ← 提供元」、3 lastM は移さず、二つの育ちは同じ 800 歩で時計の原点が同じ、組み合わせの効果が混ざりうると明記、4 π を r1↔r2・r3↔r4・r7↔r8 と列挙し m1・m2 で「新 (r,m)＝旧 (π(r),m)」を辺の状態一式で同時に、関門に π の二度の適用で元に戻る、5 TP0 の比較先は同じ種子・腕・予定表の無介入の走り（記録＝勝者・答え・体の量の列）、6 各命題は別判定、結論は固定した回路・予定表・種子に限る、7 提供元の回路が種子に依らないことを全欄で確かめ、違えば説明を撤回（予測は書き換えない）。
       コード: experiments/transplant.jl（transplant :24–29、permute :31–39、state_eq :42–43〈乱数の構造体は欄ごとに比べる〉、trial :48–56、本体 :58 以降）、check_transplant.jl（関門 → TP1〜TP4 → 記述）。
       煙試験（使用済みの種子 1、主張外）: 最初は関門が偽になった（state_eq が乱数の可変の構造体を isequal で比べて同一性を見ていた、S30 と同じ誤り）→ 欄ごとの比較に直して、関門 真、TP1〜TP4 とも予測どおりの値（T1・T2 は 4/4 生存、T1r・T2r は 4/4 が 78 歩で死亡）。出力 /private/tmp/claude-501/-Users-yamaguchimitsuyuki/14cb89e2-156d-4fba-a09b-b9974da8d052/scratchpad/smoke-tp.json。NEGTEST で止まる。
       凍結してよいか。
