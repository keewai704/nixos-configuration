# nixos-configuration

`citrus`、`citrus-vm`、`orange` の NixOS 設定を管理するリポジトリです。
3 台とも `x86_64-linux` で、機器・OS の設定は NixOS、個人のアプリと設定は Home Manager が担当します。

## 読み方

知りたいことから、次の節へ進んでください。

- [設定の読み順とホストの違い](#設定の読み順とホストの違い)
- [ディレクトリと Nix の基本](#ディレクトリの役割)
- [変更したい内容から探す](#変更したい内容から探す)
- [Codex・MCP・スキルの編集先](#codexmcpスキル)
- [Orange のサービスと保存先](#orange-のサービスを読む)
- [独自パッケージと音楽クライアントの実装](#パッケージの独自変更)
- [検証とローカル適用](#適用せずに設定を確認する)
- [アプリの使い方と開発環境](#アプリの使い方と開発環境)

## 設定の読み順とホストの違い

1. [flake.nix](flake.nix) で、外部の依存関係と各ホストの入口を確認します。
   入力の名前と取得元は `inputs`、このリポジトリが提供する設定・パッケージは `outputs` にあります。
2. 対象ホストの `default.nix` を開き、`imports` をたどります。
3. アプリや操作環境を変える場合は、[home/keewai/common.nix](home/keewai/common.nix) と
   [デスクトップ設定の入口](home/keewai/desktop/default.nix) を確認します。
4. 変更前に [AGENTS.md](AGENTS.md) の検証・コミット・ローカル適用の手順を読みます。

| ホスト | 用途 | 設定の入口 |
| --- | --- | --- |
| `citrus` | Hyprland を使う実機デスクトップ | [hosts/citrus/default.nix](hosts/citrus/default.nix) |
| `citrus-vm` | Citrus のデスクトップを使う Hyper-V 仮想マシン | [hosts/citrus-vm/default.nix](hosts/citrus-vm/default.nix) |
| `orange` | ストレージ、写真、パスワード管理、Minecraft を提供するサーバー | [hosts/orange/default.nix](hosts/orange/default.nix) |

全ホストに [modules/common.nix](modules/common.nix) と
[modules/home-manager.nix](modules/home-manager.nix) が読み込まれます。
前者はネットワークやユーザーなどの共通 OS 設定、後者は Home Manager と NixOS の接続を担当します。

`citrus-vm` は `citrus` の設定を読み込んでから、実機のハードウェア設定を無効化し、
VM 用のカーネル・起動方法・描画設定に置き換えます。
Citrus の変更が VM にも届くことに注意してください。

設定は次の順に合流します。`imports` は別の設定を読み込む入口です。

```text
flake.nix
├── 全ホスト: modules/common.nix
│   └── Codex・ログインシェルなどの共通 OS 設定
├── 全ホスト: modules/home-manager.nix
│   └── home/keewai/common.nix → shared/ の個人設定
└── 各ホスト: hosts/<host>/default.nix
    ├── citrus → 機器設定 + modules/desktop.nix → home/keewai/desktop/
    ├── citrus-vm → citrus を継承 + VM 用の上書き
    └── orange → ストレージとサーバーサービス
```

## ディレクトリの役割

| 場所 | 管理するもの |
| --- | --- |
| [flake.nix](flake.nix) / [flake.lock](flake.lock) | 外部入力、固定したバージョン、ホスト・パッケージ・開発環境の公開 |
| [modules/](modules/) | 複数ホストで共有する NixOS の機能と統合 |
| [hosts/](hosts/) | ホスト固有のハードウェア、サービス、起動設定 |
| [home/keewai/shared/](home/keewai/shared/) | 全ホストで使う個人の CLI、シェル、エディター、Codex |
| [home/keewai/desktop/](home/keewai/desktop/) | デスクトップ用アプリ、キー操作、ユーザーサービス、表示設定 |
| [pkgs/](pkgs/) | パッケージのビルド定義、パッチ、実行時に必要な補助コード |
| [themes/](themes/) | NixOS と Home Manager が共有する色、フォント、画像 |
| [skills/](skills/) | Nix で配布する個人用 Codex スキルの編集元 |
| [secrets/](secrets/) | Agenix の公開鍵設定と暗号化済みシークレット |
| [devshell/](devshell/) | このリポジトリを編集するための開発環境 |

`default.nix` は、そのディレクトリの入口です。NixOS・Home Manager の入口では
`imports` に機能別のファイルを並べ、個々の設定をそのファイルに置きます。
`pkgs/<名前>/default.nix` は、そのパッケージの作り方を定義します。

Nix に慣れていない場合は、まず次の構文が分かれば読み進められます。

| 書き方 | 読み方 |
| --- | --- |
| `{ pkgs, lib, ... }:` | 呼び出し元から受け取る値。`pkgs` はパッケージ、`lib` は設定用の関数 |
| `let 名前 = 値; in ...` | 後ろの設定で使う値に名前を付ける |
| `imports = [ ./名前.nix ];` | 別ファイルの設定を読み込んで合流する |
| `名前 = { ... };` / `[ ... ]` | 名前付きの値のまとまり / 順序のある一覧 |
| `${...}` | 値を文字列へ埋め込む |
| `inherit 名前;` | 同名の値を引き渡す。`名前 = 名前;` と同じ |
| `lib.mkIf 条件 { ... }` | 条件が成立する場合に設定を有効にする |
| `lib.mkDefault 値` / `lib.mkForce 値` | 上書き可能な既定値 / 通常の設定より優先する値 |
| `左 ++ 右` / `左 // 右` | 一覧を連結する / 属性を合わせ、同じ名前には右側の値を使う |
| `pkgs.callPackage ./名前 { ... }` | パッケージ定義に必要な依存関係を渡す |

VM の設定は、継承元と `mkForce` などの優先順位を合わせて読みます。
`system.stateVersion` と `home.stateVersion` は互換性の基準です。
パッケージの更新日を示すものではないため、入力の更新に合わせて変更しません。

## 変更したい内容から探す

| 変更したい内容 | 主な編集先 |
| --- | --- |
| 全ホストの OS 設定 | [modules/common.nix](modules/common.nix) |
| 全ホストで使う CLI | [home/keewai/common.nix](home/keewai/common.nix) |
| シェル、補完、プロンプト | [shared/shell.nix](home/keewai/shared/shell.nix)、[starship.toml](home/keewai/shared/starship.toml) |
| エディターとプラグイン | [shared/neovim.nix](home/keewai/shared/neovim.nix)、[neovim.lua](home/keewai/shared/neovim.lua) |
| 設定を伴わないデスクトップ用ツール | [desktop/applications.nix](home/keewai/desktop/applications.nix) |
| ウィンドウ、モニター、キー操作 | [desktop/hyprland.lua](home/keewai/desktop/hyprland.lua) |
| Hyprland のログイン・ポータル統合 | [hosts/citrus/hyprland.nix](hosts/citrus/hyprland.nix) |
| 画面ロックとアイドル時の動作 | [desktop/screen-lock.nix](home/keewai/desktop/screen-lock.nix) |
| 日本語入力 | [desktop/input-method.nix](home/keewai/desktop/input-method.nix) |
| 端末 | [desktop/kitty.nix](home/keewai/desktop/kitty.nix) |
| ブラウザーと既定の URL ハンドラー | [desktop/browser.nix](home/keewai/desktop/browser.nix)、[firefox.nix](home/keewai/desktop/firefox.nix) |
| ファイル管理、圧縮、XDG フォルダー | [desktop/file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Bitwarden と SSH エージェント | [desktop/bitwarden.nix](home/keewai/desktop/bitwarden.nix) |
| デスクトップのパネルとランチャー | [desktop/dynamic-island.nix](home/keewai/desktop/dynamic-island.nix) |
| Discord クライアントとテーマ | [desktop/legcord.nix](home/keewai/desktop/legcord.nix)、[legcord-system24.nix](home/keewai/desktop/legcord-system24.nix) |
| Steam と Millennium | [hosts/citrus/steam.nix](hosts/citrus/steam.nix)、[desktop/steam-theme.nix](home/keewai/desktop/steam-theme.nix) |
| 共通の色、フォント、壁紙 | [themes/tokyo-night-black/default.nix](themes/tokyo-night-black/default.nix) |
| VM の描画 | [hosts/citrus-vm/graphics.nix](hosts/citrus-vm/graphics.nix)、[desktop/hyperv-rendering.nix](home/keewai/desktop/hyperv-rendering.nix) |
| Hyper-V イメージ | [hosts/citrus-vm/image.nix](hosts/citrus-vm/image.nix) |
| Orange の保存先、ポート、URL | [hosts/orange/settings.nix](hosts/orange/settings.nix) |

個人のアプリには、まず Home Manager の `programs.*` / `services.*` を使います。
対応モジュールが必要な動作を満たさない場合は `home.packages` に置きます。
ログイン、PAM、ドライバー、USB のアクセス権、システムデーモンなどは NixOS 側で管理します。

たとえば、Hyprlock の見た目と起動は Home Manager、認証に必要な PAM は
[modules/hyprlock.nix](modules/hyprlock.nix) にあります。
Apple USB CLI は [shared/apple-device-usb.nix](home/keewai/shared/apple-device-usb.nix)、
実機の usbmuxd は [hosts/citrus/apple-device-usb.nix](hosts/citrus/apple-device-usb.nix) が担当します。
指紋認証は fprintd が有効な環境でだけ使います。

Home Manager は `useUserPackages = true` で NixOS に統合されています。
ユーザーのパッケージは `/etc/profiles/per-user/keewai` に入り、適用には NixOS の再構築を使います。
パッケージの所有場所を変えても、アプリの実行権限やサンドボックスは変わりません。

## Codex・MCP・スキル

| 場所 | 役割 |
| --- | --- |
| [modules/codex.nix](modules/codex.nix) | モデル、共通指示、MCP 設定の Codex 形式への変換 |
| [modules/codex-ponytail.nix](modules/codex-ponytail.nix) | Ponytail のフックとシステムスキルの配布 |
| [shared/codex.nix](home/keewai/shared/codex.nix) | 固定した Codex CLI の導入と、ユーザー設定に残った管理対象の上書きの除去 |
| [shared/codex-remote.nix](home/keewai/shared/codex-remote.nix) | 認証付き Remote Control のユーザーサービス |
| [shared/paseo.nix](home/keewai/shared/paseo.nix) | Paseo の CLI、Web UI、Codex 接続とユーザーサービス |
| [modules/codex-remote.nix](modules/codex-remote.nix) | ログイン前にもユーザーサービスを起動するための linger |
| [desktop/codex.nix](home/keewai/desktop/codex.nix) | デスクトップアプリと `codex:` URL ハンドラー |
| [shared/mcp.nix](home/keewai/shared/mcp.nix) | 全ホストで使う MCP サーバー |
| [desktop/cua.nix](home/keewai/desktop/cua.nix) | デスクトップ操作用ドライバーと MCP |
| [shared/skills.nix](home/keewai/shared/skills.nix) | 個人スキルの公開と配布対象の選別 |

Codex CLI は固定した `sadjow/codex-cli-nix` 入力から導入します。
設定を変える場合は、このリポジトリの編集元を変更してください。
生成先の `/etc/codex` や `/home/keewai/.agents/skills` は直接編集しません。
Ponytail は `/etc/codex/skills/ponytail`、配布対象の個人スキルは `~/.agents/skills` に配置されます。
`skills/luna-delegation` は配布対象から外れており、現在の共通指示はサブエージェントを使わない設定です。

## Orange のサービスを読む

各サービスは [settings.nix](hosts/orange/settings.nix) を直接読みます。
`flake.nix` からホスト専用の値を暗黙に注入する構成ではありません。

Web の入口は Tailscale Serve の HTTPS 443 です。
そこからループバックの nginx（`127.0.0.1:8000`）を経由して、アプリへ転送します。
設定は [web.nix](hosts/orange/services/web.nix) にまとめています。

| サービス | アクセス先・用途 | 編集先 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich.nix](hosts/orange/services/immich.nix) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden.nix](hosts/orange/services/vaultwarden.nix) |
| Samba | HDD の共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | LAN・tailnet 向け Fabric サーバー | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale Exit Node | 経路と UDP オフロード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |

ストレージの起動順序は、HDD のマウント、共有ディレクトリの準備、既存データの取り込み、
アプリ起動の順です。[storage.nix](hosts/orange/services/storage.nix) がマウントと準備を担当し、
各アプリのファイル権限と取り込み条件はアプリ側で管理します。

長い実行処理は、サービス設定の隣のシェルファイルに置いています。
Nix ファイルを読むと依存関係・権限・起動条件がわかり、シェルファイルを読むと処理の順番がわかります。
シェル内の `@名前@` は、対応する Nix ファイルの `scriptReplacements` で置き換えます。
これらのシェルファイルはサービス用のテンプレートなので、直接実行するものではありません。

| 処理 | サービス設定 | 実行処理 |
| --- | --- | --- |
| Immich の既存 DB 取り込み | [immich.nix](hosts/orange/services/immich.nix) | [import-immich-database.sh](hosts/orange/services/import-immich-database.sh) |
| Vaultwarden の既存データ取り込み | [vaultwarden.nix](hosts/orange/services/vaultwarden.nix) | [import-vaultwarden-data.sh](hosts/orange/services/import-vaultwarden-data.sh) |
| バックアップの世代保存 | [local-backup.nix](hosts/orange/services/local-backup.nix) | [local-backup.sh](hosts/orange/services/local-backup.sh) |
| 異常検出と通知 | [health-monitor.nix](hosts/orange/services/health-monitor.nix) | [health-monitor.sh](hosts/orange/services/health-monitor.sh) |

監視は 15 分間隔で実行し、新しい異常を検出したときに Discord へ通知します。
同じ異常を毎回通知しないよう、通知済みの状態を保存します。
監視内容は [health-monitor.sh](hosts/orange/services/health-monitor.sh) の末尾の `main` から読めます。
サービス、保存領域、ドライブ、メモリー、温度、ログ、時刻、通信、バックアップ、カーネルの順に確認し、
終了時の `finish_and_notify` が新しい異常をまとめて通知します。
[smart-tests.nix](hosts/orange/services/smart-tests.nix) はドライブの定期自己診断、
[maintenance.nix](hosts/orange/services/maintenance.nix) はログ掃除・TRIM・Nix Store の保守を担当します。

## パッケージの独自変更

[pkgs/default.nix](pkgs/default.nix) は `nix build .#<名前>` で公開するパッケージの一覧です。
ホスト内だけで使うパッケージは、その機能の設定から `callPackage` で読み込みます。

| ディレクトリ | 独自変更の目的 |
| --- | --- |
| [aquamarine-hyperv/](pkgs/aquamarine-hyperv/) | Hyper-V 用の描画対応 |
| [brave-origin/](pkgs/brave-origin/) | Brave Origin のバージョン選択と日本語設定 |
| [chatgpt-desktop/](pkgs/chatgpt-desktop/) | 公式 Linux 配布物の NixOS 対応、起動処理、ASAR のパッチ |
| [cua-driver/](pkgs/cua-driver/) | デスクトップ操作用ドライバーの実行環境 |
| [fprintd-cs9711/](pkgs/fprintd-cs9711/) | CS9711 指紋センサーと認証キャンセルの修正 |
| [hyprland/](pkgs/hyprland/) | 入力メソッドの修飾キー処理の修正 |
| [hyprpaper-shm/](pkgs/hyprpaper-shm/) | VM 用の壁紙描画と旧 IPC の橋渡し |
| [paseo/](pkgs/paseo/) | 配布パッケージで欠落する node-pty のネイティブ部品を同じ固定バージョンから補完 |
| [ponytail-hooks/](pkgs/ponytail-hooks/) | Ponytail の管理用フック |

パッチは対象パッケージと同じディレクトリに置きます。
上流を更新するときは、パッチの前提と付属のテストも確認してください。
`keewai704` 所有の GitHub 入力は `main` ブランチを明示し、リビジョンとハッシュを固定します。

### Apple Music クライアント

Apple Music クライアントの実装、Nix パッケージ、Home Manager モジュールは
[keewai704/siora](https://github.com/keewai704/siora) で管理します。
このリポジトリでは [apple-music.nix](home/keewai/desktop/apple-music.nix) からそのモジュールを取り込みます。

## 適用せずに設定を確認する

次の例は、リポジトリのルートで、現在のホストの設定だけを評価・ビルドします。
ホスト名が一致しない場合は終了します。別のホスト名で代用しません。

```sh
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
configured_host="$(cat /etc/hostname)"
test "$runtime_host" = "$configured_host" || exit 1

flake_host="$(nix eval --raw --no-write-lock-file \
  ".#nixosConfigurations.$runtime_host.config.networking.hostName")" || exit 1
test "$runtime_host" = "$flake_host" || exit 1

nix build ".#nixosConfigurations.$runtime_host.config.system.build.toplevel" \
  --no-link --no-write-lock-file
```

全体の出力を確認するには `nix flake show --no-write-lock-file` を使います。
変更時の必須チェックは [AGENTS.md](AGENTS.md) の対象表から選びます。
設定変更を実機へ適用する場合は、コミット後に現在のホストで `test`、稼働確認、
`switch`、再確認の順に進めます。別ホストへの接続・適用は、その操作の明示的な依頼がある場合に限ります。

## アプリの使い方と開発環境

日常操作を確認するときに開いてください。構成や編集先は上の一覧からたどれます。

<details>
<summary>Paseo で Codex を使う</summary>

Paseo はユーザーサービスとして起動します。ブラウザーで
[ローカルの Web UI](http://127.0.0.1:6767) を開き、プロバイダーに Codex を選びます。
既存の Codex CLI と `~/.codex` の認証を使います。未認証のホストでは `codex login` を実行してください。
CLI では作業ディレクトリから `paseo run --provider codex "依頼内容"` で開始できます。

状態確認は `systemctl --user status paseo`、再起動は `systemctl --user restart paseo`、
Codex の検出確認は `paseo provider diagnostic codex` を使います。
`~/.paseo/config.json` は Home Manager が管理するため、接続設定は
[shared/paseo.nix](home/keewai/shared/paseo.nix) で変更します。
待受けはループバックだけで、リレーは無効です。別ホストへの適用と端末のペアリングは個別に行います。
音声機能は無効にしており、音声モデルの自動ダウンロードは行いません。

</details>

<details>
<summary>Apple Music（Siora）の操作と認証</summary>

### Apple Music（Siora）

`siora` でネイティブアプリを起動します。
認証には Apple Music 3.6.0-beta（1109）の x86_64 ライブラリを
`alac-room-auth-import /path/to/apple-music.apkm` で取り込みます。
既定の配置先は `~/.local/share/alac-room/auth/rootfs` です。
認証データの配置先を変える場合は `ALAC_ROOM_AUTH_DATA_DIR` を設定します。
APK 由来のライブラリは再配布せず、各ユーザーが所有する APK からこの場所へ取り込みます。

</details>

<details>
<summary>ブラウザーと日本語設定</summary>

### ブラウザー

既定の URL・HTML ハンドラーは Firefox です。Brave Origin も Home Manager で管理します。
Firefox は固定した `keewai704/my-firefox-nix` の `main` を利用し、Sine/Natsumi、
日本語化、Bitwarden/uBlock Origin のポリシーを引き継ぎます。
設定は AutoConfig で固定し、最初の適用時にプロフィールを準備してから Sine を配置します。
Firefox の見た目は Sine/Natsumi が担当するため、Stylix の Firefox 対応は無効です。
この非公開入力の取得には GitHub の読み取り認証が必要です。

</details>

<details>
<summary>Neovim の操作と開発環境</summary>

### Neovim と開発環境

全ホストで `nvim`、`vim`、`vi` が利用でき、新しいセッションでは `EDITOR` と `VISUAL` にも設定されます。
一般の編集設定は [shared/neovim.lua](home/keewai/shared/neovim.lua)、
Nix で固定するプラグインは [shared/neovim.nix](home/keewai/shared/neovim.nix) にあります。
`lazy.nvim` の管理画面は `:Lazy` で開きます。プラグインと Tree-sitter のパーサーは
Nix で導入するため、初回起動時のダウンロードは不要です。
更新は Nixpkgs の固定バージョンを変更して行い、パーサーの追加は `neovim.nix` で行います。
Wayland のクリップボード連携も含みます。

```sh
nix develop --no-write-lock-file
nvim flake.nix
```

開発環境には Nix・Lua・Bash の言語サーバー、フォーマッター、静的解析ツールが入っています。
[devshell/neovim.lua](devshell/neovim.lua) が共通のエディター設定に補完・診断・定義移動を追加します。
`NVIM_PROJECT_CONFIG` に設定された信頼できる Lua ファイルだけを追加で読み込みます。
開発環境の外で起動した Neovim には共通設定が適用されます。
拡張設定を変更したら `nix develop` に入り直してください。

nixd は編集中の flake が固定した Nixpkgs と現在のホスト名を使い、NixOS と Home Manager の設定候補を表示します。
別ホストの候補を調べる場合は、Neovim 起動前に `NVIM_NIXOS_HOST=orange` などを指定します。
これは補完対象の選択であり、そのホストへの接続・適用は行いません。
Zsh には一般の編集と構文強調を使い、Bash 専用の診断・整形は適用しません。
statix と deadnix はコマンドとして利用できます。

画面は絶対行番号、ファイル一覧、開いているファイルのタブ、フローティング端末を備えます。
作業ディレクトリと Git ブランチごとに開いたファイルとウィンドウ配置を終了時に保存し、復元は手動で行います。
ホーム画面からファイル検索・最近のファイル・作業の復元・ヘルプへ移動できます。
言語サーバーがない環境でも、編集中のテキストを使った補完が動作します。

| キー | 操作 |
| --- | --- |
| `Space ff` / `Space fg` | ファイル検索 / 内容検索 |
| `Space fb` / `Space fh` / `Space fr` | 開いているファイル / ヘルプ / 最近のファイル |
| `Space e` / `Space h` / `Space ?` | ファイル一覧 / ホーム画面 / キーガイド |
| `Space t` または `Ctrl-\` | 端末の表示切り替え |
| 端末内の `Esc Esc` | 端末入力モードを終了 |
| `[b` / `]b` / `Space bd` | 前のファイル / 次のファイル / 閉じる |
| `Space ws` / `Space wv` / `Space wc` | 上下分割 / 左右分割 / ウィンドウを閉じる |
| `Space sr` / `Space ss` / `Space sd` | 作業を復元 / 保存済み作業を選択 / 今回の保存を停止 |
| `Space gd` / `Space gg` | Git 差分の表示 / 状態の表示 |
| `Space gc` / `Space ge` | Git 履歴 / 変更ファイル一覧 |
| `Space l` | プラグイン管理 |
| `Space cf` | フォーマッターがある場合にファイル・選択範囲を整形 |
| `Space cd` / `Space cq` | 診断を表示 / 診断一覧 |
| `Space xx` / `Space xb` / `Space cs` | 作業全体の診断 / ファイルの診断 / シンボル一覧 |
| `gd` / `gr` / `K` | 定義 / 参照 / 説明（言語サーバー接続時） |
| `Space cr` / `Space ca` | 名前変更 / コードアクション（言語サーバー接続時） |
| `gcc` / 選択中の `gc` | コメントの切り替え |
| 選択中の `Alt-h/j/k/l` | 選択したテキストの移動 |
| 選択中の `ga` / `gS` | 整列 / 引数リストの分割・結合 |
| `Ctrl-n` / `Ctrl-p` / `Ctrl-y` | 次の補完候補 / 前の候補 / 確定 |

ファイル一覧では `Enter` で開き、`a` / `A` でファイル / ディレクトリを作成します。
`r` は名前変更、`y` / `x` の後に `p` でコピー / 移動、`d` は削除、
`H` は隠しファイルの表示切り替え、`?` は操作ガイドです。

</details>
