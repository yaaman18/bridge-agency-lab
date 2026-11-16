# handoff S54（2026-11-16 19:38、lab-coder。codex I-R 19:25 の 2〜5 の直し。本番は始めていない）
- 直したこと: `experiments/trial/watch.sh`（区切りを TAB=$(printf '\t') に。旧版も実はタブ文字で 17 列だった。dmesg・tune2fs・boot_id・throttled が読めないときは ERR、0 にしない）。`pi_check.sh` place（Pi が「absent」と答えたときだけ置く。ssh の失敗・空・想定外の答えは exit 3 で全体を止める）と rehearsal-check（dmesg ERR・tune2fs ERR）。
- 新しく足したもの: `experiments/trial/end_check.sh BEING_TOOLS RUN AUDIT REF [BOOTS]`（PT1・PT3、r4 の読み (i)）。`experiments/trial/scripts_test_r2.sh BUILD [OLD_DIR]`（Mac だけ。偽の ssh/scp/sudo などを PATH に置く。OLD_DIR は freeze 1 の watch.sh/pi_check.sh で、旧版の欠陥を示す対照になる。今回の写しは scratchpad の old/。sha は freeze の行にある）。
- 結果: `experiments/results-trial-scripts-r2.out` 22 項目 ALL PASS。sha は `experiments/freeze-trial-run-code.txt` 末尾の「freeze 2, third set」（watch 593c4d28…, pi_check 080922f2…, end_check 6cbc762e…, test 63bf92de…, results e392f529…）。第二組の注にある「23 checks」は 22 の誤り。
- n=60480（Mac fast ビルド、final-669-L2 を包み直した写し）: 入力が空だと exit 0、run は不変、監査に start 60480 / wait 60481 / end 60480 eof の 3 行が足される。commit は増えない。chain は ok。
- Pi（読むだけ、1 回ずつ）: watch は 17 列、ext4 0、clean、0、t1/t2 は n 0 で基準と一致、unit は inactive。list では t1/t2 の監査が 0 B、rehearsal が n 37。
- codex: [AUTO D-S54 3] で 3・4・5 は accept。[AUTO D-S54 4] では BOOTS の説明に challenge（総数の余裕で追加の起動が隠れる）。頭の注を「総数だけを見る」に直した（再レビューはまだ）。EC8 の clarify（beyond の分岐だけの回帰の検査になっていない）: 検査はすでに FAIL の理由に commit-beyond-run-n があるかを grep しているが、SHA の不一致と chain の不良も同時に起きている。本番開始の承認は保留のまま。
- 本番を始める前に残ること: (1) claude-lab が「本番中は unit を手で start しない」という運用の記録の置き場を決めて codex に示す（仕様は変えていない）。(2) codex が第三組を確かめて承認するか（[AUTO D-S54 5] は claude-lab の判断）。(3) Pi の実物で n=60480 は確かめていない。(4) 本番の unit の enable の記録。
- 最初に打つコマンド: `tail -7 experiments/freeze-trial-run-code.txt; tail -3 experiments/results-trial-scripts-r2.out; cat $(ls -t discussion/.codex-turns/*.last | head -1)`
