# S54 試運転を始める手順（2026-11-16、lab-coder。仕様 `specs/S54-trial-run.md` r4〈freeze 4〉、設計 `notes/D-POWER.md`）

- 位置づけ: 準備の記録と、これから打つコマンドの列。**ここに書いたコマンドは、まだ一つも打っていない**（unit は `/home/pi/s54/units/` に置いただけ。`/etc/systemd/system` へ入れていない、enable も start もしていない）。稽古は**ユーザーの一言があってから**。本番は稽古が通り、ユーザーの一言があってから。
- 記号: `PI=pi@bridge-pi.local`、`B=~/s54-work/build-d`（S49d のソースの写しと四つのビルド。`build-d/builds.txt`）、`BT=$B/mac-prod/release/being-tools`（Mac の側で走りのファイルを読む道具）。Mac の上のコマンドは `~/bridge-agency-lab` で打つ。
- sudo: Pi の `sudo -n` は通る（2026-11-16 に `sudo -n true` だけで確かめた）。sudo が要るのは unit を入れる・外す・電源を切るときと、見張りの読み（`dmesg`、`tune2fs -l`）だけ。

## 準備で確かめたこと（結果のファイル）
- §1 関門 H1〜H3（S49d の版、`onelife-run.rs` b5b0e2ac…）: 全部合格 → `experiments/results-trial-gates-d.out`。
- §2 基準: n＝0 の一致（三体）と Mac の短い間隔のビルドの全 60480 歩の一致 → `experiments/results-trial-ref.out`。sha → `experiments/freeze-trial-run-inputs.txt`。
- 基準の副産物（予測しない、報告だけ）: 試-1（L2）は 20515 歩めに、試-2（L2+SF）は 11343 歩めに死ぬ。稽古の体（627・L2・D1）は 60480 歩まで死なない。C1 の Pi の監査は Mac の監査とバイト一致（7ef47a0c…、06d332ed…）。
- 順の逸脱: C1 は Mac の R2（全 60480 歩、約 2 時間 25 分）が終わる前に並べて走らせた（照らす先は Julia の基準なので判定は独立）。R2 はその後に合格。
- §3 C1（Pi、`/dev/shm/s54-c1/`、二体 × 60480 歩）・C2（Pi、製品のビルド 12 歩、Mac の時計で 120.4 秒）: 合格 → `experiments/results-trial-pi-check.out`。
- §4 包みの検査（Mac と Pi の `/dev/shm`）: 合格 → `experiments/results-trial-wrapper.out`。
- 確認した事実: `/dev/shm` の中の pi のファイルは、pi の最後のログインの会話が終わると消える（systemd-logind の RemoveIPC。既定のまま。1 回めの C1 はこれで判定の前に消えた。2 回めは ssh の会話を一つ開けたまま走らせた）。**本番・稽古の置き場は `/home/pi/s54/` なので当たらない。** C1 の残りは次に会話が全部閉じたとき消える。

## (a) 止めて入れ直す稽古（§5。1 回。ユーザーの手）
前（claude-lab、Mac）:
1. 置いたものを照らす: `sh experiments/trial/pi_check.sh $B list` → 下の (e) の sha と同じ、rehearsal の n＝0・監査 0 バイト。
2. S52 の記録を Mac に写す（中身は見ない。sha と時刻だけ `notes/pi-rebuild.md` の「写しの記録」に足す）。写し先は案: `mkdir -p ~/s52-copies && scp -o BatchMode=yes $PI:/home/pi/s52/ambient.tsv ~/s52-copies/ambient-$(date +%Y%m%dT%H%M%S).tsv && shasum -a 256 ~/s52-copies/ambient-*.tsv | tail -1`。
3. 稽古の常駐を入れて始める:
   `ssh $PI 'sudo cp /home/pi/s54/units/s54-rehearsal.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now s54-rehearsal.service'`
4. 5 分ほど待ち（n が 30 前後）、`sh experiments/trial/pi_check.sh $B rehearsal-check` と `sh experiments/trial/watch.sh $BT rehearsal`。確かめる: unit active、n＞0、payload SHA＝基準、commit の他 0、S52 active、boot_id を控える。

止める（ユーザー）:
5. Pi 5 の電源ボタンを **1 回短く**押す → 数秒で止まり LED が赤になる。（ユーザーの一言があれば claude-lab が `ssh $PI sudo systemctl poweroff` を打ってもよい。）**LED が赤になる前に抜かない。**
6. 入れる: ボタンをもう一度押す（または赤になった後に挿し直す）。

後（claude-lab、Mac）:
7. つながるのを待つ: `until ssh -o BatchMode=yes -o ConnectTimeout=5 $PI true; do sleep 10; done`（Pi の時計は判定に使わない。時計を合わせるかは S52 の手順に従う）。
8. `sh experiments/trial/pi_check.sh $B rehearsal-check` を 2 回（1 分以上あけて）と `sh experiments/trial/watch.sh $BT rehearsal`。確かめる（§5）: boot_id が変わった／unit active（人手なしで再開）／n が増える／payload SHA＝基準の n の値（走りのファイルは完全な版）／commit の他 0／監査は `start` が足され、break と audit_behind の数を報告（個体は止まらない）／S52 active／dmesg の ext4 の誤り 0／tune2fs の state clean・FS Error count なし。一つでも落ちたら本番は始めず報告。
9. 稽古の常駐を外す: `ssh $PI 'sudo systemctl disable --now s54-rehearsal.service && sudo rm /etc/systemd/system/s54-rehearsal.service && sudo systemctl daemon-reload'`。稽古の走りのファイルと監査は残す（写さない、戻さない）。

