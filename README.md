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
シェル起動時にロックし、アイドル 600 秒でロック、660 秒で画面を消灯します。
ロック画面のメディア表示は Noctalia 標準のものを使います。
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

## Pi・MCP・スキル

| 場所 | 役割 |
| --- | --- |
| [shared/pi/default.nix](home/keewai/shared/pi/default.nix) | 全ホスト共通の Pi 設定の入口 |
| [shared/pi/agent.nix](home/keewai/shared/pi/agent.nix) | 本体・実行環境、モデル、ローカル拡張と指示の配布 |
| [skills/superpowers/](skills/superpowers/) | Superpowers 6.4.1 の Pi / Astra 向けローカルスキル |
| [shared/pi/codex-conversion.nix](home/keewai/shared/pi/codex-conversion.nix) | Pi Codex conversion の導入、補助バイナリ、ツール・Remote context management・互換設定 |
| [shared/pi/mcp.nix](home/keewai/shared/pi/mcp.nix) | Pi MCP アダプターの導入、共通 MCP サーバーの登録と設定変換 |
| [shared/pi/lsp.nix](home/keewai/shared/pi/lsp.nix) | Pi LSP 拡張の導入、言語サーバーと診断設定 |
| [shared/pi/web-search.nix](home/keewai/shared/pi/web-search.nix) | Pi Web 検索拡張の導入、検索・取得経路、CLI / Web 共通の設定ファイル |
| [shared/pi/web.nix](home/keewai/shared/pi/web.nix) | Pi Web の導入、ユーザーサービス、ホストごとの tailnet 許可 |
| [shared/pi/subagents.nix](home/keewai/shared/pi/subagents.nix) | Agent Teams・Crew・Core Subagent の固定版と読み込み対象 |
| [shared/pi/APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) | 全プロジェクト共通の追加システム指示 |
| [shared/pi/extensions/](home/keewai/shared/pi/extensions/)、[prompts/](home/keewai/shared/pi/prompts/) | キャッシュ監視・CLI 完了通知のローカル拡張、レビュー用プロンプト |
| [desktop/pi/default.nix](home/keewai/desktop/pi/default.nix) | デスクトップ専用連携の入口 |
| [desktop/pi/cua.nix](home/keewai/desktop/pi/cua.nix) | デスクトップ操作用ドライバーと MCP |
| [shared/skills.nix](home/keewai/shared/skills.nix)、[skills/](skills/) | Pi 以外とも共有できる個人スキルの配布と編集元 |
| [pkgs/pi-coding-agent/](pkgs/pi-coding-agent/)、[pkgs/pi-web/](pkgs/pi-web/) | アプリ本体のビルド定義とパッチ |
| [modules/common.nix](modules/common.nix) | ログイン前にもユーザーサービスを起動するための linger |
| [citrus/web.nix](hosts/citrus/web.nix)、[orange/services/web.nix](hosts/orange/services/web.nix) | 既存の Tailscale Serve と nginx による HTTPS 公開 |

共通プロフィールは `shared/pi/`、デスクトッププロフィールは追加で `desktop/pi/` を読み込みます。
設定を追加するときは、既存の機能別ファイルへ追記するか、同じディレクトリに名前の明確な
モジュールを作り、その `default.nix` の `imports` に追加します。
拡張のバージョン・読み込み対象は、その機能を担当するモジュールで設定と一緒に管理します。
`settings.packages` の `lib.mkOrder` は Codex conversion → MCP → Web 検索 → LSP → Teams・Crew・Core Subagent の
読み込み順を保つための指定です。Codex conversion のバージョンは補助バイナリと同じ定義を参照します。
ローカル拡張は `extensions/`、プロンプトは `prompts/` に置いて `agent.nix` から配布します。
共有スキル、パッケージのビルド、OS の公開設定は Pi 専用設定と役割が異なるため、
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
Pi 本体は [pi-coding-agent/default.nix](pkgs/pi-coding-agent/default.nix) で 0.87.1 に固定し、
Nixpkgs のビルド定義を使ってソース・npm 依存関係・モデルカタログのハッシュを検証します。
標準の ChatGPT 接続にはキャッシュ用ヘッダーを本文のキーに合わせる小さなパッチを適用しています。
Pi Codex conversion が読み込まれる場合は、拡張自身の上流プロバイダー実装をそのまま使います。
`@howaboua/pi-codex-conversion@3.0.37`、`pi-mcp-adapter@2.34.0`、`pi-web-access@0.30.0`、`@narumitw/pi-lsp@0.49.7`、
`@melihmucuk/pi-crew@1.0.34` は
Pi 標準のパッケージ管理で初回起動時に取得し、npm の lifecycle scripts を無効にします。
拡張のバージョン指定は Nix 管理で、取得した依存関係とロックは `~/.pi/agent/npm/` に保存されます。
この npm 依存関係のロックは flake.lock には含まれません。

