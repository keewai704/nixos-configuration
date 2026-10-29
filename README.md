# nixos-configuration

自宅サーバー `orange`（`x86_64-linux`）の NixOS 設定です。

OS・ハードウェア・システムサービスは **NixOS**、個人のアプリや設定は **Home Manager** で管理します。
作業ルール（検証・コミット・適用の手順）は [AGENTS.md](AGENTS.md) にあります。

orange の Tailscale SSH は、[Tailworm の報告](https://tailworm.com/)への暫定対策として
TCP・Unix ソケットのローカル／リモート転送を禁止しています。SSH ログインは利用できます。
`tailscaled` のメモリは 1 GiB、スワップは 0 に制限し、メモリ枯渇時の影響を抑えます。
設定は [modules/common/network.nix](modules/common/network.nix) で管理します。

## ディレクトリ構成

```text
.
├── flake.nix            入力（依存リポジトリ）、orange の構成、開発用シェル
├── hosts/orange/        ハードウェア、GPU、起動、settings.nix、services/ にサーバー機能
├── modules/common/     Nix、ネットワーク、ユーザー、Home Manager の接続
├── home/keewai/common/  個人設定（シェル、Git、コーディングエージェント、T3 Code）
├── pkgs/                自作・改造パッケージとパッチ
├── skills/              Claude Code・Codex に配る個人スキル
└── secrets/             agenix で暗号化した秘密情報
```

1つの機能が複数のファイルを使う場合は、ディレクトリにまとめて `default.nix` を入口にします
（例：`home/keewai/common/shell/`、`hosts/orange/services/tv/`）。シェルスクリプトなどの素材も、
使う側の `.nix` と同じ場所に置きます。

### 読み込みの流れ

```text
flake.nix
└── nixosConfigurations.orange
    ├── modules/common
    │   └── home-manager.nix  →  home/keewai/common
    └── hosts/orange
        └── services/        default.nix がサーバー機能を明示的に読み込む
```

## やりたいこと別の編集先

| やりたいこと | 編集するファイル |
| --- | --- |
| CLI ツールを追加 | [home/keewai/common/packages.nix](home/keewai/common/packages.nix) |
| シェル・エイリアス・プロンプト | [shell/](home/keewai/common/shell/default.nix)（`starship.toml` も同じ場所） |
| Git / GitHub CLI | [git.nix](home/keewai/common/git.nix) |
| Claude Code・Codex・スキル・MCP サーバー | [coding-agents/](home/keewai/common/coding-agents/default.nix)、[skills/](skills/) |
| T3 Code（nightly サーバー） | [t3code.nix](home/keewai/common/t3code.nix)、[pkgs/t3code](pkgs/t3code/) |
| orange のハードウェア・GPU・起動 | [hosts/orange/](hosts/orange/)、[graphics.nix](hosts/orange/graphics.nix) |
| orange のサービス・ポート・保存先 | [hosts/orange/services/](hosts/orange/services/)、[settings.nix](hosts/orange/settings.nix) |
| orange の USB チューナー・EDCB・KonomiTV | [tv/](hosts/orange/services/tv/)、[pkgs/](pkgs/) |

迷ったときは次の基準で置き場所を決めます。

- **ログイン、ドライバー、udev、PAM、デーモンなど OS との連携** → NixOS（`modules/` か `hosts/`）
- **自分だけが使うアプリや設定ファイル** → Home Manager（`home/keewai/`）
- **特定のマシンのハードウェアに依存するもの** → `hosts/<host>/`

## よく使うコマンド

```sh
nix flake update                                                  # 入力をまとめて更新（適用の前に毎回実行してコミット）
sudo nixos-rebuild test --accept-flake-config --flake .#orange    # 一時的に適用して動作確認（再起動で戻る）
sudo nixos-rebuild switch --accept-flake-config --flake .#orange  # 本適用（起動時の既定にもなる）
nix fmt                                                           # Nix ファイルを整形
nix develop                                                       # 言語サーバーや整形ツール入りのシェル
nix build --accept-flake-config .#<パッケージ名>                   # pkgs/ のパッケージを単体でビルド
```

`nixos-rebuild` には、必ず実行中のマシン自身の名前（`hostname` の結果）を指定します。

`nix` は、`gh auth login --hostname github.com` で認証済みなら、実行時に GitHub CLI から
トークンを取得して GitHub 入力と GitHub API への直接アクセスに使います。認証情報がなければ
認証なしで実行します。トークンは Nix ストアやリポジトリに保存せず、API 用の一時認証ファイルは
コマンド終了時に削除します。既存の Nix 設定と他のホスト用の認証情報も引き継ぎます。

## バイナリキャッシュ

`flake.nix` の `nixConfig` と `modules/common/nix.nix` に、Claude Code・Codex・nix-community の
キャッシュの URL と署名鍵を書いています。`nixConfig` には import や計算式が使えないため、
共通の URL と鍵は両方を手で同じ内容に保ちます。

- 新しい設定を適用する前の最初のビルドでもキャッシュを使えるよう、`nixos-rebuild` と `nix build` には
  `--accept-flake-config` を付けます。初回の適用前に単体ビルドするときは
  `sudo nix build --accept-flake-config --no-link .#<パッケージ>` を使います
  （信頼されていない利用者は、flake を受け入れても新しいキャッシュや鍵を追加できないため）。
- `accept-flake-config` を全体で有効にはしません。中身を確かめた flake のキャッシュ設定だけを受け入れます。
- `cache.nixos.org` はそのまま使います。
- キャッシュに載るのは、まったく同じストアパスのものだけです。自前のパッチを当てたパッケージなどは
  手元でビルドされます。署名の検証は無効にしません。

## コーディングエージェント

Claude Code と Codex は orange で Home Manager が導入し、どのシェルからでも使えます。
`~/.claude` の設定やログイン情報は基本的に Nix で管理しません。例外として
[coding-agents/](home/keewai/common/coding-agents/default.nix) が次のものを配ります。

- **スキル**：[skills/](skills/) の全ディレクトリを `~/.claude/skills/` と `~/.agents/skills/` にリンクします。
- **MCP サーバー**：`codingAgents.mcpServers.<名前> = { command; args; env; }` を、適用時に `~/.claude.json` へ書き込みます。
  Nix から外したサーバーだけを消し、手で追加したサーバーはそのまま残します。
- **Claude Code の共通指示**：[共通の UI・開発方針](home/keewai/common/coding-agents/shared-instructions.md)を
  `~/.claude/CLAUDE.md` に置きます。
- **Codex の共通指示**：[codex-instructions.md](home/keewai/common/coding-agents/codex-instructions.md) と共通の UI・開発方針を
  orange の `~/.codex/config.toml` の `developer_instructions` に設定します。
  [OpenCode の方針](https://github.com/anomalyco/opencode/blob/dev/AGENTS.md)を参考にした実装・検証の指示が、
  全プロジェクトの新しい Codex セッションで組み込み指示に追加されます。
  プロジェクト固有の `AGENTS.md` の規約を尊重し、手動の設定やログイン情報は保持します。

| スキル | 用途 |
| --- | --- |
| `ponytail` | 実装を単純に保つ（KISS / YAGNI） |
| `superpowers` | 設計・計画・デバッグ・レビューなど大きめの作業の進め方 |
| `add-nix-skill` | このリポジトリでスキルを追加・修正するとき |
| `apple-device-usb` | USB や Wi-Fi 経由で iPhone・iPad を操作 |
| `faster-whisper` | 音声・動画の文字起こし |

端末操作 GUI と `apple-device-usb` の実装は
[iphone-control](https://github.com/keewai704/iphone-control) で管理します。
このリポジトリには flake 入力、導入設定、スキルの手順を置きます。

リポジトリ専用の検証手順は [.agents/skills/nixos-validation](.agents/skills/nixos-validation/SKILL.md) にあります。

### T3 Code nightly

[T3 Code](https://github.com/pingdotgg/t3code) は、orange で Home Manager の常駐サーバーとして動きます。
公開経路と接続先は [t3code.nix](hosts/orange/services/t3code.nix)、ユーザーサービスは [t3code.nix](home/keewai/common/t3code.nix) が管理します。
公式の nightly AppImage に含まれる CLI を `t3 serve` で実行し、グラフィカルセッションには依存しません。
リリース情報は `t3code-releases` 入力で固定し、更新は `nix flake update` と通常の適用手順で行います。
アプリ内の自動更新は無効です。

- Web 画面は `https://orange.tail1e65cd.ts.net/t3/` です。
  Tailscale Serve HTTPS 443 → `127.0.0.1:8000` の nginx → `127.0.0.1:3773` のサーバーで配信し、API と WebSocket も同じ HTTPS 入口を通ります。
  `/t3/` 用に Web 画面のルーター、静的ファイル参照、PWA manifest をパッケージ内で補正します。
  ルートは Immich です。
- 起動時にサービスが始まり、既存の `~/.t3` のペアリング、プロジェクト、会話履歴を使います。
  同じ `~/.t3` に対してデスクトップ版や別の `t3 serve` を同時起動しないでください。
- 端末のペアリングは **Settings → Sharing & access** または
  `t3 auth pairing create --base-url https://orange.tail1e65cd.ts.net` を使います。
  `t3 pair --tailscale` は共通の Serve 設定を変更するため使いません。
  ペアリングのリンクは認証情報なので、ほかの人に見せないでください。
- Claude は Home Manager の実行ファイルと通常の `~/.claude` のログインを使います。必要なら
  `claude auth login` のあと、T3 Code でプロバイダーを再検出します。
- GitHub は既存の `gh` のログインを使います。`gh auth status` で確かめ、必要なら `gh auth login` のあと
  **Settings → Source Control → Rescan** を選びます。トークンを Nix にコピーすることはありません。
- T3 Code は利用者の権限でコマンドを実行できます。
  tailnet 内だけの公開でも、隔離された環境になるわけではありません。

## orange（サーバー）

外部からの Web アクセスは **Tailscale Serve（HTTPS 443）→ nginx（127.0.0.1:8000）→ 各アプリ（ループバック）** の一本道です。
アプリを LAN やすべてのアドレスに向けて公開しません。詳しい規則は [AGENTS.md](AGENTS.md#orange-web-exposure) にあります。

| サービス | URL・用途 | 設定 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich/](hosts/orange/services/immich/) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden/](hosts/orange/services/vaultwarden/) |
| T3 Code | `https://orange.tail1e65cd.ts.net/t3/` | [t3code.nix](hosts/orange/services/t3code.nix) |
| KonomiTV | `https://orange.tail1e65cd.ts.net/tv/` | [tv/](hosts/orange/services/tv/) |
| Samba | HDD の共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | Fabric サーバー | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale 出口ノード | 出口ノード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |
| 公開の経路 | nginx と Tailscale Serve | [web/](hosts/orange/services/web/) |

- 複数の機能で共有するポート・パス・URL は [settings.nix](hosts/orange/settings.nix) にまとめています。
  テレビ内部の接続先と保存先は [tv/settings.nix](hosts/orange/services/tv/settings.nix) で管理します。
- サービスの追加は [services/default.nix](hosts/orange/services/default.nix) に明示し、公開ルートは各サービスの設定に置きます。
  プロキシは [web/proxy.nix](hosts/orange/services/web/proxy.nix) を使い、ホスト・HTTPS・クライアントIPの転送を揃えます。
- Intel GPU と QSV のドライバーは [graphics.nix](hosts/orange/graphics.nix) が管理し、Immich とテレビから利用します。
- 起動の順番は「HDD のマウント → 共有ディレクトリの準備 → 既存データの取り込み → アプリ」です（[storage.nix](hosts/orange/services/storage.nix)）。
- [local-backup](hosts/orange/services/local-backup/) がバックアップ、[health-monitor](hosts/orange/services/health-monitor/) が
  15 分ごとに異常を Discord へ通知、[smart-tests](hosts/orange/services/smart-tests.nix) がディスクの診断、
  [maintenance](hosts/orange/services/maintenance.nix) がログの掃除・TRIM・Nix ストアの保守を受け持ちます。
- 各サービスが `orange.healthMonitor.units` と `loopbackPorts` に監視対象を追加します。
  T3 Code は `userUnits` で `keewai` のユーザーサービスとして、PC/SC は `pcscd.socket` の待受として確認します。
  Web 監視は Immich、Vaultwarden、T3 Code、KonomiTV の応答を確認します。
- 長いシェル処理は機能ディレクトリ内の `.sh` テンプレートに書き、`@名前@` を `fillTemplate`（[services/default.nix](hosts/orange/services/default.nix)）で
  置き換えて使います。テンプレートを直接実行しないでください。

### テレビ

構成の入口は [tv/default.nix](hosts/orange/services/tv/default.nix) です。
[edcb.nix](hosts/orange/services/tv/edcb.nix) が番組表と録画予約、
[recording.nix](hosts/orange/services/tv/recording.nix) が録画後の変換、
[konomitv.nix](hosts/orange/services/tv/konomitv.nix) が視聴画面と公開経路を管理します。

Sony CECH-ZD1 J 2台を、機器ごとの `torne-receiver` → mirakc の順に接続し、KonomiTV のライブ受信と
BonDriver_LinuxMirakc → xtne6f 版 EDCB（Linux ネイティブ）の録画で共有します。
KonomiTV は EDCB バックエンドの `always_receive_tv_from_mirakurun` を有効にし、番組情報・録画予約は EDCB、放送波は mirakc から取得します。
mirakc は [settings.nix](hosts/orange/services/tv/settings.nix) で指定したループバックポートの内部接続だけで利用します。同じ放送波は共有し、異なる2つの放送波を同時受信できます。チューナー不足の場合は EDCB の録画を優先します。
内蔵 B-CAS スロットは専用 IFD と標準 pcscd で公開し、ライブは aribb25、EDCB は B25Decoder で復号します。映像は Intel QSV で変換します。
8TB HDD 上の録画専用ディレクトリは `/srv/storage/KonomiTV/Recordings`、キャプチャは `/srv/storage/KonomiTV/Captures`、設定・番組表は
`/var/lib/edcb` と `/var/lib/konomitv` に保存します。

再視聴を速くするため、視聴終了後も配信を最大120秒保持します。
画面で240pを選ぶと、ライブ視聴・録画再生とも H.264 で配信し、端末との互換性を確保します。
携帯回線の低遅延モードは初回適用時に有効化し、その後の手動変更は維持します。
専用ドライバーは libusb で直接制御し、初期化と校正を機器ごとの常駐プロセスで保持します。機器とUSB接続位置の対応は [tuners.nix](hosts/orange/services/tv/tuners.nix)、放送局は [channels.nix](hosts/orange/services/tv/channels.nix) で管理します。レジスター書き込みは USB コマンドへまとめ、受信に成功した周波数の TMCC を再利用します。フルセグと TMCC のロックに失敗した場合は自動探索へ戻し、放送局IDを指定した受信では、PAT の整合性とIDを確認してから配信します。受信要求は機器ごとに排他制御し、切断済みの要求は選局せず破棄します。切断時にはUSB転送と待機を解除します。
[px4_drv本家](https://github.com/nns779/px4_drv) の転送・バッファ設計を参考に、8本の非同期USB転送と受信バッファでUSB受信とアプリへの送信を分離しています。
直接利用するLinuxネイティブのBonDriver2は `/var/lib/edcb/lib/BonDriver_Torne0.so` と `BonDriver_Torne1.so` です。`CreateBonDriver` と EDCB の `CreateBonStruct` を公開し、選局、信号レベル、TS取得・待機・消去、開閉に対応します。同名の `.so.ini` で制御ソケットと放送局一覧を指定します。設定を省く場合は1台目のソケットとUHF 13〜62chを使います。
自動録画では `BonDriver_LinuxMirakc.so` の2枠を利用し、KonomiTVとの共有を維持します。直接BonDriverとmirakcは同一機器を同時には占有できません。直接利用するアプリは `tv` グループで実行してください。`keewai` のグループ追加を既存ログインへ反映するには再ログインが必要です。
NHK総合の京都・神戸とサンテレビ2は、EDCB の表示・EPG取得・検索を無効にし、KonomiTV の一覧にも反映します。

今後の録画は EDCB の `PostRecEnd.lua` からキューへ登録し、[録画処理](hosts/orange/services/tv/recording/default.nix)が AmatsukazeCLI と QSVEncC で映像を H.265 に変換し、tsreplace で元 TS の映像だけを置換します。
音声・字幕・番組情報・データ放送などの非映像パケットを PID ごとの件数と SHA256 で比較し、PMT の非映像情報、映像の全体デコードとフレーム時刻も検証します。
インターレース映像は CPU 版 KFM で24p・30p・60pの区間を判別し、逆テレシネとインターレース解除を切り替えた可変フレームレートで出力します。プログレッシブ映像はインターレース解除を省きます。変換後の各フレームの時刻が TS への置換で変わっていないことも確認します。
Amatsukaze の入力解析では末尾 PES の境界で数フレームの差が出るため、元映像との末尾差は最大3入力フレームまで許容し、完了 JSON の `source_tail_difference_ms` に記録します。途中の時刻欠落と、変換済み映像の TS 置換時のフレーム欠落は拒否します。
初回に局ロゴを自動検出・生成し、サービスIDと解像度ごとに `/var/lib/tv-recording/logos` へ保存します。以後はそのロゴを利用して CM解析とロゴ消しを行います。ロゴを生成できない初回録画は元 TS を残して失敗扱いにします。登録済みロゴが表示されない区間はロゴを消さずに処理を続けます。
CM は残し、解析結果を録画と同じ場所の `<録画名>.chapter.txt` に保存します。解析で区切りが見つからない場合も、先頭に「本編」チャプターを作成します。映像や音声の形式変更により複数ファイルへ分割される場合は、元 TS を残します。一時データは `/var/cache/tv-recording/work` に置きます。
映像の符号化方式を示す PMT と、必要な場合の PCR 配置は更新します。検証成功後に同じファイル名へ置換し、元 TS を削除します。
失敗時は元 TS を残し、ジョブを `/var/lib/tv-recording/failed`、ログを `/var/log/tv-recording` に保存します。既存録画の一括変換は行いません。

torne_drv・mirakc・mirakc-arib・BonDriver・EDCB・B25Decoder・tsreplace・Amatsukaze・KonomiTV と配布バイナリは [flake.nix](flake.nix) の入力で管理します。
mirakc は上流の `release` ブランチを追います。
KonomiTV は `master`、対応するバイナリは上流の nightly 配布を追います。
更新は `nix flake update` と通常の Orange への適用で行い、ソースの revision と配布物の hash は `flake.lock` に残します。
Rust と Python の依存は取得元のロックから構築します。専用ドライバーは GPL-2.0 の torne_drv の中核を基に C で実装し、coax の実行・ビルド依存はありません。

## パッケージと入力の方針

- [pkgs/default.nix](pkgs/default.nix) に並べたパッケージは、設定から `pkgs.local.<名前>` で参照でき、
  `nix build .#<名前>` で単体ビルドもできます。パッチは対象パッケージのディレクトリに置きます。
- 更新の入口は `nix flake update` にそろえます。再現性のための revision と hash は `flake.lock` に残します。
- orange の Minecraft とその MOD は、バージョンやハッシュを手で管理しているため、
  `nix flake update` だけでは更新できません。
- 非自由パッケージは全体で許可しています（`allowUnfree = true`）。
- `system.stateVersion` と `home.stateVersion` は互換性の基準なので、アップデートに合わせて変えません。
