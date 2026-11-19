# メディアアートのグラフィックの様式（S54 garden の「服」の下調べ）

2026-11-17。ユーザーの依頼「メディアアートにおける本当にさまざまなグラフィックスタイルをウェブ上から探索してメモ」。
試作品（S54 の二つの命）に着せる絵の候補を選ぶための一覧。実装の正本は `UI-AUE.md`。

- 印: **〔出典〕** はこの日の検索で裏が取れた事柄（末尾の出典の番号）。**〔知識〕** は私の既知で、この日には確かめていない。
- 各項の「S54 では」は**提案**。何の状態を着せるかの案で、まだ決めていない。
- 守る線（`UI-AUE.md`）は変わらない。観測した事柄と推定した事柄を絵の上でも分ける。絵は存在に書き戻さない。

## 0. 分け方の手がかり

- 生成芸術の分類として広く引かれる Boden と Edmonds（2009）は、見た目ではなく**作り方**で分ける（Ele-art、C-art、D-art、CA-art、G-art、CG-art、Evo-art、R-art、I-art、CI-art、VR-art の 11 種）〔出典 1〕。
- 見た目の分け方には、美術史の Wölfflin の対（線的／絵画的、平面／奥行き など）を借りる例がある〔出典 2〕。
- Manovich は、デジタルアートをいくつかの「世界」に分けている。そのうち一つは、計算を主題ではなく**素材**として扱い、知覚・規模・持続を前に出す作家たち（池田亮司、Carsten Nicolai、Rafael Lozano-Hemmer など）〔出典 3〕。
- このメモでは見た目で分け、各項に作り方を添える。

## 1. 初期の計算機芸術・プロッター

- **プロッターの線画**: 1963〜64 年、シュトゥットガルト大学で数学の学生だった Frieder Nake と Georg Nees が最初の作品を描いた。Zuse の Graphomat Z64 を使い、Max Bense の情報美学と結びついていた〔出典 4〕。
  - Vera Molnar は 1968 年から、ドラム式のプロッターで格子と変奏の作品を作った〔出典 4〕。
  - 見た目: 細い単色の線、格子の規則とわずかな乱れ、同じ規則の変奏の並び。
- **S54 では**: 一歩を一つの格子の升にし、sha のビットで線の向き・ずれを決める。並べると系列の変奏表になる。観測した升は実線、推定した升は点線で描ける。

## 2. ソフトウェアアート・コードの生成芸術

- **流れの場（flow field）**: ノイズなどから作ったベクトルの場に沿って、線や粒子を流す。
  - Tyler Hobbs の Fidenza（2021、999 点）は、流れの場に沿う太い曲がった帯を、ぶつからないように置き、確率的な色の組で塗る〔出典 5〕。
  - 「long-form」の生成芸術は、作家が手を入れずに多様さと質を保つアルゴリズムを要する〔出典 5〕。
- **規則の過程を見せる**: Casey Reas（Processing の共作者）の系統〔知識〕。教え子に Refik Anadol がいる〔出典 3〕。
- **S54 では**: 体の周りに、sha から作った流れの場を置く。収量で線の密度、基準との一致で線の滑らかさを決める。

## 3. シェーダーと生成の幾何

主な資料は The Book of Shaders、Codrops の Fragments（流れの場・レイマーチング・ピクセルソートなど 120 を超える作例）〔出典 6〕。

- **SDF とレイマーチング**: 距離の関数で形を定め、光線を進めて描く。滑らかに溶け合う立体〔出典 6〕。
- **反応拡散（Gray–Scott）**: 二つの物質の反応と拡散でできる斑点・迷路・指紋の模様。写真の明るさで係数を変える例もある〔出典 6〕。
- **ボロノイとドロネー、トゥルシェのタイル、モアレ、網点、等高線、L システム**〔知識〕。
- **セル・オートマトン**: Boden と Edmonds の分類の CA-art〔出典 1〕。
- **S54 では**: 反応拡散の模様を体の皮膚にし、係数を収量で動かす。一致しないときは模様が崩れる。

## 4. デモシーン

