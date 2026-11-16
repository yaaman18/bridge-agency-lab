# Pi 5（bridge-pi）を作り直す手順（2026-11-15、claude-lab。S54 §5 (b)。microSD が壊れたときのため）

確認した事実だけを書く。microSD の中身のうち、作り直せないのは **S52 の記録**（`/home/pi/s52/ambient.tsv`）と、走っている稽古の個体の走りのファイル・監査だけ。ほかは下の手順で戻る。

1. OS の像: Raspberry Pi OS Lite 64-bit 2026-10-06（trixie）。sha256 は `b8a393dc…ea8780`（全桁は README 項番162 の周辺と作業の記録にある。書く前に照らす）。`rpi-imager --cli` で microSD に書く（**書き先の確認とユーザーの許可が要る。消去を伴う**）。
2. 起動の区画に cloud-init: `user-data`（ホスト名 `bridge-pi`、利用者 `pi`、公開鍵は Mac の `~/.ssh/id_ed25519.pub`、`ssh_pwauth: false`）、`network-config`、空の `ssh`。
3. 最初の起動の後（Mac から LAN 直結、`ssh -o BatchMode=yes pi@bridge-pi.local`。だめなら `pi@fe80::…%en7` と `-o HostKeyAlias=bridge-pi.local`）:
   - `sudo nmcli con mod netplan-eth0 ipv4.method link-local ipv6.method link-local connection.autoconnect-retries 0`（DHCP のままだと 45 秒ごとに口が閉じる。項番162）
   - `sudo raspi-config nonint do_wifi_country JP`、`sudo nmcli radio wifi on`（どこにも接続しない）
   - 時計: `sudo date -s @<Mac の秒>`（RTC に電池はない）
4. S52 を置き直す: `experiments/ambient/` の `ambient-log.sh` と `s52-ambient-log.service`（sha は `freeze-ambient-log-code.txt`）を `/home/pi/s52/` と `/etc/systemd/system/` に置き、`sudo systemctl enable --now s52-ambient-log`。**新しい記録は別の区間**として扱う（#53 の「直す場合の手順」: 新しいファイル、切り替えの時刻と sha を記録）。
5. S54 を置き直す: `experiments/trial/` の凍結物（`freeze-trial-run-code.txt`）から。**稽古の個体は続きからは戻らない**（走りのファイルが失われたら、その稽古は「媒体の故障で終わった」と記録する。写しから戻すことはしない。戻すかどうかはユーザーが決める）。
6. 失われるもの: S52 の、最後に Mac へ写した時点より後の記録。S54 の走りのファイルと監査。

## 写しの記録（S52 の記録を Mac に写したとき、ここに時刻と sha を足す。中身は換算の凍結まで見ない）

- 写しの記録 2026-11-16 18:35（稽古の前、claude-lab。中身は見ていない）: b61ade543a750b86ddb628bab9499faa70a8eeb903550a160ceed4a047889192  /Users/yamaguchimitsuyuki/s52-copies/ambient-20261116T183548.tsv  446167 バイト
