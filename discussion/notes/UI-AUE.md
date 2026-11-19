# UI-AUE: AUE の観察のインターフェースの実装メモ（2026-11-16〜17）

ユーザーの依頼で作った、試運転の個体を絵と音で見るための道具。最初の一つは S54（AUE-試-1・試-2）の見張り「S54 garden」。
理論・規則・個体には関係しない作者の側の道具（X6: 観察は存在の状態に書き戻さない）。〔暫定〕の対象外（理論でないので Fable の見直しは不要）。

## 1. 置き場所と動かし方
- ソース `viewer/s54-of/`（openFrameworks 0.12.1、`~/of_v0.12.1_osx_release` を OF_ROOT として `config.make` で指す。Xcode なし、Command Line Tools の make）。
- 作る `cd viewer/s54-of && make -j8 Release`（初回は oF の本体のライブラリも作り直し約 3 分）。動かす `open viewer/s54-of/bin/s54Garden.app`。
- 使い方と音の中身の説明は `viewer/s54-of/README.md`。ビルド出力（obj/、bin/*.app）は .gitignore。commit はしていない。

## 2. 守っている線（変えるときはユーザーに確かめる）
- **読むだけ**: 読むのは Mac の `experiments/s54-watch.tsv`（見張りの行）、`experiments/trial-data/ref-669-L2{,SF}.sha`（毎歩の状態の基準の sha、60481 行）、`drives-669.txt`（毎歩の二区画の収量）だけ。Pi に接続しない、ラボに書かない。
- **観測と推定を分けて見せる**: 見張りは 1 時間に 1 行。行の間の n は推定（最後に観測した n＋経過秒/10、基準の死の歩で止める）。HUD に observed／estimated を並べ、基準の死に達しても unit の停止が観測されるまでは「awaiting a check」。色と旋律は**基準の** sha から（試運転は確かめるたびに基準と一致）。デモ（時間 600 倍）は画面に「DEMO: simulated time, not the trial」。
- 外へ送らない（artifact にしない）。Pi はインターネットなしなので手元で閉じる。

## 3. 構成（src/ofApp.cpp 約 430 行、ofApp.h、shaders/scene.frag 85 行）
- `loadRefs`・`reloadTsv`（20 秒ごと）→ `update`（各体の stepF・alive・obsDead/expDead・mismatch、Pi の具合 stale/heat/fsBad/unreachable、起動し直しの回数 → flash。値は mutex で音のスレッドへ）→ `draw`（全画面のシェーダー＋`drawHud`）。
- 写像（左＝試-1 L2＝左チャンネル、右＝試-2 L2+SF＝右チャンネル）:

| 入力 | 絵 | 音 |
|---|---|---|
| 基準 sha（その歩） | 体の色相（滑らかに追う） | ピアノの旋律（10 秒 8 音、音 k はバイト 4k〜4k+3: 五音音階の音高・オクターブ・強さ・休符）、鐘の音高（バイト 31） |
| 区画の収量 | 体の渦の速さ | 鐘を打つ強さ |
| 基準の死までの進み | 輪 | — |
| 死（推定・観測） | 体がほどける | 音が消えていく |
| ref_match=false | 赤い乱れ | ピアノのうねり、鐘のうなり |
| throttled≠0x0 | 揺らぎ | パチパチ |
| ext4・ファイル系の誤り | 赤いひび | ノイズ |
| boot id の変化 | 光の輪 | — |
| 行が 75 分より古い・Pi 不応答 | 灰色 | こもる（低域通過） |

## 4. 楽器の音（解析して合成。音のファイルは使わない、元の音はラボに置かない）
- `tools/analyze.py`（numpy は `~/erie-c/.venv-trm/bin/python -I` を借用）→ `tools/analysis.json`・`src/instrument_tables.h`。4 番めの引数に前の json を渡すと、ピアノの wav がないときピアノはそこから引き継ぐ。
- ピアノ: University of Iowa MIS（制限なし）pp/mf/ff × A2〜A5。倍音 16 本の初めの強さ・二段の減衰（τ1・τ2・w2）・非調和 B・打鍵の雑音を、強さと音域で双線形内挿。
- 鐘（2026-11-17、バイオリンから替えた）: ユーザーが選んだ YouTube q0Zn66gvp1w（ナポリの教会の鐘、利用の許諾は自由と確かめられていない）の 5:00〜10:00。重なって鳴る鐘のうち nominal 718 Hz の鐘の 96 打から倍音 20 本（prime 369 Hz に対する比・強さ）。打った瞬間の速い減衰は 6 dB 以上持ち上がった倍音だけで測れた（0.25〜0.75 秒）。長い響きは鐘が止まないので測れず仮の値（prime で 9 秒）。音のファイルはラボに置かず数値だけ（`viewer/s54-of/tools/analyze_bell.py`、`src/bell_tables.h`）。
- 倍音の揺れと空間（2026-11-17）: 鐘の倍音を 0.25〜1.15 Hz 離れた二本に分けた（仮）。やまびこを Freeverb の残響に替え（`v`）、バイノーラル（`b`、左右 35 度、Woodworth の時間差と頭の陰の簡単な模型、HRTF ではない）を足した。
- 釣り合い: `S54_SOLO=piano|bell` で各楽器だけの rms を測り（鐘 0.0185、ピアノ 0.061）、`bellGain`＝2.0（鐘はピアノの約半分）。打鍵の雑音の換算係数 40 と打つ雑音の係数 4 は仮。
- **耳での確認はまだ**（数値の確認だけ: 割れなし・NaN なし・ピーク 0.37）。音色の調整はユーザーが聞いてから。

## 5. 試験の仕組み（環境変数）
`S54_MUTE=1`、`S54_DEMO=1`、`S54_DEMO_WARP=<倍率>`、`S54_SHOT=<png>`（300 フレーム目を保存して終わる）、`S54_WAV=<wav>`（SHOT と一緒に、約 25 秒の音を書き出す。スピーカーからも出るので、録るときは `osascript -e "set volume output muted true"`）、`S54_SOLO=piano|bell`、`S54_REVERB=0`、`S54_BINAURAL=1`。

## 6. 運用の事実
- 見張りのループは Mac のスリープの間に終わることがある（11-16 21:22〜11-17 06:09 の行が欠けた）。`caffeinate -i` 付きで掛け直した。行が古くなると画面が灰色・音がこもるので、それが見張りの止まった合図になる。

## 7. 次の候補（未着手、ユーザーが決める）
- 解像度: 見張りの間隔を短くする（Pi への読むだけの接続が増える。試運転の取り決めと照らす）。
- 切り出した個体（AUE-A 以降）向けの版: 個体ごとの基準はないので、色・旋律は観測した payload sha からだけ作る（推定の旋律は使えない）。
- MIDI 出力（本物の音源で鳴らす）、ビブラートや打鍵の雑音の耳での調整。

- 服（グラフィック）の下調べ（2026-11-17）: `UI-AUE-graphic-styles.md`（メディアアートの様式 15 系統と、S54 で何を着せられるかの案）。
- 体の見せ方（2026-11-17 ユーザーの方針）: 体＝升目（24×24 のトーラス）の上の構成要素の集まり。人の形は真似ない。見せ方（升目のまま・場として滑らか・つながりの網・トーラスを立体に など）をひとまとめにし、選択の箱とスライダーで形質と数値を調整して好みの形にする。物質の体と回路の値は試運転のファイルにないので、Mac で基準を計算し直して書き出す仕様が要る（未着手、置き場所・大きさ・書き手は未決）。
- oF の addon（2026-11-17 に `~/of_v0.12.1_osx_release/addons/` へ入れた。s54-of の addons.make にはまだ足していない）:
  - ofxPd（danomatika、master 3745618）: libpd を同梱。Pure Data のパッチで音を作れる。pdExample のビルドと起動を確認。
  - ofxImGui（jvcleave、develop 45935a4。master は ImGui が古いと README にある）: 選択の箱・スライダー・保存などの UI。example-simple のビルドと起動を確認。
  - ofxFlowTools（moostrik、master 17cabe2、2019 年。OF 0.10 向け）: GPU の流体・光学流・粒子。oF 0.12 で通らなかった 3 か所を手で直した（`ftFluidFlow.h` の setViscosity* の戻り値を void に、`min` を `std::min` に、廃止された `std::bind2nd` をラムダに。`git -C ~/of_v0.12.1_osx_release/addons/ofxFlowTools diff` で見える）。example_core のビルドと起動を確認。
  - ofxMaxim（Maximilian、micknoise、f937afb 2025-01-04、MIT）: C++ の音の合成と解析（発振器・フィルター・包絡・遅延・FFT・MFCC・粒状合成・リバーブ）。リポジトリの `cpp/openFrameworks/ofxMaxim/libs` は古く、maxiReverb・maxiSynths・maxiPolyBLEP などがないので、本体の `src/` と ofxMaxim.h を組み合わせて置いた（git 管理なし、出どころは `addons/ofxMaxim/SOURCE.txt`）。新しい本体から消えた maxiRecorder の typedef を ofxMaxim.h で 1 行だけ外した。PolyBLEP ののこぎり波・FreeVerbStereo・キックを鳴らす試験（`scratchpad/oftest/ofxMaxim_simple`）でビルドと 6 秒の起動を確認。消音して鳴らし、rms は 0.30〜0.34 で NaN なし。addon の中の警告は未使用の変数だけ（88 件）。
- 絵と音の一式の保存（2026-11-17 ユーザー依頼「いつでも差し替えできるように保存」）: `viewer/s54-of/tools/preset.sh`（save / restore / list / check）。いまの一式（ピアノ＋鐘、Freeverb・バイノーラル、シェーダー scene.frag）を `viewer/s54-of/presets/v1-2026-11-17-piano-bell/` に保存（src・bin/data・addons.make・config.make・README.md と各 sha256 の MANIFEST、ビルド済みの `bin/s54Garden.app` も）。restore は先にいまの一式を `presets/_before-restore-<時刻>` に保存してから戻すので、戻したものも失われない。保存したアプリをそのまま起動して絵が出ることを確認（消音）。一時コピーで「変えて→restore→元と一致」を確認。
- 体と回路の値の書き出し（2026-11-17 ユーザー承認「1,2,3 はそのまま」）: 仕様 `viewer/s54-of/tools/export-spec.md`（r1。Julia、lab-coder が書き codex-lab がレビュー、出力 `viewer/s54-of/data/`、6 歩ごとに間引き＋死の歩、毎歩の sha を基準と照合）。
  - 結果（2026-11-17）: `tools/export_body.jl`（218 行）・`read_body.jl`・`export_gate.sh`。`sh viewer/s54-of/tools/export_gate.sh` で GATE PASS（約 220 秒）。
    - E1: 毎歩の sha が基準と一致。E2: dead_at を make_trial.json と照合（L2 20515・L2SF 11343）。E3: 読み戻し（n≤300 の 51 フレームは計算し直してビット単位で一致。n>300 のフレームは sha と大きさと並びだけ確かめ、値は確かめていない）。
    - 負の対照 N1〜N5（基準の改変・C の改変・切り詰め・書き換え途中の失敗・戻しの mv の失敗）はすべて期待どおり落ちた。
    - 出力 `viewer/s54-of/data/body-669-L2.bin`（10998515 B、3421 フレーム）・`body-669-L2SF.bin`（6082780 B、1892 フレーム）と各 .json（見出し・回路のつくり 12 unit／22 辺・出どころの sha）。1 フレーム 3215 B（予想の 10 MB を超えて計 17.1 MB）。
    - Codex のレビューは 2 往復。書き換えの安全（作業ディレクトリ・退避と戻し）を直した。保証は単独の実行で捕まえられる失敗だけで、壊れたら走らせ直せば約 3 分で作り直せる。
- 調整パネル（2026-11-17 ユーザー依頼「調整パネル作成に入って」「解像度ガビガビのフォントはやめて」）:
  - 粗い文字の原因: `openFrameworks-Info.plist` の NSHighResolutionCapable が未展開の `${HIGH_RESOLUTION_CAPABLE}` で、Retina でも半分の解像度を引き伸ばしていた。加えて HUD は oF の点のフォント（ofDrawBitmapString）だった。plist を true にし、起動時にウィンドウを 1280×720 ポイントに保つ（`ofSetWindowShape(1280k, 720k)`）。
  - 文字は ofxImGui（develop、Dear ImGui 1.93）で描く。FreeType（oF 同梱）で輪郭をディスプレイの密度でラスタ化（`config.make` の `PROJECT_DEFINES = OFXIMGUI_FONTLOADER_FREETYPE`、LightHinting）。フォントは Mac の SF Pro Text（/Library/Fonts）＋ヒラギノ角ゴ W3/W6、数字は SF Mono。見つからなければ SFNS・Helvetica・Menlo に落ちる。暗いガラス調の配色、角丸、アクセント 1 色。新しい addon は要らなかった（ofxImGui で足りる）。
  - `src/BodyView.{h,cpp}`・`bin/data/shaders/body.{vert,frag}`: 書き出した `data/body-669-*.{json,bin}` を読み（見出しの layout が知っている形と完全に一致しなければ読まない）、見せ方 5 つ: 光（v1 の一式）・升目・場（24×24 トーラスの上の 3 次 B スプラインのなめらかな場、輪郭は閾値）・回路の網（active＝塗った丸、q＝線の太さと明るさ、sg＝暖色の細い線、h＝点の数、acts＝m の外の輪）・トーラス（立体、体の盛り上がり、升の線）。キー 1〜5、`g` でパネル、`h` で HUD。
  - パネル（見せ方）: 絵の解像度、歩を手で選ぶ（絵だけ。音と HUD は推定の歩のまま、上に帯で表示）、B と A のフレーム間の補間（C と回路は補間しない）、体の中心を追う（トーラス上の円平均）、見る広さ、C・B・A の重み、輪郭の高さ・やわらかさ、にじみ、揺らぎ、升の線・すき間、色相のもと（基準の sha／固定）・ずらし・彩度・明るさ・A の色、トーラスの半径・盛り上がり・なめらかさ・回る速さ・角・距離、回路の名前・線の太さ、HUD の濃さ。保存は `bin/data/looks/<名前>.json`（「起動時の形にする」で default.json、起動時に読む）。
  - HUD は命ごとのカード（体の下）と左上の Pi の行に分けた。カードに「絵の体（基準）n・C の升の数」、左上に「絵の体の値は Mac で基準を計算し直したもの（6 歩ごと）。Pi から観測した値ではない」。
  - 確認: 5 つの見せ方を消音で撮って目で確認、どれも約 120 fps（Retina 2560×1440、Intel i9 の MacBook Pro、ofGetFrameRate の値）。パネルの操作（クリック・保存）は自動では試していない。`S54_LOOK=<0-4>` で起動時の見せ方を選べる（試験用）。
  - 一式: `presets/v2-2026-11-17-panel` に保存。`preset.sh` の保存対象に `openFrameworks-Info.plist` を足し、v1 にも元の plist（未展開のまま）を足して MANIFEST を作り直した。一時コピーで v2→v1 へ restore→ビルド→起動、v1→v2 へ restore で元と一致を確認。
- 暗い・明るいの画面と流れの見せ方（2026-11-17 夜、ユーザー依頼「ダークモードとライトモードに切り替え」「2 をやってみて」＝ofxFlowTools・ofxPd の候補のうち ofxFlowTools を選んだ）:
  - 画面: 暗い／明るい／Mac に合わせる（`defaults read -g AppleInterfaceStyle` を 3 秒ごと）、キー `l`。明るいときは、どの見せ方も暗い地の光として描いたあと `shaders/paper.frag` で紙の上の墨に置き換える（色相を保つ。地の 0.07 までは紙のまま）。ImGui は明るい用の配色に切り替え（`ofApp::applyTheme`）、回路の網の線は墨の色に。looks の json に `theme`。
  - 見せ方 6「流れ（流体）」: ofxFlowTools（光学流 → 橋 → 流体）。注ぐのは場と同じ体の絵（body.frag の uMode 3、地と丸窓なし）。押すのはその絵の光学流。加えて体の絵を毎フレーム直接注ぐ（`Fluid::pour`。ftFluidFlow::addDensity は強さの引数を無視するため、派生クラスで ftFlow::add を呼ぶ）。渦・浮力・広がりは流体の動きで命の値ではない（パネルと README に明記）。ofxFlowTools のライセンスは BSD 型（ソースの見出し）。
  - 確認: 見せ方 光・場・回路の網・トーラス・流れを暗い・明るいで消音で撮って目で確認（scratchpad の shots2〜5）。どれも約 120 fps。Mac が Dark のとき「Mac に合わせる」で暗くなることを確認。明るい側への切り替わりはシステムの外観を変えていないので確かめていない。デモの撮影で一度だけ終わらずに残った（kill -9 で止めた）。走らせ直すと 0 で終わり、再現しなかった。原因は不明。
  - 一式: `presets/v3-2026-11-17-theme-flow`（書き換える前は `presets/_before-theme-flow-20261117`）。
  - 未確認: パネルのクリックでの切り替え、流体の数値の好み（浮力の既定 0.04・注ぐ量 0.8 は目で決めた仮の値）。