- 限られた計算機で、実時間で見せる効果の伝統。代表的な効果は次のとおり〔出典 7〕。
  - プラズマ: 色の勾配が揺れ続ける。
  - ロトズーマー: 画像が回りながら拡大縮小する。
  - トンネル: 点・線・輪でできた筒の中を飛ぶ。
  - メタボール: 溶け合う塊。
  - 炎: 熱の値の格子を色の表で塗る。
  - 効果どうしを組み合わせることも多い（プラズマを立方体に貼るなど）。
- ほかに、ラスターバー（色の帯）、星の流れ、スクローラー（流れる文字）〔知識〕。
- **S54 では**: 炎の格子を Pi の温度（throttled）に、星の流れを歩の進みに使う。

## 5. グリッチとデータの崩れ

- **グリッチ**: 偶然の誤りや雑音を、表現として使う。Rosa Menkman の *Glitch Studies Manifesto*（2010）、*The Glitch Moment(um)*（2011）。Menkman は Nick Briz らと GLI.TC/H を開いた〔出典 8〕。
- **データベンディング**: ファイルを、本来とは違うソフトで編集して壊す。サーキットベンディング（玩具の回路を曲げて音を変える）から来た語〔出典 8〕。
- **データモッシュ**: 動画の圧縮の仕組み（前の絵との差分）を壊し、絵が溶けて流れる〔出典 8〕。
- **ピクセルソート**: 画素の行・列を明るさや色で並べ替える。Kim Asendorf が広めた。偶然ではないので、グリッチに入れるかどうかは意見が割れる〔出典 8〕。
- ほかに、RGB のずれ、ブロックのずれ、走査線、圧縮のブロックノイズ、VHS の揺れ〔知識〕。
- **S54 では**: 基準と一致しないとき（ref_match=false）だけ出す。一致している間は出さないので、崩れに意味が残る。

## 6. データの美学・ミニマル

- **池田亮司**:
  - *test pattern*（2008 年に YCAM で初演）は、文字・音・写真・動画などあらゆるデータをバーコードと 0/1 の模様に変える。白黒が激しく明滅する〔出典 9〕。
  - *datamatics* では、切り詰めた白黒に強い差し色が入る〔出典 9〕。
- **Carsten Nicolai（alva noto）**: 格子、信号、波形の可視化〔知識〕。
- **S54 では**: sha そのものを、白黒の縞として体の帯に流す。観測の行が届いた瞬間だけ差し色を入れる。

## 7. （外した: AI の潜在空間）

2026-11-17 ユーザー決定で候補から外した。学習した模型の出力は存在の状態と一対一に結びつかず、観測の正直さを保てない。
Refik Anadol のような 3D の粒子・流体の**見た目**は AI なしでも作れるので、別の系統として足す余地は残る（まだ調べていない）。

## 8. 人工生命・進化の芸術

- **Karl Sims の Evolved Virtual Creatures（1994）**: 遺伝的アルゴリズムで、ブロックの体と神経の制御を進化させた。泳ぐ・歩く・跳ぶ・緑の立方体を奪い合うことで選んだ。思わぬずるの抜け道を見つけた失敗集も付いている〔出典 10〕。
- **Sommerer と Mignonneau の A-Volve（1994〜97）**: 来場者がタッチ画面に描いた生き物が、水を張った池の中で実時間に生き、遺伝子を次の世代へ渡す〔出典 11〕。
  - 同じ作家の Interactive Plant Growing（1992）、LifeSpacies II（文字を打つと生き物ができる）〔出典 11〕。
- **S54 では**: 系譜として一番近い。ただし**見た目だけ**を借りる。たとえば体の節・触手・膜。観測者が存在に手を入れる仕組み（A-Volve の交配など）は借りない（X6）。

## 9. 点群・計測された空間

- **Rhizomatiks（真鍋大度）**:
  - フォトグラメトリと複合現実で、夢のような風景を作る〔出典 12〕。
  - 金沢での作品では、iPhone で撮った映像から 3D Gaussian Splatting で空間を立て直した〔出典 12〕。
  - Azure Kinect を何台も使う記録〔出典 12〕。
- ほかに、LiDAR の点群、深度カメラ、走査の帯〔知識〕。
- **S54 では**: 体を点の雲として描き、点の数を観測の確かさにする。見張りの行の直後は濃く、推定の時間が延びるほど点がまばらになる。

