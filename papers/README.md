# papers/ — 収集論文の保存場所

`../integrated-list-and-papers.md`（全62項目・153件、Muse と Claude Code のリストの統合版）の論文を、2026-11-04 に取れる範囲で集めた。
合法に無料で公開されている版（オープンアクセス）だけを OpenAlex・arXiv・Europe PMC の API で探して取った。有料の論文は取っていない。

| 状態 | 件数 | 意味 |
|---|---|---|
| `ok` | 27 | PDF を取れた（`pdf/`）。本文テキストは `text/<番号>.txt`（頁ごとに `===== p.N =====`） |
| `text_only` | 3 | PDF は取れず、Europe PMC の全文（XML から文字だけ）を `text/<番号>.txt` に置いた |
| `oa_failed` | 41 | 公開版はあるが、ボット対策などで自動では取れなかった → `manual-download.md`（★10件を先頭に） |
| `no_oa_found` | 82 | 公開版が見つからない（有料・書籍・古い論文）。要約は integrated-list にだけある |

- `index.tsv`: 番号（P001〜P153、integrated-list の並び順）・項目・状態・頁数・ファイル・DOI・取得元・書誌の頭。
- `fetch-results.json`: 試した URL の候補まで含む記録。
- 手で取った PDF は `pdf/manual/P<番号>.pdf` に置く。
- PDF と本文テキストは著作物なので git に入れない（`.gitignore`）。