[Superpowers 6.4.1](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71)
の全15スキルを、[Astra の公式ガイド](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices)
に合わせたローカル版として [skills/superpowers/](skills/superpowers/) で管理します。
上流リビジョンと MIT ライセンスを保持し、Home Manager が `~/.agents/skills/superpowers/` へ配布します。
Pi の標準探索を使い、`/skill:using-superpowers`、`/skill:brainstorming`、
`/skill:systematic-debugging` などで呼び出せます。開発時は `APPEND_SYSTEM.md` が入口スキルを案内します。
不要な承認待ち、固定回数のレビュー・テスト、別ハーネス専用ツールの指示を調整し、
変更に必要な検証、独立レビュー、許可された作業の完遂を重視します。
Ponytail、利用者の明示指示、AGENTS.md の配置・検証・承認規則を維持します。
上流のブートストラップ拡張、ブラウザー補助、実行スクリプト、会話のエクスポート機能は配布しません。
スキルは npm では取得せず、このリポジトリで更新します。適用後は新しいタスクで読み込んでください。

[Pi 0.86.0](https://github.com/earendil-works/pi/blob/v0.86.0/packages/coding-agent/CHANGELOG.md) は
プロバイダーへ渡すシステム指示・ツール定義を `TranscriptContext.messages` 内へ移しました。
旧形式の `context.systemPrompt` / `context.tools` を参照していた Codex conversion 3.0.34 は使わず、
上流で Pi 0.87 の指示・ツール・圧縮・再開に対応した 3.0.37 と組み合わせます。
Pi 本体の `cacheWarming` は `off` にし、更新によってキャッシュ維持用の追加推論を有効にしません。
Pi Web はビルド時も実行時も同じ Pi SDK を参照し、
[transcript-context.patch](pkgs/pi-web/transcript-context.patch) でタイトル生成・専用システム指示・
セッション一覧の同時刻の並び順を新しい SDK に合わせます。
会話履歴や読み取り専用の `agent.state.systemPrompt` は書き換えません。
Pi Web のラッパーは同じ SDK の場所を `PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT` で伝え、
通常と異なる Nix の配置でもバックグラウンドの子が本体を解決できるようにします。

[Pi Codex conversion](https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion) は
公開 npm パッケージを改変せず、CLI と Pi Web の両方で読み込みます。Codex CLI の導入は不要です。
Codex 対象モデルでは **Code Mode** と実験的 **Context management: Remote** を使います。
追加ツール専用モードは使わず、Pi 既定の `read / bash / edit / write` は
`exec` / `wait` を使う構成に置き換わります。`exec` 内の JavaScript から
`tools.exec_command`、`tools.write_stdin`、`tools.apply_patch`、`tools.view_image` を組み合わせます。
既存の MCP・検索・LSP・サブエージェントなどは維持し、Code Mode の登録 API に対応した拡張だけが
`exec` 内にも公開されます。非対象モデルでは通常の Pi ツールに戻ります。
初回実行では上流が固定した Code Mode ホストをチェックサム検証付きでキャッシュへ取得します。
Notebook Mode は有効にしません。

Remote は Codex のサーバー側 history / notes を暗号化された契約で利用し、
`history / notes / new_context / get_context_remaining` でコンテキストの引き継ぎを行います。
Code Mode では `history`・`notes`・`new_context` は直接呼び出し、残量確認は
`exec` 内の `tools.get_context_remaining` を使います。
**Hybrid compaction** も有効にし、対応する Codex 接続では Responses compaction V2 の暗号化チェックポイントを
ノートと併用します。単独の `responsesCompaction` は無効のままですが、Hybrid 経由で V2 を使用します。
自動コンパクションは有効のままで、しきい値ではノート保存を促し、`new_context`・手動 `/compact`・
コンテキスト超過の回復で圧縮します。既存の会話は有効化だけで切り捨てず、元の Pi JSONL も残します。
Remote を利用したセッションの再開時は同じ設定を維持してください。途中で無効にすると分離した履歴が再結合し得ます。
サーバー機能や認証に問題があっても、別の保存方式へ黙って切り替えません。
非対応の接続には Remote は適用されず、暗号化チェックポイントの他プロバイダーへの可搬性も保証されません。
Remote と独立した Parallel Pi summary は併用せず、追加のローカル要約要求は行いません。

Notebook、Heavy system prompt overwrite、自動推論レベル変更、Fast Mode、
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

作業分担と独立レビューは [Pi の委任拡張](#pi-の委任拡張)を CLI と Web の両方で
明示的な委任依頼なしでも利用します。共通の `/review` は Crew の独立した `code-reviewer` の結果も確認します。
拡張を利用できない場合は親が直接レビューし、その制限を報告します。

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

### Pi の委任拡張

[Agent Teams](https://github.com/tmustier/pi-agent-teams)、
[Crew](https://github.com/melihmucuk/pi-crew)、
[Core Subagent](https://github.com/arhen/pi-extensions/tree/main/packages/core/pi-core-subagent) を
[subagents.nix](home/keewai/shared/pi/subagents.nix) で管理します。
同名の別実装ではなく、上記の scoped npm パッケージを固定して読み込みます。
Teams 0.5.5 は [pkgs/pi-agent-teams](pkgs/pi-agent-teams/default.nix)、Core 1.3.55 は
[pkgs/pi-core-subagent](pkgs/pi-core-subagent/default.nix) で npm 配布物をハッシュ固定します。
Teams には明示ツールリストでも子の `team_message` を有効にする修正を適用します。
さらに Teams の起動時 GC・終了時削除、Core の起動時自動復旧コミット・既存ブランチ掃除を止め、
未統合の worktree とブランチを保持します。後片付けは内容と統合状況を確認し、明示的な許可を得て行います。
Core の取消は子の終了処理後に run を終端状態へ移し、取消直後の resume との競合を防ぎます。
実行時の依存は Pi SDK を使い、Teams と Core の取得に初回起動時の npm は使いません。
旧 pi-subagents のパッケージ・設定・専用 config.json の配布は廃止します。
Pi Web 内蔵側は引き続き `agents/settings.json` の `builtInEnabled: false` で無効にします。

| 拡張 | 主な用途と操作 |
| --- | --- |
| Crew | 通常の委任。`crew_list`、`crew_spawn`、`crew_status`、`crew_respond`、`crew_done`、`crew_abort` |
| Core Subagent | 呼び出しごとの専門役・依存関係付きタスク。`subagent`、`subagent_status`、`subagent_result`、`await_subagent`、`steer_subagent`、`resume_subagent`、`subagent_cancel`、`reply_subagent` |
| Agent Teams | 共有タスク一覧・チーム間メッセージ。`teams` ツール、`/team`、`/swarm` |

Crew の役割は同梱の `scout`、`planner`、`oracle`、`worker`、`code-reviewer`、`quality-reviewer` を使い、
独自プロファイルへ複製しません。`crew_spawn` の `task` は `goal`・`context`・`instructions` を持つ構造です。
結果は自動通知され、確認後に `crew_done` で閉じます。追加指示は完了済み・入力待ちの子に
`crew_respond` で渡します。実行中の子への steering や失敗後の resume と同じ操作ではありません。
同梱スキルと `/pi-crew-plan`・`/pi-crew-review` も読み込み、共通 `/review` は `code-reviewer` を利用します。
同梱の読み取り専用役にも `bash` があり、読み取り専用は指示上の制約であってサンドボックスではありません。
親の Astra・`xhigh` は維持し、Crew のモデル・推論指定は同梱役割に従います。

Core は `subagent({ agent: "auditor", prompt: "...", task: "...", cwd: "..." })` のように役割を渡します。
既定は fresh context・バックグラウンド・読み取り専用で、起動後に一度 status を確認し、完了通知後に result を取得します。
同じ呼び出しの結果を直ちに使う場合は `autoAwait: true`、並列処理は `tasks`、本当の依存関係だけに `needs` を使います。
子は ambient 拡張を読み込まず、モデル未指定なら親のモデルを継承します。旧 pi-subagents の役割・API ではありません。
`bash`・`edit`・`write` を持つ子は Git worktree に分離され、終了時に拡張が自動コミットします。
このリポジトリではコミットを親が担当するため、Core は読み取り専用の委任に使います。
差分レビューでは親が実際の未コミット差分・新規ファイルを渡し、別 worktree に自動転送されるとは扱いません。

Teams は共有タスクとメッセージが必要な場合に選びます。`contextMode: "fresh"` を優先し、
並列編集には `workspaceMode: "worktree"`、使用する名前は `teammates` で明示します。
Crew は親と同じ cwd で起動するため、並列編集では親が用意した checkout への絶対パス操作を指示します。
Crew 自体が cwd を分離する機能ではありません。
Teams の hooks は既定の無効のままとし、追加の自動チェックループは構成しません。
各拡張は異なる状態管理を持つため、同じ仕事を複数へ投入したり ID を使い回したりしません。
Pi Web の旧内蔵一覧がこれらの実行一覧に変わるわけではありません。

[APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) により、調査・計画・実装・レビューでは
早い段階で有用な部分を自動委任します。単なる応答や即答には起動せず、明示的な無効化指示を優先します。
3拡張を合わせて同時4子までという運用方針を守り、再帰的なチームや不要な子は作りません。
これは共通スケジューラーによる強制制限ではありません。Core のバッチには `concurrency: 4` 以下を渡します。
委任しても監査・リモート操作・公開などの権限は広がらず、統合・コミット・適用は親が担当します。
変更後は fresh context の独立レビューを取得し、実際の差分と結果を確認してからコミットします。
失敗時は親が補完し、独立レビュー済みとは扱いません。子もモデルの利用枠を消費します。

Code Mode でも委任ツールは直接呼び出し、未登録の `tools.crew_spawn`・`tools.teams`・`tools.subagent` が
`exec` 内にあるとは仮定しません。拡張・ツールの継承方法は3パッケージで異なるため、
検索や拡張依存の検証は、子の実ツールを確認できた場合以外は親が担当します。
共有設定は Nix の編集元で変更し、パッケージ同梱の役割を管理操作で書き換えません。
`~/.pi/agent/agents` の Pi Web 無効化設定は読み取り専用の Nix Store ディレクトリを維持します。

旧パッケージの取得済み npm ファイル・実行履歴・認証情報は自動削除せず、旧 ID を新拡張へ自動移行しません。
移行前の子を終了してから新しいセッションを開始してください。既存セッションの実行中に `/reload` しません。
旧内蔵履歴の中断表示用 [interrupted-subagents.patch](pkgs/pi-web/interrupted-subagents.patch) は維持します。
新しい実行は選択した拡張のツール結果・状態・子のセッションファイルで確認します。

状態確認は `systemctl --user status pi-web`、ログは `journalctl --user -u pi-web`、
再起動は `systemctl --user restart pi-web` です。
ソース、npm 依存関係、フォントは固定し、Nix のビルド中にネットワークからフォントを取得しません。

### Unified CLI/Web subagents: approved design, not yet implemented

This section records the approved integration design. The preceding sections
describe the currently deployed three-plugin configuration. This design does not
enable the replacement or claim that its implementation or validation is complete.

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
Default to fresh conversation context, background execution, and no recursive
delegation. Load the working directory's applicable repository instructions;
fresh context does not mean dropping `AGENTS.md`. Tool and resource selection must
be explicit and consistent on first start and resume. Tool restrictions and Git
worktrees are not an operating-system sandbox.

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
cross-parent control and recursive spawning by enforcing ownership and child tool
availability, not only by prompting.

Distinguish queued or dependency-blocked work, running work, input required,
completed reports, failure, cancellation, and interruption. A structured report
contains its outcome and complete report text; input requests also state what is
needed. The parent can answer input requests, steer running work, follow up in the
same child session, stop work, and close a verified delivery. Closing releases
runtime resources without deleting the retained session or worktree. Preserve
plain-text results from legacy native sessions.

CLI and Web expose the same task and control semantics. Web presents the task
list, dependencies, progress, messages, and inspectable child conversations; CLI
provides equivalent tool results and compact status output. Existing native
`Agent`, result retrieval, and steering calls remain supported. Code Mode must
keep the native delegation tools directly callable without requiring an
unregistered `tools.*` bridge.

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
role discovery, provider bindings, Code Mode tool availability, both adapter
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
<summary>開発環境</summary>

### 開発環境

```sh
nix develop --no-write-lock-file
```

[devshell/default.nix](devshell/default.nix) で Nix・Lua・Bash の言語サーバー、
フォーマッター、静的解析ツールを提供します。エディター固有の設定は含みません。

</details>