## 10. 信号をそのまま見せる

- **オシロスコープの音楽**: Jerobeam Fenderson と Hansi Raber。古いアナログのオシロスコープの XY 表示に、手で作った波形で絵を描く〔出典 12〕。
- リサジュー図形、波形、スペクトログラム〔知識〕。
- **S54 では**: いま鳴っているピアノと鐘の左右の信号を、そのまま XY で描く。音と絵が一つの源から出ていることが見える。

## 11. 布・織り・工芸

- **ジャカード織り**:
  - 19 世紀のジャカード織機はパンチカードで模様を織った。Babbage はそこから着想してパンチカードを計算機に取り入れた〔出典 13〕。
  - Anni Albers の *On Weaving*（1965）が要の文献として引かれる〔出典 13〕。
- **計算で織る作品**〔出典 13〕:
  - Matt DesLauriers の WOVEN·CODES（Albers に着想、実際の膝掛けに織った）
  - 西陣の織物を手続き的に生成する研究（wave2weave、Roth と Ueda）
  - Phillip Stearns（コードから直接織る）
  - Cynthia Schira（1983 年から計算機制御のジャカード）
  - 織機の模擬機を持つ Perpetua
- ほかに、刺繍、編み目、レース、パッチワーク、金継ぎ、釉の貫入、青銅の緑青〔知識〕。
- **S54 では**: 一番「服」らしい。各歩の sha 256 ビットで経糸の上げ下げを決め、一歩に一段ずつ布が織り上がる。布そのものが歩の記録になる。推定の歩の段は薄い糸、観測した歩の段は濃い糸で織る。

## 12. 光・投影・空間の作品

- **teamLab**: 2001 年に東京で猪子寿之らが作った、芸術家・プログラマ・技術者の集団。没入する部屋に、花・水・書の筆致が流れる〔知識〕（検索の結果に設立の記述はあったが、どの頁の記述かを特定できなかった）。
- **Joanie Lemercier**: 線と光の投影、建物への投影〔知識〕。
- **Rafael Lozano-Hemmer**: 心拍などの生体の信号を光の列にする〔知識〕。
- ほかに、プロジェクションマッピング、レーザー、ボリュメトリックな光〔知識〕。
- **S54 では**: 光の筋で体の輪郭だけを描く。生きている間は脈を打たせる。

## 13. ネット・ポストインターネットの美学

- **ヴェイパーウェイヴ**: 2010 年代初めの音楽の小ジャンルで、絵の様式でもあり、ミームでもある。初期のネットの絵、90 年代末のウェブ、グリッチ、サイバーパンクを使い、VHS の劣化をよく使う〔出典 14〕。
- **Y2K の未来主義**: おおよそ 1997〜2004 年。光沢・浮遊・発光する立体の部品〔出典 14〕。
- **ブルータリズムのウェブ**: 整ったミニマルに逆らう、むき出しの構造〔出典 14〕。
- **サイバーパンクの HUD**: 照準、計器、走査〔知識〕（HUD とサイバーパンクの結びつきは、検索では裏が取れなかった）。
- **James Bridle の「New Aesthetic」（2011）**: 機械の見方（衛星写真、顔認識の枠、ピクセル）が現実に漏れ出す〔知識〕（この日の検索では確かめられなかった）。
- **S54 では**: 機械が見ているような層（バウンディングボックス・照準・引き出し線のラベル）。観測と推定の区別を一番素直に描ける（実線と点線、「est.」の札）。

## 14. 低解像度・限られた色

- **1 ビットのディザ**（Bayer の行列、誤差拡散）、ピクセルアート、等角投影、ボクセル、ASCII と ANSI のアート、テレテキスト〔知識〕。
- **S54 では**: 見張りの行が古い（stale）・Pi が応えないときは、絵の解像度と色数を落とす。いまの音がこもるのと揃えられる。

## 15. 時間の痕

- 残像、尾を引く軌跡、少し前の姿を重ねる表示（オニオンスキン）、長時間露光、スリットスキャン（時間を一つの軸に並べた絵）〔知識〕。
- **S54 では**: スリットスキャンで、歩の列を横軸に積む。死の歩へ近づく進みが一枚に見える。

