# nixos-configuration

`citrus`（デスクトップ）と `orange`（サーバー）の NixOS 設定です。
両方とも `x86_64-linux`。機器・OS の統合は NixOS、個人のアプリと設定は Home Manager が担当します。

必要な節から読んでください。変更時の権限・コミット・適用規則は [AGENTS.md](AGENTS.md)、
検証方法は [nixos-validation](.agents/skills/nixos-validation/SKILL.md) が正本です。

- [構成と編集先](#構成と編集先)
- [Pi の指示・スキル・ロール](#pi-の指示スキルロール)
- [Pi の起動とモデル](#pi-の起動とモデル)
- [コンテキスト・TODO・ツール](#コンテキストtodoツール)
- [Pi Web とネイティブ委任](#pi-web-とネイティブ委任)
- [Citrus のデスクトップ](#citrus-のデスクトップ)
- [Orange のサービス](#orange-のサービス)
- [パッケージとローカル適用](#パッケージとローカル適用)

## 構成と編集先

```text
flake.nix
├── modules/common.nix                 全ホスト共通の OS 設定
├── modules/home-manager.nix            NixOS と Home Manager の接続
│   └── home/keewai/common.nix → shared/ 共通の個人設定
└── hosts/<host>/default.nix
    ├── citrus → 機器設定 + modules/desktop.nix → home/keewai/desktop/
    └── orange → ストレージとサーバーサービス
```

| 場所 | 責任・入口 |
| --- | --- |
| [flake.nix](flake.nix)、[flake.lock](flake.lock) | 外部入力、固定リビジョン、ホスト・パッケージ・開発環境の公開 |
| [hosts/citrus/](hosts/citrus/)、[hosts/orange/](hosts/orange/) | 各ホストの機器、起動、サービス。`default.nix` の imports からたどる |
| [modules/](modules/) | 共有する OS 統合。`common.nix` は全ホスト共通のみ |
| [home/keewai/shared/](home/keewai/shared/) | CLI、シェル、Pi など共通の個人設定 |
| [home/keewai/desktop/](home/keewai/desktop/) | GUI アプリ、セッションサービス、テーマ、入力・表示設定 |
| [pkgs/](pkgs/) | パッケージ定義、パッチ、実行時の補助コード |
| [themes/](themes/) | 共通の色、フォント、画像 |
| [secrets/](secrets/) | Agenix の公開鍵設定と暗号化済みシークレット |
| [devshell/](devshell/) | Nix・Lua・Bash の言語サーバー、整形・解析ツール |

`imports = [ ./feature.nix ];` は設定を合流させる入口です。
`pkgs.callPackage ./package { };` はパッケージ定義へ依存関係を渡します。
`lib.mkIf` は条件付き設定、`lib.mkDefault` / `lib.mkForce` は優先順位を指定します。
`system.stateVersion` / `home.stateVersion` は互換性の基準であり、入力更新に合わせて変更しません。

| 変更したい内容 | 主な編集先 |
| --- | --- |
| 共通 CLI、シェル、補完 | [common.nix](home/keewai/common.nix)、[shell.nix](home/keewai/shared/shell.nix)、[starship.toml](home/keewai/shared/starship.toml) |
| 設定のない GUI ツール | [applications.nix](home/keewai/desktop/applications.nix) |
| ウィンドウ・モニター・キー | [hyprland.lua](home/keewai/desktop/hyprland.lua) |
| Hyprland のビルド・ログイン・ポータル | [hosts/citrus/hyprland.nix](hosts/citrus/hyprland.nix) |
| パネル・ランチャー・配色・アイドル | [noctalia.nix](home/keewai/desktop/noctalia.nix) |
| 日本語入力 | [input-method.nix](home/keewai/desktop/input-method.nix)、[input-method-shortcut.nix](modules/input-method-shortcut.nix) |
| 端末・ブラウザー・ファイル管理 | [kitty.nix](home/keewai/desktop/kitty.nix)、[browser.nix](home/keewai/desktop/browser.nix)、[firefox.nix](home/keewai/desktop/firefox.nix)、[file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Bitwarden・SSH エージェント | [bitwarden.nix](home/keewai/desktop/bitwarden.nix) |
| Discord | [legcord.nix](home/keewai/desktop/legcord.nix)、[legcord-system24.nix](home/keewai/desktop/legcord-system24.nix) |
| Steam・Millennium | [hosts/citrus/steam.nix](hosts/citrus/steam.nix)、[steam-theme.nix](home/keewai/desktop/steam-theme.nix) |
| Sunshine・仮想画面 | [hosts/citrus/sunshine.nix](hosts/citrus/sunshine.nix)、[pkgs/sunshine-display/](pkgs/sunshine-display/) |
| 共通テーマ | [tokyo-night-black](themes/tokyo-night-black/default.nix) |
| Orange の保存先・ポート・URL | [hosts/orange/settings.nix](hosts/orange/settings.nix) |

個人アプリは Home Manager の `programs.*` / `services.*`、次に `home.packages` を使います。
ログイン、PAM、ドライバー、デバイス権限、システムデーモンなどの必須統合は NixOS に残します。
例えば Apple USB CLI は [shared/apple-device-usb.nix](home/keewai/shared/apple-device-usb.nix)、
usbmuxd は [hosts/citrus/apple-device-usb.nix](hosts/citrus/apple-device-usb.nix) が担当します。
Home Manager は `useUserPackages = true` で、パッケージは `/etc/profiles/per-user/keewai` に入ります。
所有場所の変更はサンドボックス化や権限削減ではなく、適用も NixOS 再構築のままです。

## Pi の指示・スキル・ロール

指示は目的ごとに一箇所で管理します。README は構成と使い方、AGENTS.md はこのリポジトリの規則です。
すべてを作業のたびに読み込む必要はありません。

| 目的 | 編集元・読み込み先 |
| --- | --- |
| 全プロジェクト共通の振る舞い | [APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md) → `~/.pi/agent/APPEND_SYSTEM.md` |
| 特定操作の手順 | [skills/](skills/) → `~/.agents/skills/`。配布は [shared/skills.nix](home/keewai/shared/skills.nix) |
| このリポジトリだけの検証 | [.agents/skills/nixos-validation/](.agents/skills/nixos-validation/) |
| ネイティブ子エージェントの役割 | [keewai704/pi-web の roles/](https://github.com/keewai704/pi-web/tree/main/roles) → CLI/Web 共通のビルド済みロールデータ |
| 明示的なレビュー依頼 | [prompts/review.md](home/keewai/shared/pi/prompts/review.md) → `/review [対象]` |

指針は [OpenAI: Rethinking skills and prompts for GPT-6 Astra](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
と [Anthropic: Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) に基づきます。

- スキルの説明は「どの操作で使うか」を短く示し、複数手順の詳細は必要な参照だけ読みます。
- 完了条件と権限を明確にし、通常の判断は任せます。毎回の全資料読破、細かな思考手順、固定回数の確認は課しません。
- 自動的な二重レビューや小さな作業の委任を避けます。依頼・適用規則で必要なレビューや具体的な稼働確認は残します。
- レビューは低い重大度も含めて根拠のある問題を挙げ、影響順に整理します。重大な問題だけに限定しません。
- 会話の説明も生成文書も目的に必要な長さにし、進捗は重要な発見・障害・方針変更時に伝えます。

親の既定モデル・thinking・上限・権限は変更しません。子への委任では、後述の省コスト方針に沿って
モデルと thinking を明示します。速度や品質の改善率を実測したという意味ではありません。
生成先を直接編集せず、上表の編集元を変更してください。
反映後は新しいセッションで使います。作業を所有するセッションを途中で reload したり、履歴を書き換えたりしません。

### スキルの選び方

| スキル | 用途 |
| --- | --- |
| `ponytail` | コーディング、明示的な単純化・先行実装の見直し。KISS / YAGNI を含む |
| `superpowers` | 明示依頼、または設計・調整の手順が役立つ仕事。通常の小変更には不要 |
| `add-nix-skill` | Nix 管理の個人スキルの追加・改訂 |
| `add-nix-mcp` | 永続 MCP サーバー設定の追加・変更。既存ツールの呼び出しでは不要 |
| `apple-device-usb` | USB または既にペアリング済みのローカル Wi-Fi 経由で iPhone/iPad を操作 |
| `faster-whisper` | ローカル音声・動画の文字起こし |
| `nixos-validation` | この設定リポジトリの変更検証・失敗診断 |

Pi 標準の `/skill:<名前> <依頼>` で明示的に呼び出せます。
Ponytail は `full` が既定で、会話中に `ponytail lite` / `full` / `ultra`、
`stop ponytail` / `normal mode` で変更・無効化できます。登録済みスラッシュコマンドではありません。

[Superpowers 6.4.1](https://github.com/obra/superpowers/tree/5bf4e78011075bcfc0dc295f0724994cd123ee71)
はローカル適応版です。1つの [入口](skills/superpowers/SKILL.md) から14の参照ワークフローを選び、
全15用途を保持します。個別の旧コマンドや bootstrap 拡張は重ねて登録しません。
上流リビジョンと MIT ライセンスを保持し、会話エクスポート機能は配布しません。

`/review` の対象省略時は staged / unstaged の差分と関連する未追跡ソースが対象です。
生成物・秘密情報は除外し、編集やステージはしません。独立レビューは必要な範囲で使い、
必要なのに利用できない場合はその制限を明示します。

## Pi の起動とモデル

プロジェクト内で `pi` を起動します。初回は `/login` から OpenAI (ChatGPT Plus/Pro) を選択します。
継続は `pi -c`、履歴選択は `pi -r`。認証は `~/.pi/agent/auth.json`、会話・実行時キャッシュも
`~/.pi/agent` に保存します。`openai-codex` はプロバイダー名で、Codex CLI は不要です。
Codex CLI、Remote Control、ChatGPT Desktop は導入しません。旧アプリのユーザーデータは自動削除しません。

| 設定・機能 | 編集元 |
| --- | --- |
| 共通設定の入口 | [shared/pi/default.nix](home/keewai/shared/pi/default.nix) |
| 本体、モデル、標準ツール、個人指示 | [agent.nix](home/keewai/shared/pi/agent.nix) |
| Claude Code / SDK ブリッジ | [claude-bridge.nix](home/keewai/shared/pi/claude-bridge.nix) |
| TODO、MCP、LSP、Web 検索 | [tasks.nix](home/keewai/shared/pi/tasks.nix)、[mcp.nix](home/keewai/shared/pi/mcp.nix)、[lsp.nix](home/keewai/shared/pi/lsp.nix)、[web-search.nix](home/keewai/shared/pi/web-search.nix) |
| Web サービス・委任登録・共有派生 | [web.nix](home/keewai/shared/pi/web.nix)、[subagents.nix](home/keewai/shared/pi/subagents.nix)、[web-package.nix](home/keewai/shared/pi/web-package.nix) |
| ローカルコンテキスト等の拡張 | [extensions/](home/keewai/shared/pi/extensions/) |
| デスクトップ専用 CUA | [desktop/pi/cua.nix](home/keewai/desktop/pi/cua.nix) |
| パッケージ固定・Nix 統合 | [pkgs/pi-coding-agent/](pkgs/pi-coding-agent/)、[pkgs/pi-web/](pkgs/pi-web/)、各 `pkgs/pi-*/` |

本体は Pi `0.87.1`。既定は `openai-codex/gpt-6-astra` / `xhigh`、コンテキスト上限 872,000 です。
モデル選択は制限しません。自動 compaction は有効で、一般設定は応答予約 16,384・直近履歴 20,000、
Astra はモデル別に 131,072・32,768 トークンです。`cacheWarming = "off"` で定期的な追加推論を行いません。
キャッシュ率だけを理由に空要求やプロンプト水増しを行わず、品質・総入力・再作業と合わせて判断します。
フッターのトークン・費用見積もりは ChatGPT 契約の請求額や残枠ではありません。

`defaultProjectTrust = "always"` のため、プロジェクトの設定・スキル・拡張を既定で読み込みます。
保存済みの信頼拒否や `--no-approve` は Pi 標準の優先順位に従います。
拡張はユーザー権限で動作し、プロジェクト信頼やツール制限は OS サンドボックスではありません。

### Claude ブリッジ

[pi-claude-bridge fork](https://github.com/keewai704/pi-claude-bridge) `0.8.0`、Claude Agent SDK `0.3.276`、
Nixpkgs の Claude Code `2.1.276` を組み合わせ、CLI の絶対 Store パスを渡します。
実行時ダウンロードや SDK 同梱の未調整バイナリには依存しません。

`claude auth login` → `claude auth status` で Claude 側の認証を確認し、Pi の `/model` で
`claude-bridge/claude-opus-5-5` などを選びます。Pi の `/login` とは別の認証です。
`plan = "pro"`、長文脈の追加課金は無効。Opus 5.5 は上流ブリッジの未測定モデル規則に従い 200K 登録で、
ガイドの 1M という仕様を理由に強制拡大しません。利用権・課金は Claude 側の契約に従い、費用表示 0 は無料の保証ではありません。

`AskClaude` は無効で、委任は native Agent、TODO は pi-tasks、指示・ツール・compaction は Pi が所有します。
Claude 独自の MCP・スキル探索・自動メモ・compaction は使いません。
fork はモデル登録を環境ごと、実行状態をセッションごとに分離し、子の cwd/指示も Pi から取得します。
プロジェクト別ブリッジ設定と Claude HTTP の `onPayload` / `onResponse` 監視・書き換えには対応しません。
各問い合わせを Pi 履歴から再構成するため、上流とキャッシュ効率が異なる場合があります。
認証と SDK の一時会話は `~/.claude`、元の履歴は Pi JSONL に残します。既存 Claude 会話は削除しません。
パッケージ読み込みや合成テストは実認証・モデル利用権・実推論の証明ではありません。

## コンテキスト・TODO・ツール

### ローカルコンテキストと TODO

[local-context.ts](home/keewai/shared/pi/extensions/local-context.ts) は、元の JSONL を保持したまま
選択中のセッション・ブランチから必要な履歴だけ取得します。OpenAI の暗号化チェックポイントの再実装ではありません。

- `context_notes`：目標、権限、選択、出典を明示メモとして保存。自動要約とは別です。
- `context_history_search` / `context_history_read`：件数・文字数を制限した原文検索と取得。
  entry/window ID と続き位置を返します。window は compaction 境界の時系列区間で、過去のモデル入力の完全な複製ではありません。
- 思考・画像・ツール引数・非公開メタデータ・他拡張の不透明な状態は対象外ですが、通常テキスト内の秘密を万能に除去する機能ではありません。

自動 compaction と `/compact` は維持します。「ローカル」は保存と制御を指し、推論や要約までオフラインではありません。
メモ・TODO は毎ターンのシステム指示へ重複注入しません。

[pi-tasks fork](https://github.com/keewai704/pi-tasks) の `TaskCreate / TaskList / TaskGet / TaskUpdate` は進捗台帳です。
保存先は `session-global`（`~/.pi/agent/tasks/sessions/`）、fork は独立台帳に引き継ぎます。
完了タスクの自動削除・auto-cascade は無効。破損・読み取り不能な台帳は空として上書きせず停止します。
`TaskExecute / TaskStop / TaskOutput` は登録せず、実行・結果確認は native Agent が担当します。

### MCP・検索・LSP

Linux 標準ツールは `read / bash / edit / write / grep / find / ls`、実行環境は Node.js、Python、jq、ast-grep を含みます。
構造検索は `ast-grep` を読み取り専用で使い、Linux の別コマンド `sg` は使いません。
`bash` の `shellCommandPrefix` は NixOS 権限ラッパーを PATH の先頭に置き、`pipefail` を有効にします。
`sudo` の認証条件は変えず、`errexit` は強制しません。Web の別端末や独自シェルの拡張には適用されません。

MCP は共通の `context7`、`nixos`、`openaiDeveloperDocs`、`serena` と、デスクトップ限定 `cua-driver` です。
登録したサーバーを有効にし、初回の情報取得後は必要時接続します。状態確認は `/mcp`。
単独操作は `mcp`、複数呼び出しの依存処理・抽出は `mcpScript` を使います。
後者の既定期限は30秒、中間転送は合計16 MiB。認証・承認と最終出力制限は通常呼び出しと共通です。
期限切れは副作用を再実行する根拠になりません。詳細は手動専用 `/skill:mcp-scripting` で読みます。

[pi-web-access](https://github.com/nicobailon/pi-web-access) は `web_search / fetch_content / get_search_content / source_check` を提供します。
公式 OpenAI モデルでは provider 省略で現在モデル・ChatGPT 認証を再利用します。
Claude 等では `provider: "openai"` を明示して別の Astra 検索経路を使い、会話モデルは変更しません。
検索はライブ Web 取得を使い ChatGPT 利用枠を消費します。他社への自動フォールバックはありません。
`workflow = "none"` が既定で、必要なら `/websearch` で確認 UI を開きます。
ブラウザー Cookie と第三者ページ取得代行は既定で無効、PDF はローカル `unpdf` 抽出（OCR なし）です。
`source_check` は原文ハッシュ・引用を返しますが、支持・反証の判定は利用側が行います。
CLI/Web 共通設定は `~/.pi/agent/web-search.json` と `~/.config/pi/web-search.json` に同じ内容を配布します。

LSP は Nix、TypeScript/JavaScript、Python、Lua、Bash に対応し、必要時に起動して呼び出し後に停止します。
`lsp_diagnostics` は対象 paths/root を絞って使い、ビルドの代用にはしません。
Python 診断は basedpyright と Ruff、修正は `lsp_fix` の対象サーバーを指定します。
Bash は ShellCheck を接続します。`lsp_fix` は既定プレビューで、書き込み時は他の編集と並列にしません。
設定は `~/.pi/agent/pi-lsp.json`、状態確認は `/lsp`。
Pi 拡張用 [tsconfig.json](home/keewai/shared/pi/tsconfig.json) は適用済みユーザープロフィールの Pi SDK・Node 型を参照します。

### パッケージと旧構成

MCP `2.34.0`、Web access `0.30.0`、LSP `0.49.7`、pi-tasks `0.9.0`、Claude bridge `0.8.0` を Nix で固定し、
Store 内のパッケージを直接読み込みます。拡張の順序は `settings.packages` の `lib.mkOrder`、
バージョン・依存・ハッシュは担当 `pkgs/pi-*/` が所有します。`pi update --extensions` では更新しません。

従来のプラグイン用 patch は `keewai704` の fork に統合し、各 `main` のコミットとハッシュを固定します。
対象は [pi-web](https://github.com/keewai704/pi-web)、[pi-claude-bridge](https://github.com/keewai704/pi-claude-bridge)、
[pi-tasks](https://github.com/keewai704/pi-tasks)、[pi-agent-teams](https://github.com/keewai704/pi-agent-teams)、
[pi-core-subagent](https://github.com/keewai704/pi-extensions/tree/main/packages/core/pi-core-subagent) です。
実装・テストは fork、取得・依存固定・SDK 差し替えなどの Nix 統合はこのリポジトリで管理します。
Pi 本体の `cache-affinity-header.patch` はプラグインではないため、引き続きここで管理します。

Codex conversion、Code Mode、Remote/Hybrid compaction、旧 Teams/Crew/Core の実行エンジンは読み込みません。
旧 npm ファイル、認証、履歴、未統合 worktree、ロールバック資源は自動削除しません。
旧 ID や暗号化セッションは native/local へ自動変換せず、再開には互換性の確認が必要です。
Pi 0.87 のプロバイダーは `TranscriptContext.messages` 内のシステム指示・ツール定義を扱う必要があります。
Web と CLI は同じパッチ済み SDK を使い、キャッシュ用ヘッダーも標準接続の本文キーに合わせます。
ChatGPT 接続へ API 専用 TTL を追加したり、履歴・セッション ID を書き換えたりしません。

## Pi Web とネイティブ委任

Pi Web は [web.nix](home/keewai/shared/pi/web.nix) のユーザーサービスです。
ローカルは `http://127.0.0.1:30141/pi/`、tailnet は次の URL を使います。

- [Citrus](https://citrus.tail1e65cd.ts.net/pi/)
- [Orange](https://orange.tail1e65cd.ts.net/pi/)

`Tailscale Serve HTTPS 443 → nginx 127.0.0.1:8000 → Pi Web 127.0.0.1:30141` の経路です。
`/pi` を basePath としてビルドし、API・assets・イベント・通知・PWA も同じパスを使います。
Citrus の `/` は `/pi/` へ転送、Orange の `/` は Immich、`/vault/` は Vaultwarden のままです。

CLI/Web はホスト内で認証・設定・スキル・会話を共有し、ホスト間では複製しません。
Orange でも初回認証が必要です。Nix 管理設定は画面から変更せず編集元を使います。
状態は `systemctl --user status pi-web`、ログは `journalctl --user -u pi-web` で確認します。

### 役割と依頼

[Pi Web fork](https://github.com/keewai704/pi-web) の共有実装を CLI/Web が使い、
[Nix パッケージ](pkgs/pi-web/default.nix) が SDK と実行環境を統合します。
CLI は `pi-web-native-subagents/subagent-cli-extension.js` を読み込み、Web サーバーを起動しません。
Web 内では二重登録を抑止します。ロール本文は Crew `1.0.34` 由来のローカル適応版で、MIT 通知を同梱します。

| ロール | 成果物 |
| --- | --- |
| `scout` | 範囲を絞った事実調査と出典 |
| `planner` | 依存関係・リスク・完了条件を含む実装計画 |
| `oracle` | 選択肢と根拠のある推奨 |
| `worker` | 指定範囲の変更と確認結果 |
| `code-reviewer` | 正しさ・実行時・セキュリティ等の問題 |
| `quality-reviewer` | 複雑さ・重複・結合等の保守性の問題 |

CLI/Web の組み込みロール一覧には、この6種類だけを表示します。
`general-purpose → worker`、`explore → scout`、`plan → planner` は過去の呼び出し用の互換名で、
一覧には追加しません。同名のユーザー定義ロールがある場合は、その設定（無効化を含む）を優先します。
`manage_subagents(action: "list")` で実際のロール・ツールを確認します。
読み取り専用ロールに shell はなく、ambient extensions の継承も既定で無効なので、レビューには読める差分を渡します。
ツール制限と worktree は OS サンドボックスではありません。

| ツール | 操作 |
| --- | --- |
| `Agent` | 単独・バッチの委任、明示的 resume |
| `get_subagent_result` | 状態・結果・保持した子履歴の取得 |
| `steer_subagent` | 情報伝達。メッセージだけでは再開しない |
| `manage_subagents` | list / assign / message / answer / cancel / close / release |

単独は `subagent_type`、バッチは各 `tasks[]` の `profile` に完全一致のロール名を指定します。
依頼は文字列または `assignment: {goal, context, instructions}`。追加専門性には `specialist_prompt` を使います。
checkout、入力、許可ファイル、成果物、確認範囲、終了条件を渡し、親の未コミット内容が見えるとは仮定しません。

```json
{
  "subagent_type": "scout",
  "assignment": {
    "goal": "Locate the caller that decides the retry policy.",
    "context": ["Read only the specified checkout and relevant callers."],
    "instructions": ["Return paths, observed behavior, and missing evidence; do not edit."]
  },
  "model": "openai-codex/gpt-6-luna",
  "thinking": "low"
}
```

### 委任モデルと thinking

エージェントには、毎回 `model` と `thinking` の両方を明示するよう指示します。
バッチは各 `tasks[]` 内に指定し、pending task の割り当ても同様です。
親が Astra/xhigh でも、それを無指定で引き継ぎません。ユーザーの明示指定を優先したうえで、出発点を次のようにします。

| ロール | モデル（provider は `openai-codex`） | thinking |
| --- | --- | --- |
| `scout` | `gpt-6-luna` | `low` |
| `worker` / `planner` / `code-reviewer` | `gpt-6-sol` | `medium` |
| `quality-reviewer` | `gpt-6-sol` | `low` |
| `oracle` | `gpt-6-sol` | `high` |

単純な抽出・機械的編集・小さな確認は Luna や低い thinking を選べます。
複数モジュールにまたがる曖昧な仕事は Sol/medium〜high を使い、Astra は明示依頼か、
安価な選択では不足する具体的な難問に限定して理由を説明します。`xhigh` / `max` を一律には使いません。
小さな作業は親が直接行い、合格結果を別モデルで再確認するためだけの追加委任は行いません。
再開・入力回答時も既存の選択を確認し、変更理由がなければ維持して呼び出しに明示します。

これは [APPEND_SYSTEM.md](home/keewai/shared/pi/APPEND_SYSTEM.md#select-the-delegation-model) の選択方針です。
API スキーマやロールの実行時既定値は変更していないため、直接 API を呼んで指定を省略すれば従来の継承が働きます。
非対応のモデル・thinking を黙って別の選択へ置換しません。現在の SDK で Astra は `minimal`〜`max`、
Sol/Luna は加えて `off` に対応します。登録・合成テストだけでは実モデルの利用権を保証しません。

[OpenAI のモデル選択ガイド](https://learn.chatgpt.com/docs/models#recommended-models) は、複雑なコーディングに Sol、
焦点の絞られた反復作業に Luna を案内しています。この構成での品質・速度・実課金の改善率は未測定です。
親モデル、同時実行数、認証、プロバイダーの権限は変更しません。

### 実行・引き継ぎの契約

- 既定は fresh context・バックグラウンド。大きく独立した仕事を必要な数だけ分担します。
  同じ直属親の全バッチ/resume を合計して最大4子（設定範囲1〜4）、深さは親→子→孫までです。
  子は権限を広げられず、読み取り専用から writer を作れません。
- 前提は `needs`。失敗・キャンセル・入力待ちは成功として渡しません。
  writer は明示したコミット `input_revision` から別 worktree を作り、未コミット変更は転送しません。
  `integrated_changes` は親が統合・コミットし、その OID で前提タスクを `release` するまで待ちます。
- 自動コミット・マージ・ブランチ/worktree 削除はしません。親が統合・適用を所有します。
  tool scope は再開時も保持し、旧子へ新しい能力を暗黙追加しません。
- 結果通知は受領であって確認完了ではありません。親が結果を読んで、現行 delivery ID で `close` します。
  `needs_input` は `answer`、その他の再開は `Agent(resume: ...)`。キャンセルは teardown 完了後に再開できます。
- メッセージは送信者付き情報で、新しい利用者権限ではありません。明示 progress は表示用で、モデルを起こしません。
  未読結果・失敗・入力依頼は対応対象です。処理済み通知への相づちだけのターンは不要です。
- 実行所有者は親ごとに1プロセス。他 CLI/Web は閲覧のみです。終了・クラッシュは自動再実行せず明示 resume を必要とします。
  CLI 終了後の常駐実行は保証しません。セッション・結果・worktree は保持します。
- Web は元のコンパクトな会話一覧・子/孫への切替を使い、別のタスクカードや管理フォームは増やしません。
  ツール/API は直近100件のメッセージを返し、以前の記録も保存します。

ネイティブ委任の実装・ロール・package-local tests は [keewai704/pi-web](https://github.com/keewai704/pi-web/tree/main) が正本です。
この README は使い方と契約を示し、古い移行手順や完了していない実装チェックリストを実行キューとして保持しません。

## Citrus のデスクトップ

[Noctalia v5](https://docs.noctalia.dev/noctalia/) がパネル、ランチャー、通知、クリップボード、壁紙、認証、アイドルを担当します。
電源管理・I²C 等の OS 統合は [hosts/citrus/noctalia.nix](hosts/citrus/noctalia.nix)、見た目・起動は Home Manager です。
指紋認証は fprintd が有効な環境だけで使います。`Super+,` で Noctalia 設定を開きます。

Sunshine 配信のため画面ロックは無効です。起動時・アイドル時・サスペンド前のロックと手動ロック操作を無効にし、
アイドル660秒での画面消灯は維持します。無人時もアクセスできるため、端末とペアリング済みクライアントの管理に注意してください。
GTK・Qt・Kitty・Hyprland の色は Noctalia テンプレート、フォント・カーソル・アイコン・未対応アプリ等は Stylix が担当します。
Home Manager はテンプレートの入力を宣言し、生成色ファイルは Noctalia が更新します。

Bitwarden のデスクトップ/SSH エージェントは Home Manager 管理です。rbw 初回は
`rbw config set email <メールアドレス>`、`rbw login`、`rbw unlock`、`rbw sync` を使います。
公式 Bitwarden サーバーではログイン前に `rbw register` と個人 API キーが必要です。
Noctalia には旧 Dynamic Island の `bw <項目名>` 検索・コピー機能はないため、rbw は端末から使います。

既定ブラウザーは Firefox。固定した `keewai704/my-firefox-nix` の `main` から Sine/Natsumi、日本語化、
Bitwarden/uBlock Origin を取り込みます。非公開入力の取得には GitHub 読み取り認証が必要です。
Brave Origin も Home Manager で管理します。

### Sunshine 配信

Hyprland 上の `SUNSHINE` 仮想画面を NVENC で配信します。uinput/udev/Avahi は NixOS、Moonlight は Home Manager が担当します。
管理画面は citrus の `https://localhost:47990` のみ、UPnP は無効。Moonlight に LAN または Tailscale の citrus アドレスを登録します。

| アプリ | 動作 |
| --- | --- |
| `Extend Display` | 既存画面の右に仮想画面を追加 |
| `Steam Big Picture` | クライアントのみ表示にし、Steam Big Picture を起動 |
| `Client Only` | 他画面を無効にし仮想画面だけ表示 |

解像度・リフレッシュレートはクライアント要求に合わせます。HDR は無効です。
初回測定は 1920×1080・60 FPS・20 Mbps。120 Hz 対応端末では 1080p・120 FPS・40 Mbps・H.264・
ハードウェアデコード・V-Sync/フレームペーシング無効が低遅延候補です。ティアリングが気になる場合は V-Sync を戻します。

```sh
moonlight stream citrus "Extend Display" --1080 --fps 120 --bitrate 40000 --video-codec H.264 --video-decoder hardware --no-vsync --no-frame-pacing --no-hdr
```

2026-09-21 の citrus 内 Moonlight/Weston 合成ループバック測定では描画 59.94→119.87 FPS、
ホスト処理平均 2.2→2.2 ms、デコード平均 0.28→0.06 ms、ネットワーク欠落 0% でした。
同一 GPU の測定であり、外部端末・実ネットワーク・ゲーム負荷の保証ではありません。

単なる切断ではアプリが継続します。復元は Moonlight の「アプリを終了」、またはサービス停止で行います。
終了処理は Hyprland 設定を再読込し、宣言済み画面と接続中画面のワークスペース配置を戻します。
取り外した画面の以前の配置・電源状態や、一時的な `hyprctl` 変更は復元できません。
`SUNSHINE` はサービス予約名で、稼働中に同名出力を手動で作り直さないでください。

## Orange のサービス

各サービスは [settings.nix](hosts/orange/settings.nix) を直接読みます。
Web の入口は Tailscale Serve HTTPS 443 → loopback nginx `127.0.0.1:8000` です。
公開経路は [web.nix](hosts/orange/services/web.nix)、規則は [AGENTS.md](AGENTS.md#orange-web-exposure) にあります。

| サービス | 用途・入口 | 編集先 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich.nix](hosts/orange/services/immich.nix) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden.nix](hosts/orange/services/vaultwarden.nix) |
| Pi Web | `https://orange.tail1e65cd.ts.net/pi/` | [shared/pi/web.nix](home/keewai/shared/pi/web.nix) |
| Samba | HDD 共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | LAN/tailnet 向け Fabric | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale Exit Node | 経路・UDP オフロード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |

起動は HDD マウント→共有ディレクトリ準備→既存データ取り込み→アプリの順です。
[storage.nix](hosts/orange/services/storage.nix) がマウントと準備、各サービスが権限と取り込み条件を所有します。
長い実行処理は隣接する shell テンプレートに置き、`@名前@` を Nix の `scriptReplacements` で置換します。
テンプレートをそのまま直接実行しません。

取り込みは [import-immich-database.sh](hosts/orange/services/import-immich-database.sh)、
[import-vaultwarden-data.sh](hosts/orange/services/import-vaultwarden-data.sh)、
バックアップは [local-backup.nix](hosts/orange/services/local-backup.nix) と [local-backup.sh](hosts/orange/services/local-backup.sh) です。
[health-monitor.nix](hosts/orange/services/health-monitor.nix) / [health-monitor.sh](hosts/orange/services/health-monitor.sh) は
15分間隔でサービス・容量・ドライブ・メモリー・温度・ログ・時刻・通信・バックアップ・カーネルを調べ、新しい異常を Discord に通知します。
[smart-tests.nix](hosts/orange/services/smart-tests.nix) はドライブ自己診断、[maintenance.nix](hosts/orange/services/maintenance.nix) はログ掃除・TRIM・Store 保守です。

## パッケージとローカル適用

[pkgs/default.nix](pkgs/default.nix) が `nix build .#<名前>` の公開一覧です。ホスト内だけのパッケージは担当設定から `callPackage` します。
パッチは対象パッケージの隣に置き、上流更新時には前提と付属テストを確認します。
`keewai704` の GitHub 入力は `main` と revision/hash を固定します。
Nixpkgs はホスト・Home Manager・公開パッケージ・開発シェルで `allowUnfree = true` です。

Hyprland は IME の修飾キー対応のため独自ビルドし、Aquamarine 等の依存は上流定義を使います。
keyd で Logitech を除外する [設定](hosts/citrus/input-method-shortcut.nix) と、別デバイスの Shift/Ctrl を引き継ぐパッチは別の役割です。
既存の NixOS・`hyprland.cachix.org`・Chaotic キャッシュを利用します。

Apple Music クライアントの実装・パッケージ・モジュールは [keewai704/siora](https://github.com/keewai704/siora)、
取り込みは [apple-music.nix](home/keewai/desktop/apple-music.nix) です。起動は `siora`。
認証用ライブラリは所有する Apple Music 3.6.0-beta（1109）x86_64 APKM から
`alac-room-auth-import /path/to/apple-music.apkm` で取り込み、再配布しません。
既定保存先は `~/.local/share/alac-room/auth/rootfs`、変更は `ALAC_ROOM_AUTH_DATA_DIR` を使います。

### 変更から適用まで

[検証スキル](.agents/skills/nixos-validation/SKILL.md) で変更に応じた確認を選びます。
毎回の全ホストビルド、`nix flake check`、変更前後の全評価比較は不要です。
開発環境は `nix develop --no-write-lock-file` で開けます。

[AGENTS.md](AGENTS.md#completion-gates) に従い、対象だけ整形・検証・コミットし、
実行ホストに影響する場合は、そのホストの `test` → 稼働確認 → `switch` → 再確認まで行います。
同じ出力を事前ビルドせず `test` の評価・ビルドを使います。稼働と boot-default の一致も確認します。
リポジトリ文書だけの変更はローカル適用不要ですが、配布スキルや Pi 指示・ロールは全ホストへ影響します。
別ホストへの接続・適用や push は、その操作の明示的な許可なしに行いません。
