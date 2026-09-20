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
| 画面ロックとアイドル時の動作 | [desktop/hypr-island.nix](home/keewai/desktop/hypr-island.nix) |
| 日本語入力と切り替えキー | [desktop/input-method.nix](home/keewai/desktop/input-method.nix)、[modules/input-method-shortcut.nix](modules/input-method-shortcut.nix) |
| 端末 | [desktop/kitty.nix](home/keewai/desktop/kitty.nix) |
| ブラウザーと既定の URL ハンドラー | [desktop/browser.nix](home/keewai/desktop/browser.nix)、[firefox.nix](home/keewai/desktop/firefox.nix) |
| ファイル管理、圧縮、XDG フォルダー | [desktop/file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Bitwarden と SSH エージェント | [desktop/bitwarden.nix](home/keewai/desktop/bitwarden.nix) |
| デスクトップのパネルとランチャー | [desktop/hypr-island.nix](home/keewai/desktop/hypr-island.nix) |
| Discord クライアントとテーマ | [desktop/legcord.nix](home/keewai/desktop/legcord.nix)、[legcord-system24.nix](home/keewai/desktop/legcord-system24.nix) |
| Steam と Millennium | [hosts/citrus/steam.nix](hosts/citrus/steam.nix)、[desktop/steam-theme.nix](home/keewai/desktop/steam-theme.nix) |
| 共通の色、フォント、壁紙 | [themes/tokyo-night-black/default.nix](themes/tokyo-night-black/default.nix) |
| Orange の保存先、ポート、URL | [hosts/orange/settings.nix](hosts/orange/settings.nix) |

個人のアプリには、まず Home Manager の `programs.*` / `services.*` を使います。
対応モジュールが必要な動作を満たさない場合は `home.packages` に置きます。
ログイン、PAM、ドライバー、USB のアクセス権、システムデーモンなどは NixOS 側で管理します。

たとえば、Hyprlock の見た目と起動は hypr-island の Home Manager モジュール、
認証に必要な PAM は [hosts/citrus/hypr-island.nix](hosts/citrus/hypr-island.nix) が読み込む
hypr-island の NixOS モジュールが担当します。
Apple USB CLI は [shared/apple-device-usb.nix](home/keewai/shared/apple-device-usb.nix)、
実機の usbmuxd は [hosts/citrus/apple-device-usb.nix](hosts/citrus/apple-device-usb.nix) が担当します。
指紋認証は fprintd が有効な環境でだけ使います。

パネル本体、Island のキー操作、ロックとアイドル制御、Stylix 連携、Bitwarden の初期設定ランチャーは
外部入力の [hypr-island](https://github.com/keewai704/hypr-island) が管理します。
このリポジトリには有効化、テーマの元データ、接続先 URL、機器の差分を置きます。
公開済みの Nix オプション名 `programs.dynamic-island` は互換性のため維持しています。

Home Manager は `useUserPackages = true` で NixOS に統合されています。
ユーザーのパッケージは `/etc/profiles/per-user/keewai` に入り、適用には NixOS の再構築を使います。
パッケージの所有場所を変えても、アプリの実行権限やサンドボックスは変わりません。

## Pi・MCP・スキル

| 場所 | 役割 |
| --- | --- |
| [shared/pi/default.nix](home/keewai/shared/pi/default.nix) | 全ホスト共通の Pi 設定の入口 |
| [shared/pi/agent.nix](home/keewai/shared/pi/agent.nix) | 本体・実行環境、モデル、ローカル拡張と指示の配布 |
| [shared/pi/codex-conversion.nix](home/keewai/shared/pi/codex-conversion.nix) | Pi Codex conversion の導入、補助バイナリ、ツール・Remote context management・互換設定 |
| [shared/pi/mcp.nix](home/keewai/shared/pi/mcp.nix) | Pi MCP アダプターの導入、共通 MCP サーバーの登録と設定変換 |
| [shared/pi/lsp.nix](home/keewai/shared/pi/lsp.nix) | Pi LSP 拡張の導入、言語サーバーと診断設定 |
| [shared/pi/web-search.nix](home/keewai/shared/pi/web-search.nix) | Pi Web 検索拡張の導入、検索・取得経路、CLI / Web 共通の設定ファイル |
| [shared/pi/web.nix](home/keewai/shared/pi/web.nix) | Pi Web の導入、ユーザーサービス、ホストごとの tailnet 許可 |
| [shared/pi/web-agents/](home/keewai/shared/pi/web-agents/) | Pi Web 内蔵サブエージェントの有効化、役割、モデル、推論設定 |
| [shared/pi/APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) | 全プロジェクト共通の追加システム指示 |
| [shared/pi/extensions/](home/keewai/shared/pi/extensions/)、[prompts/](home/keewai/shared/pi/prompts/) | キャッシュ監視・Jev 分析・CLI 完了通知のローカル拡張、レビュー用プロンプト |
| [desktop/pi/default.nix](home/keewai/desktop/pi/default.nix) | デスクトップ専用連携の入口 |
| [desktop/pi/cua.nix](home/keewai/desktop/pi/cua.nix) | デスクトップ操作用ドライバーと MCP |
| [desktop/pi/jev-computer/](home/keewai/desktop/pi/jev-computer/) | Jev と Linux AT-SPI の限定アクセシビリティ操作ループ |
| [desktop/pi/jev-browser/](home/keewai/desktop/pi/jev-browser/) | Jev と Browser Harness の導入、Pi の限定ブラウザー操作ツールとランナー |
| [shared/skills.nix](home/keewai/shared/skills.nix)、[skills/](skills/) | Pi 以外とも共有できる個人スキルの配布と編集元 |
| [shared/typesafe.nix](home/keewai/shared/typesafe.nix) | Jev と Pi プラグインが共有する TypeSafe 認証ファイルの場所 |
| [pkgs/pi-coding-agent/](pkgs/pi-coding-agent/)、[pkgs/pi-web/](pkgs/pi-web/) | アプリ本体のビルド定義とパッチ |
| [modules/common.nix](modules/common.nix) | ログイン前にもユーザーサービスを起動するための linger |
| [citrus/web.nix](hosts/citrus/web.nix)、[orange/services/web.nix](hosts/orange/services/web.nix) | 既存の Tailscale Serve と nginx による HTTPS 公開 |

共通プロフィールは `shared/pi/`、デスクトッププロフィールは追加で `desktop/pi/` を読み込みます。
設定を追加するときは、既存の機能別ファイルへ追記するか、同じディレクトリに名前の明確な
モジュールを作り、その `default.nix` の `imports` に追加します。
拡張のバージョン・読み込み対象は、その機能を担当するモジュールで設定と一緒に管理します。
`settings.packages` の `lib.mkOrder` は従来の Codex conversion → MCP → Web 検索 → LSP の
読み込み順を保つための指定です。Codex conversion のバージョンは補助バイナリと同じ定義を参照します。
ローカル拡張は `extensions/`、プロンプトは `prompts/` に置いて `agent.nix` から配布します。
共有スキル・TypeSafe 認証、パッケージのビルド、OS の公開設定は Pi 専用設定と役割が異なるため、
上表の担当場所に残します。配置の整理で `~/.pi/agent` などの配布先やホストごとの有効機能は変えません。

Codex CLI、Remote Control、ChatGPT Desktop とそのブラウザー・URL 連携は導入しません。
Pi の `openai-codex` は ChatGPT 契約で接続するプロバイダー名であり、Codex CLI は必要ありません。
認証と過去の会話など、旧アプリのユーザーデータやロールバック用の旧世代は自動削除しません。
設定を変える場合は、このリポジトリの編集元を変更してください。
`~/.pi/agent` の Nix 管理対象ファイルや `~/.agents/skills` の生成物は直接編集しません。
Ponytail も他の個人スキルと同じ `~/.agents/skills` に配置します。

### Pi で Astra を使う

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
`exec_command` はこの prefix を使わないため、Pi の `shellPath` に Nix 管理の Bash ラッパーを設定し、
同じ PATH と `pipefail` を維持します。Fish 環境でも存在しない `/bin/bash` にフォールバックしません。
Web の別端末や、指定したシェルを使わない拡張プロセスは対象外です。
`pipefail` により、パイプの前段で失敗した検証を後段の整形処理が成功として隠すことを防ぎます。
`errexit` は強制せず、想定した失敗は呼び出し側で明示的に処理します。
`defaultProjectTrust = "always"` により、すべてのディレクトリを既定で信頼します。
プロジェクトの設定・スキル・拡張は確認なしで読み込まれ、拡張コードはユーザー権限で実行されます。
個別に保存した信頼拒否や明示的な `--no-approve` は Pi 標準の優先順位で適用されます。

既定のモデルは `openai-codex/gpt-6-astra`、推論は `xhigh`、コンテキスト上限は 872,000 です。
モデル選択は制限せず、必要なら Pi 標準の操作で変更できます。
自動コンパクションを有効にし、応答用に 131,072 トークン、要約時の直近履歴に 32,768 トークンを確保します。
Pi 本体は flake.lock の Nixpkgs に固定された 0.85.1 を使います。
標準の ChatGPT 接続にはキャッシュ用ヘッダーを本文のキーに合わせる小さなパッチを適用しています。
Pi Codex conversion が読み込まれる場合は、拡張自身の上流プロバイダー実装をそのまま使います。
`@howaboua/pi-codex-conversion@3.0.34`、`pi-mcp-adapter@2.34.0`、`pi-web-access@0.30.0`、`@narumitw/pi-lsp@0.49.7` は
Pi 標準のパッケージ管理で初回起動時に取得し、npm の lifecycle scripts を無効にします。
拡張のバージョン指定は Nix 管理で、取得した依存関係とロックは `~/.pi/agent/npm/` に保存されます。
この npm 依存関係のロックは flake.lock には含まれません。

[Pi 0.86.0](https://github.com/earendil-works/pi/blob/v0.86.0/packages/coding-agent/CHANGELOG.md) は
プロバイダーへ渡すシステム指示・ツール定義を `TranscriptContext.messages` 内へ移しました。
Codex conversion 3.0.34 は旧形式の `context.systemPrompt` / `context.tools` を参照するため、
0.86.0 の正規化処理と拡張のリクエスト生成を組み合わせた通信なしの検証で、指示とツールの欠落を確認しています。
本体だけの更新は保留し、拡張の対応後に指示・ツール・Remote コンテキスト管理と Pi Web の互換性を検証して更新します。

[Pi Codex conversion](https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion) は
公開 npm パッケージを改変せず、CLI と Pi Web の両方で読み込みます。Codex CLI の導入は不要です。
Codex 対象モデルでは **Structured adapter** と実験的 **Context management: Remote** を使います。
追加ツール専用モードでは context management が無効になるため、`read / bash / edit / write` は
`exec_command / write_stdin / apply_patch / view_image` に置き換わります。
`grep / find / ls`、MCP・検索・LSP・サブエージェントは維持します。非対象モデルでは通常の Pi ツールに戻ります。

Remote は Codex のサーバー側 history / notes を暗号化された契約で利用し、
`history / notes / new_context / get_context_remaining` でコンテキストの引き継ぎを行います。
**Hybrid compaction** も有効にし、対応する Codex 接続では Responses compaction V2 の暗号化チェックポイントを
ノートと併用します。単独の `responsesCompaction` は無効のままですが、Hybrid 経由で V2 を使用します。
自動コンパクションは有効のままで、しきい値ではノート保存を促し、`new_context`・手動 `/compact`・
コンテキスト超過の回復で圧縮します。既存の会話は有効化だけで切り捨てず、元の Pi JSONL も残します。
Remote を利用したセッションの再開時は同じ設定を維持してください。途中で無効にすると分離した履歴が再結合し得ます。
サーバー機能や認証に問題があっても、別の保存方式へ黙って切り替えません。
非対応の接続には Remote は適用されず、暗号化チェックポイントの他プロバイダーへの可搬性も保証されません。
Remote と独立した Parallel Pi summary は併用せず、追加のローカル要約要求は行いません。

Code / Notebook、Heavy system prompt overwrite、自動推論レベル変更、Fast Mode、
キャッシュ keepalive と強制 WebSocket は有効にしません。既存のモデル・推論設定を維持します。
音声・GipPity LAN サーバーは起動せず、新しい待受け・ファイアウォール・外部公開も追加しません。
特に Orange で `/codex voice server` による別ポート公開を行わないでください。

NixOS では同梱 Linux バイナリをそのまま実行できないため、
[pi-codex-conversion-helpers](pkgs/pi-codex-conversion-helpers/default.nix) で同じ固定版から補助バイナリを取り出し、
動的リンクだけを Nix Store のライブラリに合わせます。上流の `tools.customRustBinariesDir` で指定し、
導入済み npm ファイルや拡張の JavaScript は変更しません。補助バイナリは一般の PATH に追加しません。
`/codex` で設定・利用状況を確認できますが、永続設定は
[codex-conversion.nix](home/keewai/shared/pi/codex-conversion.nix) を編集してください。
Nix 管理のグローバル設定を UI から保存したり、プロジェクト設定で上書きしたりしません。
適用後、既存の Pi セッションは `/reload` で読み込みます。

MCP は共有レジストリから、そのホストに定義されたすべてのサーバーを有効にします。
共通の `context7`、`nixos`、`openaiDeveloperDocs`、`serena` に加え、デスクトップでは `cua-driver` も使えます。
初回はツール情報を取得し、以降は必要時に接続します。共有設定へ追加したサーバーも Pi 側に反映されます。
`defaultTools` は Linux の全組み込みツール `read / bash / edit / write / grep / find / ls` を選びます。
Codex adapter の対象モデルでは上記のツール置換が適用されます。
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
親では Astra、通常の子では Luna を使い、検索のためのモデル変更や他社への自動フォールバックは行いません。
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

作業分担と独立レビューは [Pi Web 内蔵サブエージェント](#pi-web) に一本化します。
Web では明示的な委任依頼なしで自動利用し、CLI の Pi にサブエージェント機能は追加しません。
CLI / Web 共通の `/review` は、Web では独立した `reviewer` の結果も回収して確認します。
内蔵ツールを利用できない場合は親が直接レビューし、その制限を報告します。

システム指示とツール定義を不用意に変えず、毎ターンの日付・Git 状態の注入、履歴の書き換え、定期的な空要求は行いません。
Pi Codex conversion の通信実装に合わせ、キャッシュキーは上流のセッション単位の扱いを使います。
旧 `astra-cache` の作業ディレクトリ単位のキー上書きは、拡張が作る HTTP ヘッダーと不整合になるため撤去しました。
既存セッションの保存先や ID は変更しません。新規セッション間のキャッシュ共用は強制しません。
同じ仕事は `pi -c` で続け、モデル・推論レベル・拡張の変更や `/compact` は必要な場合に使います。
フッターの `CH` は直近要求の再利用率です。`/cache` は直近応答と選択ブランチの累計を分けて表示し、
再利用・新規キャッシュ書き込み・未キャッシュの入力トークン数を確認できます。
累計は全モデル・圧縮前も含む報告済み使用量を入力トークンで重み付けし、
通常応答・ツール内呼び出し・Pi 要約・Remote 圧縮 V2 の内訳も表示します。
V2 の使用量は拡張が保存する圧縮メタデータから読み、別途実行された Pi 要約の使用量とは分けて加算します。
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

内蔵サブエージェントは `Agent` で起動し、`get_subagent_result` で結果を確認、
`steer_subagent` で実行中の子に追加指示を送ります。バックグラウンド実行、再開、
モデル指定、文脈継承、worktree 分離は内蔵機能を使います。
[web-agents/](home/keewai/shared/pi/web-agents/) で有効化、親セッションごとの最大同時実行数4、4役を管理します。

| 役割 | 用途 | モデル | 推論 |
| --- | --- | --- | --- |
| `explore` | 読み取り専用のコード調査 | `openai-codex/gpt-5.6-luna` | `high` |
| `plan` | 読み取り専用の計画・リスク整理 | `openai-codex/gpt-5.6-luna` | `max` |
| `general-purpose` | 実装・検証 | `openai-codex/gpt-5.6-luna` | `max` |
| `reviewer` | 差分・呼び出し元の独立レビュー | `openai-codex/gpt-5.6-luna` | `max` |

親の Astra・`xhigh` と全ツール設定は維持します。全役を既定でバックグラウンド実行し、
独立した文脈と組み込みツールだけを使います。拡張・スキルは自動読み込みせず、Web 検索や
MCP / LSP に依存する検証は親が担当します。子にも適用される AGENTS.md を読むよう指示し、
実装・計画・レビュー時は必要な Ponytail を読みます。`reviewer` は Git の実際の差分を
確認するためシェルを使いますが、変更操作は禁止します。この指示は OS の読み取り専用隔離ではありません。

[APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) により、調査・計画・実装・レビューを
伴う通常の依頼は毎回、早い段階で有用な部分を自動委任します。単なる応答や即答には子を起動せず、
ユーザーの明示的な無効化指示を優先します。独立した作業だけを並列化し、親は重複しない仕事を進めます。
変更後は新鮮な文脈の `reviewer` に実際のタスク差分と呼び出し元を確認させ、結果を回収・検証してから
コミットや完了報告へ進みます。失敗時は制限を報告して親が補完し、独立レビュー済みとは扱いません。
役割と目的を進捗で示し、子セッションの通知・結果取得・再開を使います。子から再帰的にチームは作りません。

各依頼には対象 checkout・入力・担当範囲・受け入れ条件を渡し、並列編集は別 worktree に分離します。
未コミットの入力が別 worktree に自動転送されるとは扱いません。自動委任は監査を変更作業にしたり、
リモート操作・公開などの権限を広げたりしません。統合・ステージ・コミット・ローカル適用・公開は親が担当します。
子の要求も ChatGPT の利用枠を消費します。自動利用はモデルへの常設指示であり、毎ターンの強制起動や
追加の常駐ループではありません。

上流の役割検出は個別ファイルのシンボリックリンクを対象にしないため、
`~/.pi/agent/agents` ディレクトリ全体を Home Manager からリンクします。
役割や有効化設定を Web 画面から書き換えず、`web-agents/` を編集して適用します。
初回移行時に既存の未管理ディレクトリがある場合は内容を確認して退避し、自動上書きしません。
旧拡張の取得済み npm ファイル・実行履歴・認証情報は自動削除しません。
既存セッションは `/reload`、または新規セッションの開始で新しい構成を読み込みます。

再起動で実行主体を失った子は、保存履歴の `running` / `queued` を稼働の証拠にせず、
`interrupted` として表示します。履歴を書き換えず、同じ子セッション ID を `Agent` の
`resume` に渡して再開できます。実際に動いている子・待機中の子はランタイムの状態を優先し、
一覧・詳細・検索・結果取得で状態をそろえます。この修正と回帰テストは
[interrupted-subagents.patch](pkgs/pi-web/interrupted-subagents.patch) で管理します。

状態確認は `systemctl --user status pi-web`、ログは `journalctl --user -u pi-web`、
再起動は `systemctl --user restart pi-web` です。
ソース、npm 依存関係、フォントは固定し、Nix のビルド中にネットワークからフォントを取得しません。

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
| [browser-harness/](pkgs/browser-harness/) | Jev のブラウザー接続と Python 依存関係、Linux の Brave 検出 |
| [jev-ultrafast/](pkgs/jev-ultrafast/) | 固定した Jev ソース、ローカル inspector、上流のオフラインテスト |
| [cua-driver/](pkgs/cua-driver/) | デスクトップ操作用ドライバーの実行環境 |
| [fprintd-cs9711/](pkgs/fprintd-cs9711/) | CS9711 指紋センサーと認証キャンセルの修正 |
| [hyprland/](pkgs/hyprland/) | 入力メソッドの修飾キー処理の修正 |
| [pi-coding-agent/](pkgs/pi-coding-agent/) | 標準 ChatGPT 接続のキャッシュ用ヘッダーと会話・接続の識別子を分離 |
| [pi-codex-conversion-helpers/](pkgs/pi-codex-conversion-helpers/) | 上流拡張を改変せず使うための NixOS 用ネイティブ補助バイナリ |
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
<summary>TypeSafe の共有認証（Jev / Pi プラグイン）</summary>

### TypeSafe の共有認証

TypeSafe の API キーは `~/.config/typesafe/api-key` にキー本体だけを1行で保存します。
`TYPESAFE_API_KEY=` のような変数名や引用符は付けません。
キーはユーザーが管理する通常ファイルで、Git・Nix Store・Pi の設定 JSON には入れません。
ホスト間でキーを同期しません。

```sh
install -d -m 700 ~/.config/typesafe
touch ~/.config/typesafe/api-key
chmod 600 ~/.config/typesafe/api-key
```

ローカルのエディターでキーを設定します。ディレクトリは `700`、ファイルは `600` を保ちます。
Home Manager は秘密値ではなく `TYPESAFE_API_KEY_FILE` にファイルの絶対パスだけを設定します。
新しいログインセッションの Pi CLI と Pi Web が同じ場所を参照できます。
既存の端末・Pi は環境変数を引き継ぐため、再ログインしてから起動し直してください。

今後の Pi プラグインは `process.env.TYPESAFE_API_KEY_FILE` を読み書き先に使います。
未設定時は `${XDG_CONFIG_HOME:-~/.config}/typesafe/api-key` を使います。
設定画面で受け取ったキーは、同じディレクトリの権限 `600` の一時ファイルへ書き、
rename で置き換えてください。キーを会話・ツール引数・ログ・セッション履歴へ保存せず、
API 呼び出しの都度読み直します。ログ・検索用の Jev 拡張もこの共有ファイルを利用します。

`jev` の起動ラッパーが共有ファイルを読み、上流標準の `TYPESAFE_API_KEY` 環境変数で渡します。
Jev 本体へのパッチはありません。プラグインからキーを変更した後は、Jev を再起動してください。
優先順位は、明示的な `TYPESAFE_API_KEY` 環境変数、共有ファイル、Jev の `.env` の順です。
共有運用ではキーを二重管理しないよう、Jev の `.env` の `TYPESAFE_API_KEY` は空のままにします。

</details>

<details>
<summary>Jev でログの一次切り分け・検索結果の順位付け</summary>

### Pi の Jev 分析ツール

全ホストの Pi CLI / Pi Web に `jev_log_triage` と `jev_search_rank` を配置します。
[shared/pi/agent.nix](home/keewai/shared/pi/agent.nix) が
[jev-analysis.ts](home/keewai/shared/pi/extensions/jev-analysis.ts) を配布します。
ブラウザー、追加の npm パッケージ、文字生成モデル、常駐サービスは不要です。
適用後、既存の Pi は `/reload` で読み込みます。Jevの指定や呼び出しごとの確認は不要です。
ツールの標準指示で、単純でないビルド・テスト・コマンドの失敗と、複数の検索候補に対して積極的に使います。
主モデルが同じ分類・比較に多くのトークンを使う前にJevへ任せ、選ばれた根拠や上位候補から確認します。
ログは必要な抜粋だけ、検索は短い説明文の候補をまとめて1回で渡し、順位付けのためだけに全文を取得しません。
自明な失敗、単一候補、必要な情報源が既に明確な場合は省略し、入力が同じなら結果を再利用します。
根拠不足・矛盾があれば読む範囲を広げ、必要な検証を削って節約しません。トークン削減率は未測定です。
エージェントの選択方針であり、すべてのログ・検索を捕捉する常駐フックではありません。

- 「この公開ビルドの失敗を調べて」
- 「このテーマを調べて、根拠のURLも示して」

`jev_log_triage` には連続したログ抜粋、出典ラベル `source`、元の開始行 `firstLine` を渡します。
ツール自体はファイルを読みません。最大200行で、送信する構造化データ全体は24,000 UTF-8バイトまでです。
途中の行を黙って省略せず、必要な範囲を明示して渡します。マスキングする場合も行数を保ち、出典ラベルに明記します。
出典ラベルはTypeSafeへ送りません。
失敗の確率、原因分類と確信度、選んだ根拠の1行と前後最大2行を返します。
情報不足や低確信度では `inconclusive`、それ以外も `tentative` であり、原因の確定ではありません。
確信度0.6などのしきい値は未校正の目安です。元ログの確認、終了コード、実際の検証を置き換えません。

`jev_search_rank` には検索語と、取得済みの1〜20候補の `id / url / title / snippet` を渡します。
先に既存の `web_search` / `get_search_content` で実際の候補を取得し、説明文を創作しません。
検索語と候補全体は24,000 UTF-8バイトまでで、URLの取得や既存の検索結果の書き換えは行いません。
関連度0〜3と確信度を返し、元ID・URL・入力位置を保持します。同点は入力順を維持し、低得点の候補も残します。
関連度は事実確認・情報源の信頼性ではないため、重要な主張は原文で確認します。

この2ツールは利用者の自動利用設定に従い、確認UIなしでもTypeSafeへ送信し、別途API料金が発生します。
公開情報または外部送信が許可された機密を含まない抜粋だけを選び、秘密値・私的情報を渡さないでください。
機密性や送信許可が不明ならJevを使わず通常の解析を続けます。認証不足やAPIエラーでも自動再試行せず通常処理に戻ります。
自動マスキングはありません。ツール引数と結果は通常のPiセッション履歴にも残ります。
ログ・会話履歴の自動収集や書き換え、コマンド実行・修復のフックは追加しません。
`jev_browser` の明示的な依頼・対話承認の条件は変更しません。

認証は明示的な `TYPESAFE_API_KEY`、共有ファイルの順です。ブラウザー用 `.env` は読みません。
送信先はTypeSafe公式APIに固定し、リダイレクトや他社へのフォールバックは認めません。
1回につきAPI要求は1回、応答待ちは最大30秒です。
入力超過は切り捨てず拒否し、失敗・キャンセル時も自動再試行しません。
応答は最大128 KB、結果は最大48 KBに制限します。キャンセル後も送信済みの要求は課金される場合があります。
結果にはAPIの入出力トークン数と、入力100万トークンあたり$0.042・出力無料で計算した概算額を表示します。
これは請求額・残高ではなく、料金改定にも自動追従しません。ChatGPT契約の利用枠とは別です。

</details>

<details>
<summary>Jev と AT-SPI を組み合わせた高速 GUI 操作</summary>

### Jev computer

デスクトップの Pi に `computer_inspect` と `jev_computer` を配布します。既存の `cua-driver` は維持し、
短い状態依存の操作を、主モデルへクリックごとに戻らずツール内で進めます。
高速経路は GTK / Qt の AT-SPI を直接使い、CUA の Hyprland IPC 形式への依存を避けます。
プロセス・コンポジターから対象 PID を特定し、`computer_inspect` に渡してウィンドウ名を確認します。
さらに正確な `window_title` を指定して要素を読み、`jev_computer` に `pid`、`window_title`、目的と候補を渡します。
`computer_inspect` は読み取り専用で、TypeSafe には送信しません。
候補は正確な `role` / `label` の組で、`value` を省略すると最初の公開アクセシビリティ・アクション、
指定すると編集可能なテキスト・フィールド全体の置換です。
同名・同ロールが複数ある場合や無効な要素は操作対象にしません。入力文字列は主モデルが事前に用意し、
Jev は候補選択だけを担当します。別の文字生成モデルやスクリーンショット送信は不要です。
ブラウザーのページ操作には既存の `jev_browser`、既知の固定手順や API / CLI 処理には決定的な処理を使います。

開始時に対象、目的、候補、アクセシビリティ本文・値の TypeSafe 送信と別料金を確認します。
既定は操作ごとの承認で、隔離したテストアプリの自動実行は利用者だけが選択できます。
私的・ログイン済みアカウント情報、秘密値、端末、本番の購入・投稿・削除・権限変更には使いません。
これは OS やネットワークのサンドボックスではなく、公開情報でも機密が混ざる画面は対象外です。
呼び出し元は必要に応じて通常の CUA の画像と突き合わせ、信頼できるネイティブのアクセシビリティ・ツリーに限定します。

各操作の前後で状態を取得し、判断・承認待ちの間に状態が変わった場合も停止します。
同一ユーザーの PID・開始時刻と正確なウィンドウ名に固定し、古い要素トークンを再利用しません。
曖昧な対象、変化なし、部分的な操作結果、低確信度では再試行せず、主モデルへ戻します。
クリック後のツリー変化は進捗の手掛かりであり、目的の達成を保証しません。
0.7 の確信度しきい値は未校正の目安で、安全性の保証ではありません。
座標、キー操作、前面化、アプリ起動、ブラウザーのデバッグ設定への自動切り替えはありません。
AT-SPI ワーカーは実行中だけ専用 stdio 接続で起動し、終了後はそのプロセスを止めて対象アプリを残します。
新しい常駐サービス・待受け・MCP サーバーは追加しません。ブラウザー版 Jev と共有するロックで多重実行を拒否しますが、
通常の CUA や人の入力を遮断するものではないため、同じアプリを並行操作しないでください。

既定は8操作・120秒、最大20候補・20操作・300秒です。観測は最大80要素・16 KB、結果は48 KB未満です。
`expect` は新しい観測で2回連続して確認する述語です。`role` / `label` は正確な一致を使い、
必要なら `value` / `selected` も指定します。`stop_reason: done` と検査結果は独立し、
`unknown` や検査未指定は成功を意味しません。アクセシビリティ検査だけで視覚的・タスク全体の成功を保証しません。
処理時間、Jev 判断時間、要求回数、取得できた利用量に基づく概算料金を返します。速度の倍率は保証しません。
認証・送信制限・応答検証は共有の [Jev 分析実装](home/keewai/shared/pi/extensions/jev-analysis.ts) を再利用します。
適用後、既存セッションでは `/reload`、または新しいセッションで読み込みます。

</details>

<details>
<summary>Jev Ultrafast の起動と認証</summary>

### Jev Ultrafast

デスクトップでは `jev` と `browser-harness` を Home Manager で導入します。
[desktop/pi/jev-browser/default.nix](home/keewai/desktop/pi/jev-browser/default.nix) が導入先です。
既存の Brave Origin を使い、既定の Firefox・URL ハンドラーは変更しません。
サービスの自動起動、外部公開、Pi の MCP 登録は行いません。
両コマンドでは Browser Harness のテレメトリーと更新通知を無効にしています。
更新はこのリポジトリの Nix パッケージ定義で行います。

```sh
install -d -m 700 ~/.config/jev-ultrafast
jev_root=$(dirname "$(dirname "$(readlink -f "$(command -v jev)")")")
cp -n "$jev_root/share/jev-ultrafast/env.example" ~/.config/jev-ultrafast/.env
chmod 600 ~/.config/jev-ultrafast/.env
```

TypeSafe キーは上の[共有認証](#typesafe-の共有認証)で設定します。
Jev の判断は TypeSafe 公式の `https://api.typesafe.ai/v1/systemone` へ送ります。
[TypeSafe の公式仕様](https://docs.typesafe.ai/)では Jev は文字生成を行いません。
TypeSafe キーを `TEXT_MODEL_API_KEY` に流用せず、文字生成を使う場合だけ、別の対応サービスのキーを
この `.env` の `TEXT_MODEL_API_KEY` に設定します。キーがなければ選択・クリックは使えますが、文字入力時に停止します。
テンプレートの文字生成先は OpenRouter の `inception/mercury-2.5` です。
キーを Nix、Git、チャットに書かず、既存の認証ファイルを上書きしないでください。
別の OpenAI 互換サービスを使う場合は `TEXT_MODEL_BASE_URL`、`TEXT_MODEL`、
`TEXT_MODEL_REASONING` も合わせて変更します。API 呼び出しには料金が発生します。

Brave Origin で `brave://inspect/#remote-debugging` を開き、必要な場合だけリモートデバッグを許可します。
接続時の許可ダイアログも自分で確認してください。既存プロフィールのタブとログイン状態にアクセスでき、
実行時にはページの内容や操作履歴がモデル提供元へ送られます。個人情報を含むタスクには注意してください。

```sh
cd ~/.config/jev-ultrafast
jev
```

`http://127.0.0.1:8766` を開き、`Start demo` から操作します。終了は端末の `Ctrl-C` です。
`.env` は起動ディレクトリから読み込み、キーなしでも画面表示までは確認できます。
接続の診断は `browser-harness --doctor`、接続デーモンの停止は `browser-harness --reload` です。
録画は Browser Harness の既定で無効です。モデルの `DONE` だけで成功とは判断せず、結果も確認してください。

### Pi から使う

デスクトップの Pi には `jev_browser` ツールも配置します。既存の Pi は `/reload`、
または新しいセッションで読み込みます。たとえば「Jev でこのテスト用ページの検索フォームを確認して」と
明示して依頼します。通常の検索・API・CLI・回帰テストを置き換える用途ではありません。
Orange には配置せず、常駐サービスや MCP サーバーも追加しません。
開始承認後、普段の Brave Origin が起動済みならそのまま接続し、未起動なら通常のコマンドで起動します。
別プロフィール、headless、デバッグポートなどのブラウザー起動オプションは追加しません。
Pi Web でもユーザーセッションの表示環境を使います。表示環境がない場合は自動で headless に切り替えず停止します。
デバッグ接続は通常の Brave が公開するループバックの接続先だけを使います。
未設定なら `browser_setup_required` で停止するので、利用者自身が `brave://inspect/#remote-debugging` で許可し、
次の実行時の接続ダイアログも確認してください。ブラウザー設定を自動変更したり、許可操作を代行したりしません。

開始時に URL、目的、外部送信と課金の説明を確認し、操作ごとの承認か、隔離したテスト環境向けの自動実行を選びます。
自動実行はモデルの引数では選べません。確認 UI のない実行は拒否します。
操作ごとの承認では、クリック先や文字生成後の実際の入力値を実行前に表示します。
テスト環境かどうかは利用者が確認するもので、技術的なサンドボックスではありません。
私的・ログイン済みアカウントの情報、秘密値、本番の購入・投稿・削除・権限変更には使わないでください。
普段の Brave のプロフィールとログイン状態を共有します。既存タブを操作対象にはしませんが、
専用タブにも同じ Cookie が適用されるため、公開 URL でも私的情報を表示するページは対象にしないでください。
プロフィール・ネットワーク・OS 権限を分離するサンドボックスではありません。

既定は最大12回の判断・120秒、上限は30回・300秒です。時間にはブラウザー起動と操作承認待ちも含みます。
Pi のキャンセルとセッション終了でランナーを停止します。実行ごとの一時的な systemd ユーザースコープで
ランナーと接続デーモンだけを管理し、終了後に停止と接続用一時ファイルの削除を確認します。
Brave を自動起動するときは別のユーザーアプリ単位で起動し、タスクの停止ではブラウザー全体を終了しません。
作成したタブだけを閉じ、既存タブ・通常のプロフィールは削除しません。
Pi が異常終了してもランナーはスコープの制限時間で停止しますが、その場合のタブ・一時ファイルの後片付けは保証しません。
停止処理には数秒の猶予があります。同じ利用者の Jev ツールは排他実行します。
CUA で同じブラウザーを同時操作しないでください。
開始 URL と異なる origin を観測すると、以降のモデル送信と操作を停止します。
リダイレクトそのもの、ページ内 JavaScript、第三者への通信を遮断する機能ではありません。

`expect.urlContains` と `expect.textContains` は終了前に新しく観測した URL・表示本文への文字列検査です。
`agent_status` と `verification.status` を別々に返し、検査を指定しなければ `not_requested`、
最終観測がなければ `unknown` とします。検査成功もタスク全体の正しさを保証しません。
証拠は現在の表示領域の本文6,000 UTF-8バイト・最大20要素（合計4 KiBまで）・最大30操作に限定し、
スクリーンショットや生のモデル要求は保存しません。結果全体が48 KBを超えた場合は証拠を省略し、検査結果を `unknown` にします。
本文・操作要約は Pi の通常のセッション履歴に残ります。失敗やキャンセル後は副作用が起きた可能性を確認し、
自動で再実行しないでください。タブのクローズが確認できなければ `cleanup` にその旨を返します。
`browser_cleanup` は通常のブラウザーを残したこと、`runner_cleanup` はランナー・デーモン停止と接続用一時ファイル削除を示します。
スコープ停止を確認できない場合はエラーにし、調査用のスコープ名・一時ディレクトリを示します。

ランナーは起動ディレクトリによらず `~/.config/jev-ultrafast/.env`（XDG_CONFIG_HOME に対応）を読みます。
TypeSafe キーは既存の共有ファイルを利用し、明示的な環境変数、共有ファイル、`.env` の順に優先します。
文字生成先・認証は上の Jev 設定を再利用し、Pi の ChatGPT 認証を流用しません。
`TEXT_MODEL_API_KEY` が TypeSafe キーと同一なら、別サービスへの誤送信を防ぐため文字生成を拒否します。
モデル呼び出し回数は結果に含めますが、実請求額や残高の表示ではありません。

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