## (b) 本番の unit を入れて始める（稽古が通り、ユーザーの一言の後）
1. `sh experiments/trial/pi_check.sh $B list` → t1・t2 の sha が (e) と同じ、n＝0、監査 0 バイト。
2. `ssh $PI 'sudo cp /home/pi/s54/units/s54-trial-1.service /home/pi/s54/units/s54-trial-2.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now s54-trial-1.service s54-trial-2.service'`
3. すぐに `sh experiments/trial/watch.sh $BT` を 1 回（始めの行。Mac の時刻が PT2 の起点）。以後は (d)。
- 常駐は起動時に始まる（`WantedBy=multi-user.target`）、`Restart=no`（誤りで止まったら次の起動まで止まったまま）。止め方は (a) の 5・6 と同じ（ボタンを押してから抜く）。

## (c) 外す
- 一体ずつ: `ssh $PI 'sudo systemctl disable --now s54-trial-1.service && sudo rm /etc/systemd/system/s54-trial-1.service && sudo systemctl daemon-reload'`（2 も同じ）。走りのファイル・監査・入力は `/home/pi/s54/t1`・`t2` に残る。外した後に包みを手で走らせない。
- 稽古を終えるのは n＝60480 かユーザーの一言（§4）。n＝60480 で `onelife-run` は入力が尽きて終わり、unit は inactive になる。起動のたびに包みは n＝60480 を読み、空の入力で `onelife-run` を走らせる（監査に start・end が足されるはず。推論で、確かめていない）。気になるなら外す。

## (d) 見張り `watch.sh`
- claude-lab が Mac から 1 時間に 1 回: `sh experiments/trial/watch.sh $BT`（行は `experiments/s54-watch.tsv`。稽古のときは第 2 引数 `rehearsal`、行は `experiments/s54-rehearsal-watch.tsv`）。自分では繰り返さない。
- Pi では読むだけ: 走りのファイルを各 1 回 `cat`（その一つの写しから n と SHA）、throttled、unit の is-active、boot_id、`sudo -n dmesg` の ext4 の誤りの数、`sudo -n tune2fs -l` の state と error count。止めない・再起動しない・書かない。
- 終わったとき（または外したとき）の監査の照合は `pi_check.sh` の `c1-verify` と同じ形（commit の列を `trial-data/ref-669-*.sha` と照らす）で、別に書く（まだない）。

## (e) いま Pi に置いてあるもの（2026-11-16 06:38、`pi_check.sh $B list` の出力、Pi の sha256sum）
- `/home/pi/s54/t1/`（試-1、669・L2）・`t2/`（試-2、669・L2+SF）・`rehearsal/`（627・L2・D1）に各:
  - `being-tools` d7241d3225c5bafdd6ad8610aaa0965eba0974b69026afe3e164d311a645d836（製品、aarch64 musl 静的）
  - `onelife-run` 2c2272540622558cd572b7982dc5366ffa39f5832c8397850a9451a889c7ef12（製品、10 秒）
  - `s54-run.sh` cd97173ab2ad7b5077b38291b21cba70d906e92462db17ca5fcf67f2873e8dab
  - `run.audit` 0 バイト（e3b0c442…）
  - `drives.txt`: t1・t2 2898578ff08b874c413b9b14212755b3fe95e2b8723beb1ed3e7282929377057、rehearsal 95abfd56511d13846a171ff7fb70a525c51a48af0357e005cfefe8a152aa5678
  - `run`（n＝0）: t1 95e94b4c90b5c4fc1f766cb5db5fdf339f825467dabb80f669761509cf65599f、t2 acd071b95af0791c1fe40b959000b71910100665abb9f98e520a2a6bde1978a5、rehearsal 87d23927d6ec53d5cb626350b9f61e5a59ae2c59ee2bf33622e50e4ec1b4ab17
- `/home/pi/s54/units/`: `s54-trial-1.service` 02dadc827bafe15dc0074f23f12c639b402b8e51ca70b1e00bd1dc83f5c5a0e0、`s54-trial-2.service` 43ddf5e3e05e06a80254a43bb5ad275cee8a7fbf4d0f241ac29e2986a52c0693、`s54-rehearsal.service` bfe02e7af8fa503024728c5421ac7ebfa758b5ca9bbfbbd065825e6f26664e08
- `/home/pi/s54/c2/`（C2 の製品 12 歩、n＝12）と `c2/neg/`（負の対照、短い間隔、n＝12）。本番には使わない。
- `/dev/shm/s54-c1/`（C1 と包みの検査。RAM、会話が全部閉じるか再起動で消える）。
