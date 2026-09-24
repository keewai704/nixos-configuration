# nixos-configuration

`citrus`、`orange` の NixOS 設定を管理するリポジトリです。
2 台とも `x86_64-linux` で、機器・OS の設定は NixOS、個人のアプリと設定は Home Manager が担当します。

## 読み方

知りたいことから、次の節へ進んでください。

- [設定の読み順とホストの違い](#設定の読み順とホストの違い)
- [ディレクトリと Nix の基本](#ディレクトリの役割)
- [変更したい内容から探す](#変更したい内容から探す)
- [Pi・MCP・スキルの編集先](#pimcpスキル)
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
| `orange` | ストレージ、写真、パスワード管理、Minecraft を提供するサーバー | [hosts/orange/default.nix](hosts/orange/default.nix) |

全ホストに [modules/common.nix](modules/common.nix) と
[modules/home-manager.nix](modules/home-manager.nix) が読み込まれます。
前者はネットワークやユーザーなどの共通 OS 設定、後者は Home Manager と NixOS の接続を担当します。
ブートローダーとカーネルの選択は各ホストの `boot.nix` に置きます。
[modules/desktop.nix](modules/desktop.nix) は dconf、キーリング、ファイル管理のシステム連携、
スケジューラーと共通のデスクトッププロフィールをまとめます。
Hyprland の独自パッケージとログイン・ポータル統合は [hosts/citrus/hyprland.nix](hosts/citrus/hyprland.nix) が担当します。

設定は次の順に合流します。`imports` は別の設定を読み込む入口です。

```text
flake.nix
├── 全ホスト: modules/common.nix
│   └── ユーザーサービスの linger・ログインシェルなどの共通 OS 設定
├── 全ホスト: modules/home-manager.nix
│   └── home/keewai/common.nix → shared/ の個人設定
└── 各ホスト: hosts/<host>/default.nix
    ├── citrus → 機器設定 + modules/desktop.nix → home/keewai/desktop/
    └── orange → ストレージとサーバーサービス
```

## ディレクトリの役割

| 場所 | 管理するもの |
| --- | --- |
| [flake.nix](flake.nix) / [flake.lock](flake.lock) | 外部入力、固定したバージョン、ホスト・パッケージ・開発環境の公開 |
| [modules/](modules/) | 複数ホストで共有する NixOS の機能と統合 |
| [hosts/](hosts/) | ホスト固有のハードウェア、サービス、起動設定 |
| [home/keewai/shared/](home/keewai/shared/) | 全ホストで使う個人の CLI、シェル、Pi |
| [home/keewai/desktop/](home/keewai/desktop/) | デスクトップ用アプリ、キー操作、ユーザーサービス、表示設定 |
| [pkgs/](pkgs/) | パッケージのビルド定義、パッチ、実行時に必要な補助コード |
| [themes/](themes/) | NixOS と Home Manager が共有する色、フォント、画像 |
| [skills/](skills/) | Nix で配布する個人用 Pi スキルの編集元 |
| [.agents/skills/](.agents/skills/) | このリポジトリ専用の Pi スキル |
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

`system.stateVersion` と `home.stateVersion` は互換性の基準です。
パッケージの更新日を示すものではないため、入力の更新に合わせて変更しません。

## 変更したい内容から探す

| 変更したい内容 | 主な編集先 |
| --- | --- |
| 全ホストの OS 設定 | [modules/common.nix](modules/common.nix) |
| 全ホストで使う CLI | [home/keewai/common.nix](home/keewai/common.nix) |
| シェル、補完、プロンプト | [shared/shell.nix](home/keewai/shared/shell.nix)、[starship.toml](home/keewai/shared/starship.toml) |
| 設定を伴わないデスクトップ用ツール | [desktop/applications.nix](home/keewai/desktop/applications.nix) |
| ウィンドウ、モニター、キー操作 | [desktop/hyprland.lua](home/keewai/desktop/hyprland.lua) |
| Hyprland のパッケージ・ログイン・ポータル統合 | [hosts/citrus/hyprland.nix](hosts/citrus/hyprland.nix) |
| 画面ロック、メディア表示、アイドル時の動作 | [desktop/noctalia.nix](home/keewai/desktop/noctalia.nix) |
| 日本語入力と切り替えキー | [desktop/input-method.nix](home/keewai/desktop/input-method.nix)、[modules/input-method-shortcut.nix](modules/input-method-shortcut.nix) |
| 端末 | [desktop/kitty.nix](home/keewai/desktop/kitty.nix) |
| ブラウザーと既定の URL ハンドラー | [desktop/browser.nix](home/keewai/desktop/browser.nix)、[firefox.nix](home/keewai/desktop/firefox.nix) |
| ファイル管理、圧縮、XDG フォルダー | [desktop/file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Bitwarden と SSH エージェント | [desktop/bitwarden.nix](home/keewai/desktop/bitwarden.nix) |
| デスクトップのパネル、ランチャー、アプリの配色 | [desktop/noctalia.nix](home/keewai/desktop/noctalia.nix) |
| Discord クライアントとテーマ | [desktop/legcord.nix](home/keewai/desktop/legcord.nix)、[legcord-system24.nix](home/keewai/desktop/legcord-system24.nix) |
| Steam と Millennium | [hosts/citrus/steam.nix](hosts/citrus/steam.nix)、[desktop/steam-theme.nix](home/keewai/desktop/steam-theme.nix) |
| Sunshine 配信と仮想画面 | [hosts/citrus/sunshine.nix](hosts/citrus/sunshine.nix)、[sunshine-display](pkgs/sunshine-display/) |
| 共通の色、フォント、壁紙 | [themes/tokyo-night-black/default.nix](themes/tokyo-night-black/default.nix) |
| Orange の保存先、ポート、URL | [hosts/orange/settings.nix](hosts/orange/settings.nix) |

個人のアプリには、まず Home Manager の `programs.*` / `services.*` を使います。
対応モジュールが必要な動作を満たさない場合は `home.packages` に置きます。
ログイン、PAM、ドライバー、USB のアクセス権、システムデーモンなどは NixOS 側で管理します。

たとえば、Noctalia の見た目と起動は Home Manager、電源管理と I²C アクセスは
[hosts/citrus/noctalia.nix](hosts/citrus/noctalia.nix) が担当します。
Apple USB CLI は [shared/apple-device-usb.nix](home/keewai/shared/apple-device-usb.nix)、
実機の usbmuxd は [hosts/citrus/apple-device-usb.nix](hosts/citrus/apple-device-usb.nix) が担当します。
指紋認証は fprintd が有効な環境でだけ使います。

パネル、ランチャー、通知、クリップボード、壁紙、認証ダイアログ、ロックとアイドル制御は
nixpkgs の [Noctalia v5](https://docs.noctalia.dev/noctalia/) が管理します。
Sunshine 配信のため画面ロックは無効です。起動時・アイドル時・サスペンド前のロックとロック用キーは無効にし、
Noctalia のロック画面・ロック操作も無効にしています。アイドル 660 秒での画面消灯は維持します。
無人時もデスクトップへアクセスできるため、端末とペアリング済みクライアントの管理に注意してください。
GTK・Qt・Kitty・Hyprland の配色は Noctalia のテンプレートを優先し、対応する Stylix の配色は無効です。
Home Manager はテンプレートの読み込み先を宣言し、生成される色ファイルは Noctalia が更新します。
Stylix はフォント・カーソル・アイコン、起動時の表示と未対応アプリの設定に残します。
Bitwarden のデスクトップアプリ・SSH エージェント・rbw の初期設定は `desktop/bitwarden.nix` が担当します。
rbw の初回利用時は `rbw config set email <メールアドレス>`、`rbw login`、`rbw unlock`、`rbw sync` を実行します。
公式 Bitwarden サーバーに変更した場合は、ログイン前に `rbw register` で個人 API キーによる端末登録が必要です。
Noctalia の標準ランチャーには、旧 Dynamic Island の `bw <項目名>` による Bitwarden 検索・コピー・セットアップ機能はありません。rbw は端末から使用します。
キー操作は `desktop/hyprland.lua` にあり、`Super+,` で Noctalia 設定を開けます。

Home Manager は `useUserPackages = true` で NixOS に統合されています。
ユーザーのパッケージは `/etc/profiles/per-user/keewai` に入り、適用には NixOS の再構築を使います。
パッケージの所有場所を変えても、アプリの実行権限やサンドボックスは変わりません。

### citrus の Sunshine 配信

Sunshine は Hyprland セッションで起動し、物理モニターがなくても `SUNSHINE` 仮想画面を
NVENC で配信します。入力用の uinput・udev と Avahi の統合は NixOS モジュール、
Moonlight クライアントのインストールは Home Manager が担当します。
管理画面は citrus 上の `https://localhost:47990` からのみ利用でき、UPnP は無効です。
Moonlight には LAN の citrus または Tailscale の citrus アドレスを追加してペアリングします。

| アプリ | 動作 |
| --- | --- |
| `Extend Display` | 既存画面の右に仮想画面を配置 |
| `Steam Big Picture` | クライアントのみの表示に切り替え、Steam Big Picture を起動 |
| `Client Only` | 他の画面を無効にして仮想画面だけに表示 |

解像度とリフレッシュレートは接続時のクライアント設定に合わせます。
HDR は有効にせず、まず 1920×1080・60 FPS・20 Mbps を測定の出発点にします。
120 Hz 対応クライアントでは、1080p・120 FPS・40 Mbps・H.264・ハードウェアデコード、
V-Sync とフレームペーシング無効を低遅延候補にできます。ティアリングが気になる場合は V-Sync を戻します。
Moonlight の CLI では `moonlight stream citrus "Extend Display" --1080 --fps 120 --bitrate 40000 --video-codec H.264 --video-decoder hardware --no-vsync --no-frame-pacing --no-hdr` で指定できます。
2026-09-21 の citrus 内 Moonlight/Weston ループバック測定では、描画 59.94 → 119.87 FPS、
ホスト処理平均 2.2 → 2.2 ms、デコード平均 0.28 → 0.06 ms、ネットワーク欠落はいずれも 0% でした。
これは合成映像・同一 GPU の測定で、外部端末や LAN/Wi-Fi、ゲーム負荷時の性能は保証しません。
単なる切断ではアプリが継続するため、画面を戻すときは Moonlight の「アプリを終了」を使います。
サービス停止時にも復元処理が走ります。サービス稼働中は仮想画面を維持します。
終了時は Hyprland の設定を再読み込みして、宣言済みの画面設定と接続中の画面のワークスペース配置を戻します。
途中で取り外した画面は、再接続時に宣言済みの設定を使います。その画面の以前のワークスペース配置や電源状態は復元できません。
一時的な `hyprctl` の設定変更は再読み込みにより解除されます。
`SUNSHINE` はサービス専用の予約出力名です。稼働中に同名の出力を手動で作り直さないでください。

## Pi・MCP・スキル

| 場所 | 役割 |
| --- | --- |
| [shared/pi/default.nix](home/keewai/shared/pi/default.nix) | 全ホスト共通の Pi 設定の入口 |
| [shared/pi/agent.nix](home/keewai/shared/pi/agent.nix) | 本体・実行環境、モデル、ローカル拡張と指示の配布 |
| [shared/pi/claude-bridge.nix](home/keewai/shared/pi/claude-bridge.nix) | Claude Code / Agent SDK 経由のモデル、認証用CLIと共通設定 |
| [skills/superpowers/](skills/superpowers/) | Opus / Astra 共通の Superpowers 入口スキルと用途別の参照手順 |
| [shared/pi/tasks.nix](home/keewai/shared/pi/tasks.nix) | pi-tasks の TODO 管理、保存先と表示設定 |
| [shared/pi/mcp.nix](home/keewai/shared/pi/mcp.nix) | Pi MCP アダプターの導入、共通 MCP サーバーの登録と設定変換 |
| [shared/pi/lsp.nix](home/keewai/shared/pi/lsp.nix) | Pi LSP 拡張の導入、言語サーバーと診断設定 |
| [shared/pi/web-search.nix](home/keewai/shared/pi/web-search.nix) | Pi Web 検索拡張の導入、検索・取得経路、CLI / Web 共通の設定ファイル |
| [shared/pi/web.nix](home/keewai/shared/pi/web.nix) | Pi Web の導入、ユーザーサービス、ホストごとの tailnet 許可 |
| [shared/pi/subagents.nix](home/keewai/shared/pi/subagents.nix) | CLI/Web 共通のネイティブ委任・ロール・設定 |
| [shared/pi/APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) | 全プロジェクト共通の追加システム指示 |
| [shared/pi/extensions/](home/keewai/shared/pi/extensions/)、[prompts/](home/keewai/shared/pi/prompts/) | ローカルコンテキスト管理・キャッシュ監視・CLI 完了通知、レビュー用プロンプト |
| [desktop/pi/default.nix](home/keewai/desktop/pi/default.nix) | デスクトップ専用連携の入口 |
| [desktop/pi/cua.nix](home/keewai/desktop/pi/cua.nix) | デスクトップ操作用ドライバーと MCP |
| [shared/skills.nix](home/keewai/shared/skills.nix)、[skills/](skills/) | Pi 以外とも共有できる個人スキルの配布と編集元 |
| [pkgs/pi-coding-agent/](pkgs/pi-coding-agent/)、[pkgs/pi-web/](pkgs/pi-web/) | アプリ本体のビルド定義とパッチ |
| [pkgs/pi-claude-bridge/](pkgs/pi-claude-bridge/)、[pi-tasks/](pkgs/pi-tasks/)、[pi-mcp-adapter/](pkgs/pi-mcp-adapter/)、[pi-web-access/](pkgs/pi-web-access/)、[pi-lsp/](pkgs/pi-lsp/) | 拡張本体と実行時依存関係の固定・ビルド |
| [modules/common.nix](modules/common.nix) | ログイン前にもユーザーサービスを起動するための linger |
| [citrus/web.nix](hosts/citrus/web.nix)、[orange/services/web.nix](hosts/orange/services/web.nix) | 既存の Tailscale Serve と nginx による HTTPS 公開 |

共通プロフィールは `shared/pi/`、デスクトッププロフィールは追加で `desktop/pi/` を読み込みます。
設定を追加するときは、既存の機能別ファイルへ追記するか、同じディレクトリに名前の明確な
モジュールを作り、その `default.nix` の `imports` に追加します。
npm 拡張のバージョンと依存関係は `pkgs/pi-*/`、読み込み対象と設定は担当の Home Manager モジュールで管理します。
Superpowers の入口と参照手順は `skills/superpowers/`、配布は `shared/skills.nix` が担当します。
`settings.packages` の `lib.mkOrder` で拡張の読み込み順を固定します。
Pi Codex conversion とそのツール置換・Remote context management は読み込みません。
ローカル拡張は `extensions/`、プロンプトは `prompts/` に置いて `agent.nix` から配布します。
共有スキル、パッケージのビルド、OS の公開設定は Pi 専用設定と役割が異なるため、
上表の担当場所に残します。配置の整理で `~/.pi/agent` などの配布先やホストごとの有効機能は変えません。

Codex CLI、Remote Control、ChatGPT Desktop とそのブラウザー・URL 連携は導入しません。
Pi の `openai-codex` は ChatGPT 契約で接続するプロバイダー名であり、Codex CLI は必要ありません。
認証と過去の会話など、旧アプリのユーザーデータやロールバック用の旧世代は自動削除しません。
設定を変える場合は、このリポジトリの編集元を変更してください。
`~/.pi/agent` の Nix 管理対象ファイルや `~/.agents/skills` の生成物は直接編集しません。
Ponytail も他の個人スキルと同じ `~/.agents/skills` に配置します。

### Pi のモデルとツール

`pi` をプロジェクト内で起動し、初回は `/login` から OpenAI (ChatGPT Plus/Pro) を選びます。
認証は Pi の `~/.pi/agent/auth.json` に保存されます。
継続は `pi -c`、過去のセッションを選ぶ場合は `pi -r` です。
パッケージ管理や `auth check` なども同じ `pi` コマンドを使います。
Pi と Pi Web の実行環境には Node.js、Python（`python` / `python3`）、jq、ast-grep を含めます。
MCP の大きな JSON 出力を処理するときに、補助コマンドが見つからず再試行することを防ぎます。
構文構造を使う検索には Nix で固定した `ast-grep` CLI を使います。npm のネイティブバイナリを
取得する追加拡張は使わず、検索は読み取り専用とし、変更は通常の編集ツールで行います。
Linux の別コマンドと混同しないよう、`sg` ではなく `ast-grep` を呼び出します。
Pi 標準の `shellCommandPrefix` で、シェルツールと `!` / `!!` の PATH の先頭に
NixOS の権限ラッパーを置きます。Pi Web の非ログイン環境でも `sudo` が
`/run/wrappers/bin/sudo` を使うようにし、sudo の認証・承認条件は変更しません。
シェル実行には Pi 標準の `bash` を使い、Codex conversion の `exec_command` や専用ラッパーは使いません。
Web の別端末や、指定したシェルを使わない拡張プロセスは対象外です。
`pipefail` により、パイプの前段で失敗した検証を後段の整形処理が成功として隠すことを防ぎます。
`errexit` は強制せず、想定した失敗は呼び出し側で明示的に処理します。
`defaultProjectTrust = "always"` により、すべてのディレクトリを既定で信頼します。
プロジェクトの設定・スキル・拡張は確認なしで読み込まれ、拡張コードはユーザー権限で実行されます。
個別に保存した信頼拒否や明示的な `--no-approve` は Pi 標準の優先順位で適用されます。

既定のモデルは `openai-codex/gpt-6-astra`、推論は `xhigh`、コンテキスト上限は 872,000 です。
モデル選択は制限せず、必要なら Pi 標準の操作で変更できます。
自動コンパクションは有効です。一般設定は応答用 16,384・直近履歴 20,000 トークンとし、
Astra はモデル別設定で従来の 131,072・32,768 トークンを維持します。

[pi-claude-bridge](https://github.com/elidickinson/pi-claude-bridge) は `0.8.0` に固定し、
Claude Agent SDK `0.3.276` と Nixpkgs の Claude Code `2.1.276` を組み合わせます。
CLIは Home Manager の `programs.claude-code` で導入し、ブリッジには絶対 Store パスを渡します。
SDK同梱の未調整ネイティブCLIや、起動時のダウンロードには依存しません。
`claude auth login` でClaude Code側にログインし、`claude auth status` で状態を確認してから、
Piの `/model` で `claude-bridge/claude-opus-5-5` などを選びます。Piの `/login` とは別の認証です。
認証情報はNix Storeへ入れず、既存のPi認証・履歴も変更しません。

設定元は [claude-bridge.nix](home/keewai/shared/pi/claude-bridge.nix) です。
`AskClaude` は無効にし、委任はネイティブ `Agent`、TODOは `pi-tasks` に統一します。
`plan = "pro"` を保守的な既定値とし、長文脈向けの追加課金は有効化しません。
Opus 5.5は上流ブリッジの未測定モデル規則に従い200Kで登録し、1Mを強制しません。
費用表示が0でも無料の保証ではなく、認証・利用枠・課金はClaude側の契約に従います。
Claudeの独立したMCP・スキル探索・自動メモ・自動compactionは使わず、Piの指示とツールを渡します。
この固定版にはPi 0.87向けの互換パッチを適用します。モデル登録は環境ごと、実行状態はPiセッションごとに
分離し、子の作業ディレクトリと指示はPiの構造化コンテキストから取得します。compactionはPi標準で記録します。
プロジェクト別のブリッジ設定と `AskClaude` は対応対象外です。設定はNix管理のグローバルファイルに集約します。
新しい問い合わせは現在のPi履歴から再構成するため、上流とキャッシュ効率が異なる場合があります。
Claude側HTTP要求の `onPayload`／`onResponse` 監視・書き換えには対応しません。
認証・モデルの利用権・実推論は、パッケージの読み込みや隔離テストだけでは確認できません。

全ホストと共通Home Managerのパッケージ評価では [common.nix](modules/common.nix) の
`nixpkgs.config.allowUnfree = true` を使います。flakeの公開パッケージ・開発シェル用の
Nixpkgsインポートも同じ許可設定です。以前のNVIDIA限定許可リストは使いません。

Pi 本体は [pi-coding-agent/default.nix](pkgs/pi-coding-agent/default.nix) で 0.87.1 に固定し、
Nixpkgs のビルド定義を使ってソース・npm 依存関係・モデルカタログのハッシュを検証します。
標準の ChatGPT 接続にはキャッシュ用ヘッダーを本文のキーに合わせる小さなパッチを適用しています。
`pi-mcp-adapter@2.34.0`、`pi-web-access@0.30.0`、`@narumitw/pi-lsp@0.49.7`、
`@tintinweb/pi-tasks@0.9.0`、`pi-claude-bridge@0.8.0` は Nix で固定し、Home Manager の `settings.packages` から
Nix ストアのパッケージを直接読み込みます。初回起動時の npm インストールは不要です。
通常の依存関係を持つ拡張は各 `pkgs/pi-*/package.json` と `package-lock.json`、`npmDepsHash` で
配布物と依存関係を固定し、lifecycle scripts と Pi SDK の重複インストールを無効にしてビルドします。
Pi SDK だけに依存する LSP は npm 配布物のハッシュを固定します。
更新時は担当パッケージのバージョン・ロック・ハッシュを更新して NixOS の検証と適用を行います。
`pi update --extensions` ではこれらの固定パッケージを更新しません。
Piの認証・会話・実行時キャッシュは引き続き `~/.pi/agent` に保存します。
Claude Codeの認証とSDK動作中の一時的な会話ファイルは別途 `~/.claude` 側に置きます。
互換パッチが生成した問い合わせ専用ファイルは終了後に片付け、元の履歴はPiのJSONLに保持します。
既存のClaude会話ファイルは削除しません。
以前の `~/.pi/agent/npm/` は読み込みに使わず、自動削除もしません。

[Superpowers 6.4.1](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71)
の全15スキルを、[Astra の設計指針](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
と [Opus の利用指針](https://claude.dev/blog/getting-the-most-out-of-opus-5-5/)に沿う共通のローカル版として管理します。
[skills/superpowers/SKILL.md](skills/superpowers/SKILL.md) が1つの入口になり、
残り14のワークフローは `references/` から必要なものだけ読みます。
起動時に提示する名前・説明は `superpowers` の1件です。
[shared/skills.nix](home/keewai/shared/skills.nix) が `~/.agents/skills/superpowers/` へ配布し、
Pi 標準の探索で読み込みます。公式パッケージや bootstrap 拡張は重ねて登録しません。

| 作業 | 運用 |
| --- | --- |
| 原因・修正方針が明確なバグ修正、通常の設定変更 | Superpowers なし。範囲と必要な確認を明確にして直接実施 |
| 要件や設計に重要な未決事項がある変更 | 必要に応じて入口から設計の手順を選ぶ |
| 複数段階の調整・計画が必要な変更 | 計画・実行の手順を選び、親が現在のセッションで進める |
| 高リスクな変更、厳密な検証の明示依頼 | 必要なデバッグ・テスト・検証の参照だけを読む |
| 独立した実装作業を分担する利点が明確な変更 | 委任の手順を選ぶ。規模だけでは分担しない |

`/skill:superpowers <依頼内容>` で明示的に呼び出せます。以前の
`/skill:brainstorming` などの個別コマンドは登録せず、
例えば `/skill:superpowers 設計の未決事項を整理して` と指定します。
広すぎる発動条件、固定回数の工程、不要な承認待ちを避け、許可された範囲の完遂を重視します。
通常の選択方針は [APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) に置き、
Ponytail、利用者の明示指示、AGENTS.md の配置・検証・承認規則を維持します。
上流リビジョンと MIT ライセンスはスキル内に保持し、更新は `skills/superpowers/` で行います。
上流の実行ヘルパーや会話エクスポート機能は配布しません。
適用後は新しい Pi セッションで利用してください。既存の会話は書き換えず、モデルと effort も変更しません。

[Pi 0.86.0](https://github.com/earendil-works/pi/blob/v0.86.0/packages/coding-agent/CHANGELOG.md) は
プロバイダーへ渡すシステム指示・ツール定義を `TranscriptContext.messages` 内へ移しました。
追加プロバイダーもこの形式と標準ツールの契約に対応する必要があります。
Pi 本体の `cacheWarming` は `off` にし、更新によってキャッシュ維持用の追加推論を有効にしません。
Pi Web はビルド時も実行時も同じ Pi SDK を参照し、
[transcript-context.patch](pkgs/pi-web/transcript-context.patch) でタイトル生成・専用システム指示・
セッション一覧の同時刻の並び順を新しい SDK に合わせます。
会話履歴や読み取り専用の `agent.state.systemPrompt` は書き換えません。
Pi Web のラッパーは同じ SDK の場所を `PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT` で伝え、
通常と異なる Nix の配置でもバックグラウンドの子が本体を解決できるようにします。

コンテキスト管理は [local-context.ts](home/keewai/shared/pi/extensions/local-context.ts) が担当します。
Astra の「メモを引き継ぎ、必要な過去の履歴を検索する」方式を Pi のローカル保存で近似し、
Opus と Astra に共通で使います。OpenAI 内部実装や暗号化チェックポイントの再実装ではありません。
Pi の元の JSONL 履歴は保持し、選択中のセッション・ブランチに限定して必要な箇所を取得します。
自動コンパクションと手動 `/compact` は維持します。「ローカル」は保存と制御を指し、
通常のモデル推論やコンパクション用要約までオフラインになるわけではありません。
`context_notes` は明示メモの読み取り・全体更新、`context_history_search` と
`context_history_read` は元のテキストの検索・範囲取得を提供します。メモは Pi の追記型セッション記録に
保存し、自動要約とは区別します。メモや TODO を毎ターンのシステム指示に重ねて注入しません。
取得結果は件数・文字数を制限し、entry/window ID と次ページ位置を返します。window は compaction 境界の
時系列区間で、過去にモデルへ送った入力の完全な複製ではありません。思考・画像・ツール引数・非公開
メタデータ・他拡張のチェックポイントを除外しますが、通常のテキストに含まれる秘密の万能除去機能ではありません。

TODO は [pi-tasks](https://github.com/tintinweb/pi-tasks) の `TaskCreate / TaskList / TaskGet / TaskUpdate` で管理します。
保存先は `session-global`（`~/.pi/agent/tasks/sessions/` 以下）で、リポジトリに作業用ファイルを増やしません。
完了タスクの自動削除と auto-cascade は無効です。既存ファイルの移動・削除は行いません。
永続セッションの fork は親の TODO を独立した保存先に引き継ぎます。読み取り不能・破損・旧形式の不正な
タスクファイルは空として上書きせず、操作を止めて元データを保持します。修復は別途明示的に行ってください。
`TaskExecute / TaskStop / TaskOutput` は登録せず、子の実行と結果確認は従来のネイティブ `Agent` 系ツールが担当します。
親が結果を確認して TODO を更新する設計で、二つのランタイムや自動同期を重ねません。
永続設定は [tasks.nix](home/keewai/shared/pi/tasks.nix) を編集します。

Codex conversion、専用補助バイナリ、Code Mode、Remote/Hybrid compaction の有効設定は撤去しています。
移行中の会話は `/reload` せず、適用後は新しいセッションで標準ツールとローカル方式を使います。
過去の会話・認証・取得済みパッケージは削除しません。旧 Remote セッションを新方式で安全に再開できるとは
限らず、暗号化状態をローカルメモに自動変換することもしません。旧設定と必要な Store パスは
移行時にローカルの退避先と GC root で保持します。旧セッションの再開は別途互換性を確認してください。

MCP は共有レジストリから、そのホストに定義されたすべてのサーバーを有効にします。
共通の `context7`、`nixos`、`openaiDeveloperDocs`、`serena` に加え、デスクトップでは `cua-driver` も使えます。
初回はツール情報を取得し、以降は必要時に接続します。共有設定へ追加したサーバーも Pi 側に反映されます。
`defaultTools` は Linux の全組み込みツール `read / bash / edit / write / grep / find / ls` を選びます。
Opus と Astra のどちらでも標準ツールを維持し、モデル別のツール置換は行いません。
拡張ツールも標準どおり有効にし、ラッパーの `--tools` による許可リストは設けません。
MCP アダプターのサーバー別補助ツールも、登録されると利用できます。
`/mcp` で接続状況を確認できます。
単独の操作は `mcp`、複数呼び出し間の依存処理や結果の抽出には `mcpScript` を使います。
`mcpScript` では中間結果をモデルへ全部返さず、必要な項目と出典だけを選べます。
既定の実行期限は30秒、中間転送量はスクリプト全体で16 MiB、最終出力には既存の出力制限が適用されます。
認証・承認条件は通常のMCP呼び出しと共通です。セキュリティ上の隔離境界ではなく、失敗や期限切れ後の
副作用を自動で再実行してよい根拠にもなりません。詳細は `/skill:mcp-scripting` で読み込めます。
この上流スキルは手動専用のため、通常のスキル説明一覧には追加されません。
個人スキルは Ponytail を含め、Pi 標準の `~/.agents/skills` 探索で共有します。
単純化（KISS）と不要な先行実装の抑制（YAGNI）は Ponytail に統合し、独立したスキルは配布しません。
Ponytail のモードは会話中に `ponytail lite`、`ponytail full`、`ponytail ultra` で指定します。
追加のシステム指示は `APPEND_SYSTEM.md` に置き、Pi 標準のツール説明とプロジェクトの AGENTS.md を維持します。
`/review` または `/review <対象>` で変更のレビューを依頼できます。
対象を省略した場合は、追跡済みの差分に加え、関連する未追跡の新規ソースも確認します。
生成物・無視対象・秘密情報は除外し、レビュー中に編集やステージはしません。
管理対象の設定・指示・拡張を変更するときは、このリポジトリの編集元を直します。

[pi-web-access](https://github.com/nicobailon/pi-web-access) が `web_search`、`fetch_content`、
`get_search_content`、`source_check` を提供します。以前の `pi-web-search` 拡張は使いません。
既定の検索経路は OpenAI のみで、現在のモデルと ChatGPT 認証を再利用します。
公式OpenAIモデルでは現在の会話モデルを検索にも使います。Claudeなどで検索するときは
`provider: "openai"` を明示し、独立した `openai-codex/gpt-6-astra` の検索経路を使います。
会話モデル自体の変更や、他社への自動フォールバックは行いません。
OpenAI Responses の `web_search` を必須で呼び出し、ライブ取得を有効にした標準動作を使います。
[OpenAI の仕様](https://developers.openai.com/api/docs/guides/tools-web-search#live-internet-access)では、
`external_web_access` の未指定は `true` です。検索ごとの要求は ChatGPT の利用枠を消費します。
`provider` を省略するとこの経路を使います。明示した `provider` は上流仕様どおり経路を上書きします。

設定元は [shared/pi/web-search.nix](home/keewai/shared/pi/web-search.nix) です。`PI_CODING_AGENT_DIR` がある Pi Web と XDG 設定を使う CLI の双方に対応するため、
`~/.pi/agent/web-search.json` と `~/.config/pi/web-search.json` を同じ Nix Store の設定へ接続します。
通常の検索は `workflow = "none"` とし、検索のたびに確認用ブラウザーや追加要約を起動しません。
必要なときは `/websearch` で確認用 UI を開けます。生成された設定ファイルは編集せず、変更は Nix 側で行います。
ブラウザー Cookie の取得と第三者サービスによるページ取得代行は既定で無効、PDF はローカルの `unpdf` で抽出します（OCR なし）。
`source_check` は原文のハッシュ・引用箇所を返しますが、主張の支持・反証は自動判定しません。
重要な主張は `fetch_content` と `get_search_content` で原文を確認します。専門仕様には引き続き既存の MCP を使います。

[@narumitw/pi-lsp](https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-lsp) は
必要時だけ `lsp_diagnostics` で診断し、呼び出し終了時に言語サーバーを停止します。
Nix（nixd）、TypeScript/JavaScript、Python、Lua、Bash を Nix の固定パッケージで設定し、Bash には ShellCheck を接続します。
Python の `.py` / `.pyi` は basedpyright の型診断と Ruff の lint・修正に振り分けます。
診断は両サーバーを使い、`lsp_fix` は対象サーバーを明示します。言語サーバーは専用の
Nix Store パスから起動し、Python 仮想環境や既存プロジェクトの lint・型チェック設定は変更しません。
設定は `~/.pi/agent/pi-lsp.json` に配置します。`/lsp` で利用可能なサーバーを確認できます。
対象の `paths` と `root` を明示し、全体走査や診断出力の膨張を避けます。
診断はビルドやテストの代用ではなく、自動整形・自動修正は行いません。
リポジトリ内のPi拡張には [専用のTypeScript設定](home/keewai/shared/pi/tsconfig.json) を置き、
Nixプロフィール内のPi SDKとNode型定義を参照します。このプロフィールを適用済みのローカル環境用で、
リポジトリへのnpm依存関係追加やNix Storeのハッシュの固定は不要です。
`lsp_fix` は Pi と Pi Web の両方で利用できます。既定はプレビューで、
書き込む場合は同じファイルへの他の編集と並列実行しません。
追加拡張は過去の履歴を書き換えず、常駐の追加モデル要求も行いません。
速度や成果物の品質向上率を測定したものではなく、調査と途中診断の手段を補う構成です。

[notify.ts](home/keewai/shared/pi/extensions/notify.ts) は Kitty 上の Pi CLI が作業を終えたときに
OSC 99 のデスクトップ通知を送ります。`agent_settled` を使い、自動再試行・コンパクション・
後続メッセージの処理中には完了扱いにしません。Pi Web / RPC、非対話モード、非 Kitty 端末では
通知を出さず、追加のモデル要求や外部通知サービスも使いません。

作業分担と独立レビューは [Pi の委任拡張](#pi-の委任拡張)を CLI と Web の両方で
明示的な委任依頼なしでも利用します。共通の `/review` は Crew の独立した `code-reviewer` の結果も確認します。
拡張を利用できない場合は親が直接レビューし、その制限を報告します。

システム指示とツール定義を不用意に変えず、毎ターンの日付・Git 状態の注入、履歴の書き換え、定期的な空要求は行いません。
キャッシュキーは Pi 標準プロバイダーのセッション単位の扱いを使います。
作業ディレクトリ単位の独自キーへの上書きは行いません。
既存セッションの保存先や ID は変更しません。新規セッション間のキャッシュ共用は強制しません。
同じ仕事は `pi -c` で続け、モデル・推論レベル・拡張の変更や `/compact` は必要な場合に使います。
フッターの `CH` は直近要求の再利用率です。`/cache` は直近応答と選択ブランチの累計を分けて表示し、
再利用・新規キャッシュ書き込み・未キャッシュの入力トークン数を確認できます。
累計は全モデル・圧縮前も含む報告済み使用量を入力トークンで重み付けし、
通常応答・ツール内呼び出し・Pi 要約・旧 Remote 圧縮 V2 の内訳も表示します。
旧 V2 の使用量は保存済みメタデータから読みます。新しい Remote 圧縮を実行する機能ではありません。
入力使用量のない応答は `0%` ではなく `未計測` とします。表示はコマンド実行時点のスナップショットです。
端末ではスクロール可能なパネルを開き、↑↓ / PageUp / PageDown で移動、Esc / Enter で閉じます。
Pi Web / RPC では同じ内容をテキスト通知、非対話モードでは標準出力に表示します。
`cache-audit` は送信直前の指示・ツール・推論設定・キャッシュキーなどを項目別にハッシュで比較し、
変更された項目名だけを画面に知らせます。`/cache` では未観測・初回の基準記録・前回との差分を区別し、
最後に変化した項目も別に表示します。変更回数と比較基準はセッションの読み込み・再読み込み時にリセットします。
監視フックは要求や会話を書き換えず、設定値・プロンプト本文・ハッシュをログに保存しません。
設定が同じでも会話の変更、コンパクション、キャッシュ期限、サーバーの割り当てでミスが起こるため、再利用率は保証しません。
表示されるトークンや費用見積もりは、ChatGPT 契約の実請求や残り利用枠ではありません。

選定では [Pi の公式設定](https://pi.dev/docs/latest/settings)、
[拡張仕様](https://pi.dev/docs/latest/extensions)、
[pi-mcp-adapter の仕様](https://github.com/nicobailon/pi-mcp-adapter)、
[Astra の公式ガイド](https://developers.openai.com/api/docs/guides/latest-model)、
[OpenAI のキャッシュ仕様](https://developers.openai.com/api/docs/guides/prompt-caching)を確認しました。
Astra の API では `prompt_cache_options.ttl = "30m"` が現行仕様ですが、
ChatGPT 用の接続には API 専用の TTL パラメーターを追加しません。
本文のキーだけではなく `session-id` ヘッダーもキャッシュに使われる挙動は、
[上流の調査](https://github.com/earendil-works/pi/issues/6630)と実際の接続で確認しています。
[oh-my-pi の設定](https://github.com/can1357/oh-my-pi/blob/main/docs/settings.md)からは履歴の追記とキャッシュ維持の考え方を参考にしました。
[Armin Ronacher の利用記](https://lucumr.pocoo.org/2026/1/31/pi/)にある、小さいツール構成、必要時だけ読むスキル、レビュー操作も取り入れています。
[利用者の拡張構成の報告](https://www.reddit.com/r/PiCodingAgent/comments/1wgg6bx/my_pi_config_and_extensions/)では、
UI の改善とモデル性能の改善は区別されており、多数の拡張で性能が上がるとは判断していません。

### Pi Web

[Pi Web](https://github.com/agegr/pi-web) はユーザーサービスとして起動し、
各ホストのローカルでは `http://127.0.0.1:30141/pi/`、tailnet では
[https://citrus.tail1e65cd.ts.net/pi/](https://citrus.tail1e65cd.ts.net/pi/) または
[https://orange.tail1e65cd.ts.net/pi/](https://orange.tail1e65cd.ts.net/pi/) から使います。
Tailscale Serve の HTTPS 443 から、ループバックの nginx（`127.0.0.1:8000`）を通して公開します。
nginx は `/pi/` を Pi Web へ転送します。Citrus の `/` は `/pi/` へリダイレクトし、
Orange の `/` は既存の Immich、`/vault/` は Vaultwarden のままです。
アプリの待受けはループバックだけです。
Pi Web は `/pi` を basePath として再ビルドし、API・静的ファイル・通知・PWA も同じパスを使います。
PWA の登録範囲は `/pi/` に限定します。
Pi のバージョン、モデル、拡張、LSP、スキル、ユーザーサービスは両ホストで共通です。
MCP の CUA だけは GUI のあるデスクトップ専用です。ホストの許可名は各ホストから生成します。
認証と会話はホストごとに保存し、複製しません。Orange も初回に Pi の `/login` で認証します。

Web 版と CLI は `~/.pi/agent` の認証、設定、拡張、スキル、会話ファイルを共有します。
Pi Web が内部で使う Pi SDK も、このリポジトリのキャッシュ修正版を使います。
Home Manager が管理する設定・モデル・スキルの変更は、Web 画面ではなく Nix の編集元で行います。

### Pi のネイティブ委任

CLI と Web は [Pi Web パッケージ](pkgs/pi-web/default.nix) の同じ実装を使います。
[subagents.nix](home/keewai/shared/pi/subagents.nix) が登録・共通設定、
[web.nix](home/keewai/shared/pi/web.nix) が Web サービスを所有し、
[web-package.nix](home/keewai/shared/pi/web-package.nix) で同じ SDK・派生を共有します。
CLI は `pi-web-native-subagents/subagent-cli-extension.js` のみを読み込み、Web サーバーを起動しません。
Web 内では CLI エントリーとの二重登録を抑止します。

| ツール | 操作 |
| --- | --- |
| `Agent` | 単独・バッチの委任、明示的な resume |
| `get_subagent_result` | 結果・状態・保持した子履歴の取得 |
| `steer_subagent` | 実行中・待機中の子への情報伝達 |
| `manage_subagents` | list / assign / message / answer / cancel / close / release |

Crew から明確な役割と構造化依頼・検証後 close、Core からバッチ依存関係・明示 resume、
Teams から共有タスク・送信者付きメッセージを取り込みました。旧3エンジンのラッパーではありません。
`pkgs/pi-crew/` の旧ビルド定義は保持していますが、Crew 拡張は登録・読み込みしません。
`scout`、`planner`、`oracle`、`worker`、`code-reviewer`、`quality-reviewer` を提供し、
Crew の固定ソースから役割本文を生成して MIT ライセンスを同梱します。
`general-purpose`、`explore`、`plan` は互換名です。モデルは親の実効モデルを継承します。

`manage_subagents(action: "list")` で現在のワークスペースの役割・タスクを確認します。
単独なら `subagent_type`、バッチなら `profile` を完全一致で指定します。
依頼は `assignment: {goal, context, instructions}`、独自専門性は明示的な `specialist_prompt` です。
読み取り専用ロールはシェルを持たないため、レビューには読める差分ファイルと新規ファイルを渡します。
子への拡張の継承は既定で無効です。ツール制限・worktree は OS サンドボックスではありません。

既定は fresh context・バックグラウンドです。独立作業は1バッチ、前提は `needs` に指定します。
同じ直属の親の全バッチ・resume を共通キューで最大4子に制限します（設定範囲1〜4）。
委任は親→子→孫まで対応し、孫からの再委任は禁止します。子の権限・ツール範囲を
広げる委任は認めず、読み取り専用の子から writer は作成できません。
適用前に作成した子は保存済みのツール範囲を維持するため、孫への委任には新しい子を作成します。
writer は明示した `input_revision` のコミットから独立 worktree に作成します。
未コミット変更は転送されず、`integrated_changes` 依存は親が統合後のコミット OID で
前提タスクを release するまで開始しません。自動コミット・マージ・worktree 削除は行いません。

Web は元のコンパクトなエージェント一覧・会話切替を維持し、孫の会話も同じ一覧で開けます。
追加のタスク件数・タスクカード・親操作フォームは表示しません。子の会話がない場合は
元のツールバーのままとし、未開始タスクの確認や割当、メッセージ、回答、resume、cancel、
統合 release、検証済み close は共通の委任ツール/API で行います。
ツール/API は直近100件の送信者付きメッセージを返し、それ以前もメタデータに保持します。
子の会話はリンクから確認できます。close には現行レポートの delivery ID が必要で、履歴は残ります。

同じ親の実行所有権は1プロセスだけが保持します。他の CLI/Web は閲覧できますが操作できません。
終了・クラッシュ後は自動実行せず、明示的な resume が必要です。CLI 終了後の常駐実行は保証しません。
4ツールは Pi 標準ツールと並べて直接利用します。Code Mode 用ブリッジは不要です。
委任は有用な場合に限定し、独立レビューとリポジトリの検証・適用ゲートを維持します。

旧 Teams・Crew・Core の登録と同梱スキル・プロンプトの読み込みを解除します。
取得済み npm ファイル、認証、旧履歴、未統合 worktree、ロールバック用レシピは削除しません。
旧プラグイン ID は自動移行されません。旧子を終了してから新しいセッションを開始し、
移行中のセッションで `/reload` しないでください。Nix 管理の設定・ロールは画面から変更できません。

状態は `systemctl --user status pi-web`、ログは `journalctl --user -u pi-web` で確認します。
ソース・依存・フォントは固定し、既存 `/pi/` の公開経路を維持します。

### Unified CLI/Web subagents: approved design

This section records the approved contract. The implementation is carried by the
package patch and common Nix registration above. Implementation checks and local
activation are separate gates; the plan below is not a deployment record.

#### Goal and ownership

Replace Agent Teams, Crew, and Core Subagent in both CLI and Pi Web with one
implementation derived from Pi Web's built-in subagents. Share role discovery,
task scheduling, child-session lifecycle, results, and persistence. Do not keep
the three existing engines behind a new facade.

Keep the shared implementation and its CLI entry point with the Pi Web package
sources and patches in [pkgs/pi-web/](pkgs/pi-web/). The Web adapter owns browser
events and session presentation; the CLI adapter owns extension registration and
terminal presentation. Neither adapter owns a second scheduler. CLI loading must
not start Next.js or require the Web service to be running. Both adapters use the
same packaged Pi SDK and public SDK interfaces, including provider registration
and authentication handling.

[subagents.nix](home/keewai/shared/pi/subagents.nix) owns the common delegation
package registration, roles, and settings. [web.nix](home/keewai/shared/pi/web.nix)
continues to own the Web application and user service. Settings and distributed
roles remain Nix-managed, not editable through agent-management operations.

#### Roles and assignment contract

Provide six explicit roles: `scout` for discovery, `planner` for implementation
plans, `oracle` for decisions, `worker` for implementation, `code-reviewer` for
correctness, and `quality-reviewer` for maintainability. Adapt the useful role
contracts from Crew without modifying its installed package-owned definitions;
retain the applicable license notices. Keep the native `general-purpose`,
`explore`, and `plan` names as compatibility aliases.

Select roles by exact name. Support an explicitly supplied specialist prompt
without fuzzy matching that silently replaces the caller's choice. Models inherit
the parent's effective provider and model unless explicitly overridden; do not
hard-code Crew's model allocations. Validate model and thinking overrides before
starting work and report unavailable choices without silently substituting one.

Accept self-contained assignments with `goal`, `context`, and ordered
`instructions`. Preserve the native single-task prompt form for compatibility.
Default to fresh conversation context and background execution. Allow delegation
through two edges (root -> child -> grandchild), without widening a child's
effective capabilities. Grandchildren cannot delegate. Load the working
directory's applicable repository instructions;
fresh context does not mean dropping `AGENTS.md`. Tool and resource selection must
be explicit and consistent on first start and resume. Tool restrictions and Git
worktrees are not an operating-system sandbox.
Retained children keep their captured capabilities; start a new child to use
nested delegation when the retained session predates that capability.

#### Tasks, communication, and presentation

Support single tasks and batches with explicit IDs and dependency edges. Reuse
the native queue with a hard maximum of four active children per parent session.
Default to four and accept configured limits only from one through four. Enforce
this limit for all starts and resumes, including separate batches for the same
parent; it is not a global limit shared by unrelated parents. Validate duplicate
IDs, unknown dependencies, and cycles before launching a batch. A dependent task
starts only after its prerequisites succeed and receives their bounded results.
Failure, cancellation, or unresolved input must not be passed downstream as success.

Maintain a task list with assignments, dependencies, status, and child-session
links. Allow the parent to assign pending work and send messages; allow scoped
parent/child and sibling communication within the same delegation group. Messages
must retain their sender and be distinguishable from user authorization. Prevent
cross-parent control, capability escalation, and delegation beyond grandchildren
by enforcing ownership and child tool availability, not only by prompting.
Stopping a parent must await descendant teardown before disposing its session.
Keep upstream compact conversation rows and session shortcuts as the Web
presentation. Do not add task counters, task cards, or parent-control forms;
task coordination remains available through native tools and the shared API.

Distinguish queued or dependency-blocked work, running work, input required,
completed reports, failure, cancellation, and interruption. A structured report
contains its outcome and complete report text; input requests also state what is
needed. The parent can answer input requests, steer running work, follow up in the
same child session, stop work, and close a verified delivery. Closing releases
runtime resources without deleting the retained session or worktree. Preserve
plain-text results from legacy native sessions.

CLI and Web tools expose the same task and control semantics. Web preserves its
original agent conversation list; CLI provides equivalent tool results and
compact status output. Existing native
`Agent`, result retrieval, and steering calls remain directly callable alongside
standard Pi tools, without an unregistered bridge or second execution runtime.

#### Persistence, interruption, and write isolation

Use Pi sessions for child transcripts and versioned delegation metadata for task
state and result delivery. Bound result and message payloads and keep complete
reports inspectable without injecting every child transcript into the parent.
Avoid rewriting old conversation history or moving credentials into task metadata.

Do not add a daemon. Active execution belongs to the CLI or Web process that
started it. Claim persistent execution ownership atomically for the parent
session, covering all its batches and child runs. While that owner is live, a
second process cannot enqueue another group for the same parent, control its
children, or resume its work. Another interface may inspect persisted history
but must report that execution is owned elsewhere rather than take it over.
When the owner exits or restarts, unfinished work becomes interrupted and requires
explicit resume. CLI exit does not promise detached execution. Do not
automatically replay tasks after a crash or uncertain completion.

Cancellation must finish child teardown before a run becomes resumable. Resume
retains the task's session, workspace, role, and effective resource configuration;
an explicit model override may resolve a provider failure. Persist result-delivery
state and reconcile undelivered reports when the parent resumes, without silently
starting another child or repeating an already acknowledged delivery.

Parallel writers use separate Git worktrees from an explicit committed input.
Reject an isolation request when that input cannot be provided; do not silently
fall back to editing a shared checkout. Uncommitted parent changes are not copied
implicitly. Passing an upstream report does not transfer its file changes: work
requiring those changes waits for the parent to integrate them and explicitly
release the dependent task against the integrated revision. Independent work may
continue. Never automatically commit, merge, delete worktrees, or remove branches.
Integration, commits, activation, and authorized cleanup remain parent-owned.

#### Migration and acceptance

Switch CLI and Web together: remove the three plugin registrations and their
loaded skills/prompts, enable the shared native implementation, and update
[APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md),
[/review](home/keewai/shared/pi/prompts/review.md), and the delegation guidance here.
Preserve unrelated extensions, model settings, and the existing `/pi/` exposure.
Stop old children before starting replacement sessions; do not reload the live
migration session. Retain downloaded old packages, historical plugin data,
authentication, and unmerged worktrees. Old plugin run IDs are not native run IDs
and are not automatically resumed or converted.

Use the existing package test framework for shared runtime and adapter coverage.
Use disposable agent state and synthetic local providers, not real credentials
or paid model calls, for lifecycle integration tests. Required behaviors include
role discovery, provider bindings, standard and extension tool availability, both adapter
paths, concurrency, dependency failures, messages, input/follow-up/close, result
delivery, cancellation/resume, process ownership, and retained writer changes.
Verify that child repository instructions and tool restrictions survive resume.
Keep detailed validation guidance in
[nixos-validation](.agents/skills/nixos-validation/SKILL.md), not a separate check
suite or documentation directory.

After implementation, obtain a fresh-context diff review, run the relevant
checks, and commit only task changes. Test and switch the committed configuration
only on the verified local host, Citrus, with the repository's network, unit,
affected-service, and running/boot-default checks. Do not deploy to Orange or
publish remotely. Until implementation and those gates pass, the integration
remains planned rather than deployed.

### Unified CLI/Web subagents implementation plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` after the user reviews this plan and selects the
> execution method. The parent owns staging, commits, integration, and activation.

**Goal:** Replace the three delegation plugins in CLI and Web with the same
Pi Web-derived runtime, six roles, durable task coordination, and safe recovery.

**Architecture:** Extend the existing native controller and queue rather than
wrapping the old engines. Extract shared child-session construction, persistent
task state, and parent execution ownership. Thin CLI and Web adapters supply
parent context and presentation; a bundled CLI entry uses the same source.

**Tech stack:** TypeScript, Node.js, the pinned Pi 0.87.1 SDK, existing `node:test`
and `jiti` tests, React/Next.js, existing `proper-lockfile`, and Nix/Home Manager.

**Spec:** [Approved design](#unified-cliweb-subagents-approved-design).
The plan is not an implementation-completion or deployment record.

#### Global constraints

- "Do not keep the three existing engines behind a new facade."
- "Default to four and accept configured limits only from one through four."
- "Models inherit the parent's effective provider and model unless explicitly overridden."
- "Default to fresh conversation context and background execution."
- "Allow delegation through two edges (root -> child -> grandchild), without widening a child's effective capabilities."
- "Do not add a daemon."
- "Claim persistent execution ownership atomically for the parent session, covering all its batches and child runs."
- "Never automatically commit, merge, delete worktrees, or remove branches."
- "Uncommitted parent changes are not copied implicitly."
- "Old plugin run IDs are not native run IDs and are not automatically resumed or converted."
- "Do not deploy to Orange or publish remotely."
- Retain `/pi/`, the packaged SDK, other plugins, authentication, and history.
  Use package-local tests; do not create repository-local check suites or docs.

#### Review focus

1. A registered provider or extension changes the effective tool set: test the
   actual SDK-created child and its resumed session, not only declared profiles
   (Tasks 3 and 5).
2. CLI and Web race for the same parent, or a PID is reused: exactly one execution
   owner wins; uncertain liveness never permits takeover (Task 2).
3. A cancelled child is still tearing down while another batch or resume arrives:
   preserve the four-child bound and reject overlapping attempts (Tasks 3 and 4).
4. A notification is queued but not persisted, or the CLI changes parent sessions:
   do not lose reports, duplicate acknowledged reports, or notify the wrong parent
   (Tasks 4 and 5).
5. An upstream writer reports success with unmerged changes: retain clean and
   dirty worktrees and keep file-dependent work blocked until explicit integration
   release; test paths containing spaces (Tasks 3 and 4).

#### Source and patch workflow

Keep repository edits in the task worktree, separate from the occupied main
index. Prepare a disposable Pi Web source checkout from the pinned source in
`pkgs/pi-web/default.nix`, apply its four existing patches in order, and record
that as the patch baseline. Never edit Nix Store files. Restore development
dependencies offline from that derivation's `npmDeps` cache into the disposable
checkout, after running `use-packaged-pi-sdk.mjs` on its manifests. Use the same
SDK symlinks as `postConfigure`. Do not install mutable global dependencies or
run baseline builds unrelated to a changed behavior.

All `lib/`, `components/`, `app/`, and `e2e/` paths below refer to that disposable
Pi Web checkout. Carry its changes in the new
`pkgs/pi-web/unified-subagents.patch`, appended after the existing four patches.
Generate the patch from the recorded baseline, including new source files and
package-local tests. Apply it to a second clean copy of that same patched
baseline with `git apply --check` before each task commit. Update only task files;
parent commits use explicit paths, never `git add .` in the Nix checkout.
Tasks 1 through 6 leave tested checkpoints in that task diff. Do not commit
implementation checkpoints before an independent review of their actual diff;
the native execution path consolidates them in the reviewed Task 7 commit.

#### Task 1: Define roles, task contracts, and the hard concurrency limit

**Files:** Modify `lib/subagents.ts`, `lib/subagent-settings.ts`,
`lib/subagent-queue.ts`, and their existing tests. Create
`lib/subagent-task-types.ts`, `lib/subagent-task-types.test.mjs`, and generated
`lib/subagent-role-data.json`. Add the patch and role-generation build wiring to
`pkgs/pi-web/default.nix`; create `pkgs/pi-web/build-subagent-roles.mjs`.

**Interfaces:** Keep native v1 metadata readable. Use the following shared types;
`context` remains an array, matching the approved structured assignment contract.

```ts
export type Assignment = string | {
  goal: string;
  context: string[];
  instructions: string[];
};
export type Dependency = { taskId: string; input: 'report' | 'integrated_changes' };
export type DelegationReport =
  | { outcome: 'completed' | 'failed'; report: string }
  | { outcome: 'needs_input'; report: string; needs: string };
export type TaskStatus =
  | 'blocked' | 'queued' | 'running' | 'cancelling' | 'needs_input'
  | 'completed' | 'failed' | 'aborted' | 'interrupted';
export interface TaskInput {
  id: string;
  profile: string;
  description: string;
  assignment: Assignment;
  needs: Dependency[];
  inputRevision?: string;
  specialistPrompt?: string;
  model?: string;
  thinking?: ThinkingLevel;
}
```

- [ ] Add failing tests for six canonical roles and three native aliases,
  structured and plain assignments, blank fields, unknown report outcomes,
  `needs_input` without `needs`, and the boundary values below.

  ```js
  import assert from 'node:assert/strict';
  import test from 'node:test';
  import { createJiti } from 'jiti';
  const { validateSubagentLimit } = await createJiti(import.meta.url)
    .import('./subagent-settings.ts');
  test('enforces the native limit', () => {
    for (const value of [1, 4]) assert.equal(validateSubagentLimit(value), value);
    for (const value of [0, 5, 1.5, NaN]) {
      assert.throws(() => validateSubagentLimit(value));
    }
  });
  ```

- [ ] Run `node --experimental-strip-types --test lib/subagent-settings.test.mjs
  lib/subagent-queue.test.mjs lib/subagents.test.mjs
  lib/subagent-task-types.test.mjs`; confirm the new assertions fail before fixes.
- [ ] Define the shared schemas and `formatAssignment(assignment: Assignment):
  string`. Reject whitespace-only required strings and empty instructions. Set
  missing concurrency to four and reject explicit invalid settings. Call this
  same validation at the queue boundary instead of clamping arbitrary values.

  ```ts
  export function validateSubagentLimit(value: number): number {
    if (!Number.isInteger(value) || value < 1 || value > 4) {
      throw new Error('maxConcurrent must be an integer from 1 through 4');
    }
    return value;
  }
  ```

- [ ] Fetch only the fixed Crew 1.0.34 source as a build input from
  `https://registry.npmjs.org/@melihmucuk/pi-crew/-/pi-crew-1.0.34.tgz`, with NAR
  hash `sha256-VICdpdnYu+JdtT2t+4DEARiPkY9kGBVkKBpX17qLU9U=`. Generate role body
  and description data from its six `agents/*.md` files after `postConfigure`,
  when the existing YAML parser is available; preserve its MIT notice.
  Do not import its runtime or model allocations. Non-worker defaults use the
  native read-only tool preset; worker uses coding tools and worktree isolation.
  Keep exact role selection and explicit specialist prompts. Map
  `general-purpose -> worker`, `explore -> scout`, and `plan -> planner` only as
  built-in aliases, without overriding an exact user-defined profile.
- [ ] Rerun the focused tests. Package-local tests must verify generated roles,
  not mirror a hand-maintained list in a second runtime. Regenerate/check the
  patch and retain this tested checkpoint for the independent diff review.

#### Task 2: Persist task state and claim one owner per parent

**Files:** Create `lib/subagent-state.ts`, `lib/subagent-state.test.mjs`,
`lib/subagent-ownership.ts`, and `lib/subagent-ownership.test.mjs`. Extend shared
types in `lib/subagent-task-types.ts`.

**Interfaces:** `readDelegationState(agentDir, parentSessionFile)` returns the
versioned state or no state. `updateDelegationState(agentDir, parentSessionFile,
mutate)` performs a locked read-modify-atomic-write. `claimParent`, `assertOwner`,
and `releaseParent` use a token containing parent identity and process identity.
`validateBatch(tasks: TaskInput[]): void` validates a complete batch before any
session or worktree creation. `readyTaskIds(state): string[]` is a pure selector.

- [ ] Add tests that two processes cannot claim the same parent, separate parents
  can proceed, PID reuse is not mistaken for the old owner, and uncertain process
  identity fails closed. Test malformed/unsupported state, duplicate IDs, unknown
  or self dependencies, cycles, unassigned work, and failed prerequisites.

  ```js
  import assert from 'node:assert/strict';
  import { createJiti } from 'jiti';
  const { validateBatch } = await createJiti(import.meta.url)
    .import('./subagent-state.ts');
  const task = (id, needs = []) => ({
    id, profile: 'scout', description: id, assignment: 'Inspect', needs,
  });
  assert.throws(() => validateBatch([
    task('a', [{ taskId: 'b', input: 'report' }]),
    task('b', [{ taskId: 'a', input: 'report' }]),
  ]), /cycle/i);
  assert.doesNotThrow(() => validateBatch([
    task('a'), task('b', [{ taskId: 'a', input: 'report' }]),
  ]));
  ```

- [ ] Run `node --experimental-strip-types --test lib/subagent-state.test.mjs
  lib/subagent-ownership.test.mjs`; confirm the new behavior is absent.
- [ ] Store state under the writable agent directory's `native-subagents/`, keyed
  by a hash of the canonical parent session path. Do not write into the managed
  `agents/` directory. Use private directories and files (0700 and 0600).
  State records parent/group/task IDs, assignment, role,
  dependencies, attempt, child session, resource snapshot, workspace, report,
  messages, pending deliveries, and `closedAt`. Preserve terminal outcomes when
  closing a delivery. Reject unsupported versions rather than overwriting them.
- [ ] Reuse `proper-lockfile` for short metadata critical sections and
  `writePrivateFileAtomicSync` for replacement. Persist a random ownership token,
  PID, Linux boot identity and process-start identity. Check actual process
  identity before recovering ownership; a stale lock timestamp alone is not
  permission to take over. Claim at the parent level, covering all its batches.
  Read-only inspection never claims ownership or starts work. Recover unfinished
  work as interrupted, never by automatically enqueueing it.
- [ ] Implement DAG validation and readiness without a second execution queue.
  Report dependencies require completed reports. Integrated-change dependencies
  additionally require a parent-approved commit OID. Bound messages to 8 KiB,
  structured reports to 256 KiB, and injected report excerpts to 32 KiB, measured
  as UTF-8 bytes; retain links to complete reports and reject oversized writes.
- [ ] Rerun the two test files and the queue tests. Regenerate/check the patch and
  retain the tested state/ownership checkpoint for independent review.

#### Task 3: Share child-session creation, recovery, and write isolation

**Files:** Create `lib/subagent-session.ts` and `lib/subagent-session.test.mjs`.
Modify `lib/subagent-runtime.ts`, `lib/subagent-prompt.ts`, `lib/worktree.ts`,
`lib/pi-types.ts`, and their existing runtime, prompt, isolation, and worktree tests.

**Interfaces:** The shared controller receives a parent port rather than requiring
the parent's full `AgentSession`. SDK types below come from the packaged Pi SDK.
`createSubagentSession(parent, input, snapshot?)` and
`restoreSubagentSession(parent, sessionFile, snapshot, modelOverride?)` return an
SDK child session; the shared runtime owns its lifecycle. The host may register
that session for display but must not separately construct it on resume.

```ts
export interface SubagentParentHost {
  parentSessionId: string;
  sessionFile: string;
  cwd: string;
  effectiveModel: { provider: string; id: string };
  thinking?: ThinkingLevel;
  resolveModelRuntime(): Promise<ModelRuntime>;
  readEntries(): readonly SessionEntry[];
  readContext(): unknown[];
  sendNotification(message: DelegationNotification): Promise<void>;
}
```

- [ ] Extend the runtime tests' injected-host pattern with a deferred abort and
  real temporary Git repositories. Cover start/resume using one queue, no fifth
  active child, queued and running cancellation, a resume rejected while
  cancelling, preserved resource snapshots, unsupported model/thinking overrides,
  and fresh/exact prompts that still contain applicable repository instructions.

  ```js
  import assert from 'node:assert/strict';
  let finishAbort;
  const abortFinished = new Promise((resolve) => { finishAbort = resolve; });
  const child = { abort: () => abortFinished };
  let released = false;
  const stopped = child.abort().then(() => { released = true; });
  assert.equal(released, false);
  finishAbort();
  await stopped;
  assert.equal(released, true);
  ```

  Apply this deferred-abort sequence through the real controller fixture: call
  cancel, assert resume is rejected and its slot remains occupied, resolve abort,
  await persisted cancellation, then assert resume can start exactly once.
- [ ] Run `node --experimental-strip-types --test lib/subagent-session.test.mjs
  lib/subagent-runtime.test.mjs lib/subagent-prompt.test.mjs
  lib/subagent-isolation.test.mjs lib/worktree.test.mjs` and capture failures.
- [ ] Move child resource restoration out of Web-only `startRpcSession` into the
  shared helper. Use public SDK services, validate the effective model before
  construction, and persist the effective tool/resource selection. Reuse existing
  prompt and resource readers; do not reintroduce the removed direct mutation of
  `agent.state.systemPrompt`. Remove `noContextFiles: true` from child paths and
  retain repository instructions even with an exact specialist prompt. Missing
  required restored resources are errors, not silent permission changes.
- [ ] Extend `addWorktree` with an optional resolved commit input without changing
  its ordinary UI callers. Native writers must supply `inputRevision`, resolve it
  locally to a commit OID, and create a new isolated branch from that OID. Keep
  native plain-prompt syntax, but report a clear error when a writer omits this
  required isolation input. Never use an implicit remote tip or shared-checkout
  fallback. Remove native worktree cleanup on success, failure, cancellation,
  close, and setup failure; return any created path when setup later fails.
- [ ] Unify start and resume completion handling. `cancel` transitions through
  cancelling, awaits abort/prompt completion and terminal persistence, and only
  then releases the queue slot. Retain session/worktree identity on resume;
  explicitly resumed tasks that never acquired a session perform their first
  execution and report that fact rather than claim restored conversation history.
- [ ] Test clean and dirty worktree retention, a parent dirty file absent from a
  child, exact commit selection, and paths with spaces. Rerun the focused tests,
  regenerate/check the patch, and retain the tested lifecycle checkpoint.

#### Task 4: Execute task graphs, scoped communication, and durable results

**Files:** Modify `lib/subagent-runtime.ts`, `lib/subagent-state.ts`,
`lib/subagent-extension.ts`, `lib/subagents.ts`, `lib/types.ts`, and their tests.

**Interfaces:** Add controller operations `startBatch`, `list`, `assign`,
`resume`, `cancel`, `release`, `message`, `close`, and `reconcileDeliveries`.
Each takes a registered parent host or child actor, never trusts a tool-supplied
parent identity, and uses Task 2 state plus Task 3 session operations. `release`
takes a task ID and integrated commit OID. `close` takes a task ID and delivery ID.

```ts
export type DelegationActor =
  | { kind: 'parent'; parentSessionId: string }
  | { kind: 'child'; parentSessionId: string; taskId: string; sessionId: string };
export interface DelegationNotification {
  deliveryId: string;
  parentSessionId: string;
  taskId: string;
  attempt: number;
  report: DelegationReport;
}
```

- [ ] Add controller and extension tests for rejected batches with zero launch
  side effects, dependency success/failure/input wait, pending role assignment,
  integrated-change release, cross-parent rejection, sibling sender identity,
  answer/follow-up in the same child session, stale delivery IDs, and close
  without deleting files. Simulate crashes before send, while queued, and after
  parent transcript persistence but before delivery-state persistence.
- [ ] Run `node --experimental-strip-types --test lib/subagent-runtime.test.mjs
  lib/subagent-state.test.mjs lib/subagent-extension.test.mjs
  lib/subagents.test.mjs` and confirm the new lifecycle tests fail.
- [ ] Extend `Agent` with structured assignments, batches, explicit specialist
  prompts, committed writer inputs, and resume model overrides. Retain native
  `get_subagent_result` and `steer_subagent`. Add one parent control tool,
  `manage_subagents`, for list/assign/message/answer/cancel/close/release. Add only
  `report_subagent` and `send_subagent_message` to children, with actor identity
  bound by the runtime. Exclude all parent control tools from child sessions.
- [ ] A child report terminates its turn but does not free a slot until SDK
  teardown completes. `needs_input` keeps the session for explicit answer/resume.
  Successful prerequisites release report-only dependents; file-dependent tasks
  remain blocked until the parent supplies an integrated revision. Assigning work
  may change a pending task's role and assignment, never mutate a running attempt.
- [ ] Give each attempt a stable delivery ID. Save the report and pending
  delivery before notifying. Move delivery responsibility from the extension's
  completion callback into the runtime. Treat the matching persisted parent
  `custom_message.details.deliveryId` as the receipt; a resolved send Promise is
  insufficient. Keep an in-process inflight set until receipt or owner teardown,
  and reconcile against parent entries before redelivery. Scope all messages to
  their group and label agent messages as information, not new user authority.
- [ ] Verify legacy result text, queued/blocked result retrieval, sender checks,
  input-required payloads, payload byte limits, and no double completion callback.
  Rerun the focused tests, regenerate/check the patch, and retain the tested
  task-coordination checkpoint for independent review.

#### Task 5: Connect CLI and Web to the shared controller

**Files:** Create `lib/subagent-cli-extension.ts` and
`lib/subagent-cli-extension.test.mjs`. Modify `lib/rpc-manager.ts`, its runtime and
shutdown tests, and `lib/subagent-extension.ts`. Create
`lib/subagent-adapters.test.mjs` for disposable SDK integration coverage.

**Interfaces:** CLI exports the standard `(pi: ExtensionAPI) => void` extension
factory. Web supplies the existing wrapper registration and event invalidation
callbacks. Both construct `SubagentParentHost` and call the same controller.

- [ ] Add tests that both adapters expose one copy of every native tool, load no
  old engine, and produce the same child metadata/results. Use temporary agent
  state and registered synthetic providers that return deterministic tool calls;
  inspect actual SDK child tools, provider bindings, and resumed resources. Test
  a parent session switch with an undelivered report and a shutdown mid-cancel.
- [ ] Run `node --experimental-strip-types --test
  lib/subagent-cli-extension.test.mjs lib/subagent-adapters.test.mjs
  lib/rpc-manager.test.mjs lib/rpc-manager-shutdown.test.mjs` before wiring.
- [ ] The CLI factory registers tools without starting resources. Bind a parent
  port at session start and release it after awaited shutdown. Build the child
  `ModelRuntime` with public `ModelRuntime.create`, register the parent's public
  native/configured providers, and transfer only necessary runtime authentication
  through public APIs. Disable network model discovery. Do not read private
  `ModelRegistry.runtime`, persist credentials in task state, or silently fall
  back to another model. Keep selected model/thinking validation in Task 3.
- [ ] In Web, retain the native inline extension and register children for the
  existing inspectable session UI. Extend the existing precedence filter to
  suppress only the known packaged CLI entry when the native inline entry is
  active. Preserve unrelated tools, extensions, and diagnostics. Both routes must
  restore children through Task 3, not recreate independent Web-only state.
- [ ] When CLI moves to another parent session, do not send an old parent's
  report into the new one. Keep that delivery pending and reconcile only when
  its owner parent is active again. On shutdown, abort and persist unfinished
  children before releasing ownership; no detached child execution is promised.
- [ ] Load the configured extensions in disposable integration tests
  and prove that native delegation tools remain directly callable while children
  retain their intended permissions. Rerun the adapter tests, regenerate/check
  the patch, and retain the tested adapter checkpoint for independent review.

#### Task 6: Preserve original Web presentation and shared control APIs

**Files:** Modify `components/AgentSessionPanel.tsx`, `components/AgentsConfig.tsx`,
their tests, `components/AppShell.tsx`, `lib/api-types.ts`,
`app/api/subagents/[id]/route.ts`, settings/profile routes and relevant tests.
Retain `app/api/subagents/tasks/route.ts` and its route tests. Cover native
conversation navigation and API resume in the existing package-local
`e2e/run.mjs` flow without adding a task-management UI.

**Interfaces:** `GET /pi/api/subagents/tasks?parentSessionId=...` returns inspectable
task state and ownership. POST accepts the same parent control actions as
`manage_subagents`. Resolve the actual parent and actor on the server before
calling the controller; client input does not grant ownership or arbitrary file
access. Active work owned elsewhere is viewable but cannot be controlled.

- [ ] Add failing route tests for missing parents, cross-parent child IDs,
  rejected owners, each control action, input-required reports, and read-only
  managed settings. Add UI coverage for the original session list and child
  navigation, with no additional task count, task cards, or parent-control forms.
- [ ] Run `node --experimental-strip-types --test
  'app/api/subagents/**/*.test.mjs' components/AgentSessionPanel.test.mjs
  components/AgentsConfig.test.mjs` and capture the new failures.
- [ ] Keep the original agent panel and toolbar. Adapt native single/batch tool
  results to the existing child-conversation shortcut. Preserve `/pi/` and the
  existing SSE/session refresh path. Task state and controls remain in the
  shared tools/API rather than replacing conversation rows.
- [ ] Report Nix-managed settings/profiles as read-only with an explanatory UI
  state; reject mutations server-side before writing. Preserve existing editable
  unmanaged project profiles. Do not add a new configuration owner or locale.
- [ ] Extend the existing disposable E2E fixture with seeded native tasks and
  run `node e2e/run.mjs` against its isolated server and browser. Use the `/pi/`
  base URL and a Nix-provided browser; do not download a mutable browser or use
  real user sessions. Verify original rows at mobile and desktop widths,
  API resume, and reconnect without resurrecting completed work.
  If the browser prerequisite is unavailable, record the blocker rather than
  claiming a source-pattern assertion proves the UI behavior.
- [ ] Rerun affected route/component tests, regenerate/check the patch, and
  retain the tested Web checkpoint for independent review.

#### Task 7: Package and migrate the common implementation

**Files:** Modify `pkgs/pi-web/default.nix` and the patched `package.json`.
Create `pkgs/pi-web/build-subagent-extension.mjs` and
`home/keewai/shared/pi/web-package.nix`. Modify
`home/keewai/shared/pi/{subagents.nix,web.nix,APPEND_SYSTEM.md,prompts/review.md}`,
the delegation references in `AGENTS.md`, this README, and
`.agents/skills/nixos-validation/SKILL.md`. Superpowers configuration is
independent of delegation; preserve its current skill distribution and selection
policy described in the Pi skills section above.

**Interfaces:** Both Nix modules import `web-package.nix` to obtain the same Pi Web
derivation. Its packaged `pi-web-native-subagents/subagent-cli-extension.js` is the sole configured delegation
extension; the service still uses the existing `pi-web` executable.

- [ ] Add package-local adapter tests for the packaged CLI entry, six roles,
  provider/tool bindings, no Next.js startup on CLI load, and one registration
  under Web. Add a disposable combined-resource check including local context,
  TODO tracking, and the preserved MCP/search/LSP extensions. Do not load real credentials.
- [ ] Bundle the CLI entry using the already pinned SDK's `esbuild` library,
  leaving SDK and npm dependencies external. Do not bundle a second Pi SDK.

  ```js
  const { buildSync } = createRequire(import.meta.url)(process.argv[2]);
  buildSync({
    entryPoints: ['lib/subagent-cli-extension.ts'],
    outfile: 'pi-web-native-subagents/subagent-cli-extension.js',
    bundle: true,
    platform: 'node',
    format: 'esm',
    packages: 'external',
  });
  ```

  Import `createRequire` from `node:module` in the build helper. Pass the fixed
  SDK's `node_modules/esbuild` path from Nix `postBuild`. Include the artifact in
  npm package files and declare it under `pi.extensions`. Preserve the existing
  packaged SDK symlinks and add a disposable extension-load install check.
- [ ] Replace the three registrations in `subagents.nix` with the packaged
  native entry and empty package skill/prompt/theme filters. Move the managed
  native settings there from `web.nix`, enabling the feature with limit four.
  Keep the source of role data build-only and copy its license into the output.
  Do not delete old downloaded packages, metadata, or worktrees. Leave unused
  old package recipes as rollback material unless separately requested to remove
  them; they are no longer part of the active delegation configuration.
- [ ] Update the selective-delegation policy and `/review` to exact native tool
  and role names, structured tickets, explicit writer revisions, the enforced
  limit, and verified close. Keep native routing in the shared guidance rather
  than editing the official package's skills.
  Preserve unrelated Superpowers behavior and existing model settings.
- [ ] Update validation guidance to the new runtime and remove the obsolete gate
  asserting native tools are disabled. Replace the README's old deployment guide
  with accurate new usage after validation; keep the design/plan labelled pending
  until their execution gates pass. Format only task Nix/Markdown/source files,
  stage new files before Git-flake checks, and inspect the task-only diff.
- [ ] Run focused package tests and configured LSP diagnostics on affected source
  files in the disposable checkout. Diagnose missing LSP commands as configuration
  errors, not passing checks. Obtain the selected workflow's independent review
  of the actual task diff, fix defects, and commit task changes before activation.

#### Task 8: Verify the committed migration and activate only locally

**Files:** No new implementation files. Repair only defects caused by this change
and rerun their affected checks. The task checkout and its commits remain the
source of truth while the original checkout's index contains unrelated changes.

- [ ] Check spec coverage, native test results, patch applicability, file
  responsibilities, and the final independent review. Confirm that all intended
  changes are committed and no task changes are uncommitted. Do not stage, reset,
  or merge over the original checkout's occupied index.
- [ ] Reconfirm the execution host if its identity has become uncertain, require
  `nixosConfigurations.citrus`, and record the expected system store path and
  network/failed-unit/Pi Web baseline. End old children before changing deployed
  delegation packages. Do not reload the active migration session.
- [ ] Use the required rebuild's evaluation, package build, type checks, and
  `npm test`, rather than prebuilding the same system output:

  ```sh
  sudo nixos-rebuild test --flake /tmp/nixos-pi-unified-subagents.4lLknp/checkout#citrus --no-write-lock-file
  ```

- [ ] After test activation, check network connectivity, failed system and user
  units, Pi Web service health, loopback listeners, and the canonical `/pi/` page,
  assets, and event stream. In new disposable CLI/Web sessions, verify deployed
  native tool/role discovery and the tested synthetic-provider lifecycle. Confirm
  managed settings and other configured extensions still load. A failed required
  gate blocks switch; do not substitute mocked tests for these deployment checks.
- [ ] Only after those gates pass, switch the same committed configuration:

  ```sh
  sudo nixos-rebuild switch --flake /tmp/nixos-pi-unified-subagents.4lLknp/checkout#citrus --no-write-lock-file
  ```

- [ ] Repeat network, unit, and affected-service checks after switch. Confirm both
  `/run/current-system` and `/nix/var/nix/profiles/system` match the tested store
  path. Report task commits, clean task status, local live/boot-default outcomes,
  the retained original index and worktrees, and any blocked integration. Do not
  push, publish, deploy remotely, or automatically clean old artifacts.

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
| Pi Web | `https://orange.tail1e65cd.ts.net/pi/` | [shared/pi/web.nix](home/keewai/shared/pi/web.nix)、[web.nix](hosts/orange/services/web.nix) |
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
| [brave-origin/](pkgs/brave-origin/) | Nixpkgs の Brave Origin に日本語設定を追加 |
| [cua-driver/](pkgs/cua-driver/) | デスクトップ操作用ドライバーの実行環境 |
| [fprintd-cs9711/](pkgs/fprintd-cs9711/) | CS9711 指紋センサーと認証キャンセルの修正 |
| [hyprland/](pkgs/hyprland/) | 入力メソッドの修飾キー処理の修正 |
| [pi-coding-agent/](pkgs/pi-coding-agent/) | 標準 ChatGPT 接続のキャッシュ用ヘッダーと会話・接続の識別子を分離 |
| [pi-tasks/](pkgs/pi-tasks/) | TODO 管理の固定版と、ネイティブ委任を重複させない登録フィルター |
| [pi-web/](pkgs/pi-web/) | 固定ソースからの Pi Web ビルド、`/pi/` 対応、同梱フォント、修正版 Pi SDK と端末の実行環境 |

keyd が集約するのは処理対象の入力だけです。Citrus ではマウス入力を保つため、
[input-method-shortcut.nix](hosts/citrus/input-method-shortcut.nix) で Logitech の機器を対象外にしています。
対象外の機器から届くキー入力にも、別デバイスで押している Shift・Ctrl を IME へ引き継ぐため、
Hyprland の IME パッチを維持します。keyd による主キーボードの集約だけでは、このパッチを代替できません。

パッチは対象パッケージと同じディレクトリに置きます。
上流を更新するときは、パッチの前提と付属のテストも確認してください。
`keewai704` 所有の GitHub 入力は `main` ブランチを明示し、リビジョンとハッシュを固定します。

Hyprland 本体は IME 修正のため独自ビルドしますが、Aquamarine などの依存関係は上流のパッケージ定義を使います。
既存の NixOS 公式・`hyprland.cachix.org`・Chaotic のバイナリキャッシュを利用し、独自ビルドは必要な修正に限定します。

### Apple Music クライアント

Apple Music クライアントの実装、Nix パッケージ、Home Manager モジュールは
[keewai704/siora](https://github.com/keewai704/siora) で管理します。
このリポジトリでは [apple-music.nix](home/keewai/desktop/apple-music.nix) からそのモジュールを取り込みます。

## 適用せずに設定を確認する

通常は変更したファイルの整形・構文確認と、変更箇所に必要な確認だけを行います。
`nix flake check` や全ホストのビルド、変更前後の評価比較を毎回実行する必要はありません。
ローカル適用時には `nixos-rebuild test` のビルドを利用し、同じ出力を事前にビルドし直しません。

検証範囲の選び方と、エラー時だけ必要な評価値を前後比較する手順は、
リポジトリ専用スキル [nixos-validation](.agents/skills/nixos-validation/SKILL.md) にまとめています。
`$nixos-validation` で呼び出せます。全ホストへ配布する `skills/` には含めません。
配置は Pi の[スキル探索の仕様](https://pi.dev/docs/latest/skills)に従っています。

適用手順は [AGENTS.md](AGENTS.md) に従います。
設定変更を実機へ適用する場合は、コミット後に現在のホストで `test`、稼働確認、
`switch`、再確認の順に進めます。別ホストへの接続・適用は、その操作の明示的な依頼がある場合に限ります。

## アプリの使い方と開発環境

日常操作を確認するときに開いてください。構成や編集先は上の一覧からたどれます。

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
<summary>開発環境</summary>

### 開発環境

```sh
nix develop --no-write-lock-file
```

[devshell/default.nix](devshell/default.nix) で Nix・Lua・Bash の言語サーバー、
フォーマッター、静的解析ツールを提供します。エディター固有の設定は含みません。

</details>