## 次に決めること（ユーザー）

- どの系統を地にして、何を状態に応じて重ねるか。前の返事の案は、11 の織り目を地にし、13 の注釈と 5 の崩れを状態に応じて重ねる形。

## 出典

1. Boden & Edmonds, "What is generative art?"（2009）: https://www.bohrium.com/paper-details/what-is-generative-art/811853013856550915-14273
2. Wölfflin の原理を作風の分類に使う論文: https://arxiv.org/pdf/2402.02453.pdf
3. Manovich, "Seven Worlds of Digital Art": https://manovich.net/content/04-projects/138-seven-worlds-digital-art/seven-worlds-of-digital-art.manovich.pdf 、Refik Anadol: https://www.wikiwand.com/en/articles/Refik_Anadol
4. HOLO, "Vera Molnar: Weaving Variations — The Mechanical Arm of the Plotter": https://www.holo.mg/dossiers/vera-molnar-weaving-variations/plotters/ 、Amy Goodchild, "Early Computer Art in the 50's & 60's": https://amygoodchild.com/blog/computer-art-50s-and-60s
5. Tyler Hobbs, Fidenza: https://tylerxhobbs.com/fidenza 、Toledo Museum: https://infiniteimages.toledomuseum.org/artwork/fidenza-370 、Code Review: https://lostpixels.io/writings/code-review-fidenza
6. Codrops, Fragments: https://tympanus.net/codrops/2025/10/17/fragments-a-platform-for-learning-creative-coding-with-shaders/ 、The Book of Shaders: https://thebookofshaders.com/ 、反応拡散: https://stemgeeks.net/@femdev/learn-creative-coding-53-creative-reaction-diffusion
7. Demo effect: https://wiki.riteme.site/wiki/Demo_effect 、Realtime Visualization Methods in the Demoscene: https://old.cescg.org/CESCG-2002/BBurger
8. Glitch art: https://cavac.at/cavacopedia/Glitch%20art 、From compression artifact to filter: https://mastersofmedia.hum.uva.nl/2009/02/from-compression-artifact-to-filter 、Glossi: https://glossimag.com/data-disruption-glitch-art/
9. YCAM, test pattern [nº1]: https://special.ycam.jp/datamatics/en/testpattern.html 、e-flux, datamatics: https://www.e-flux.com/announcements/39634/ryoji-ikeda-datamatics
10. Karl Sims, Evolved Virtual Creatures: https://karlsims.com/evolved-virtual-creatures.html 、ZKM: https://zkm.de/en/node/5735
11. A-Volve: https://interface.ufg.ac.at/christa-laurent/A-Volve.html 、SIGGRAPH Digital Art Archive: https://digitalartarchive.siggraph.org/?p=5305
12. Rhizomatiks / 真鍋大度: https://daito.ws/en/about 、https://rhizomatiks.com/en/work/machinedrum-a-view-of-u 、点群の作例（Oscilloscope Music を含む）: https://creativeapplications.net/tag/point-cloud
13. WOVEN·CODES: https://behance.net/gallery/81481797/WOVENCODES 、wave2weave: https://history.siggraph.org/?p=219980 、Roth & Ueda: https://researchonline.rca.ac.uk/5856/1/TI-2023_DRS_full_paper_Kaori%20Bine%20edit.pdf 、LIA, Weaving: https://www.liaworks.com/videos/weaving-a-generative-artwork/ 、American Craft Council: https://craftcouncil.org/magazine/article/high-tech-high-art 、Perpetua: https://www.blackmountaincollege.org/blazejack_jbmcs_volume-15_final/ 、Phillip Stearns: https://blog.adafruit.com/2017/07/18/translating-computer-algorithms-into-tangible-fabrics-arttuesday/
14. Internet aesthetics: https://www.wikiwand.com/en/articles/Internet_aesthetics 、Y2K Futurism: https://aesthetics.fandom.com/wiki/Y2K_Futurism 、Webflow, retrofuturism: https://webflow.com/blog/retrofuturism 、Retro and brutalist UI design: https://www.setproduct.com/blog/retro-brutalist-ui-design-2026
