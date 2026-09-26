# nixos-configuration

2台の NixOS マシンの設定です。どちらも `x86_64-linux` です。

| ホスト | 役割 |
| --- | --- |
| `citrus` | デスクトップ（Hyprland、NVIDIA、Steam、Sunshine 配信） |
| `orange` | 自宅サーバー（Immich、Vaultwarden、Samba、Minecraft、バックアップ） |

OS・ハードウェア・システムサービスは **NixOS**、個人のアプリや設定は **Home Manager** で管理します。
作業ルール（検証・コミット・適用の手順）は [AGENTS.md](AGENTS.md) を参照してください。

## ディレクトリ構成

```text
.
├── flake.nix            入力（依存リポジトリ）とホスト一覧
├── hosts/               マシンごとの設定
│   ├── citrus/          ハードウェア、起動、音声、指紋、Sunshine など
│   └── orange/          ハードウェア、ストレージ、services/ にサーバー機能
├── modules/             複数ホストで使う NixOS 設定
│   ├── common/          全ホスト共通（Nix、ネットワーク、ユーザー、Home Manager 接続）
│   └── desktop/         デスクトップ用 OS 設定（Hyprland、Steam、Stylix など）
├── home/keewai/         個人設定（Home Manager）
│   ├── common/          全ホスト共通（シェル、Git、Claude Code / Codex、スキル）
│   └── desktop/         デスクトップ用アプリ（ブラウザー、端末、入力、Discord など）
├── pkgs/                自作・改造パッケージとパッチ
├── skills/              Claude Code / Codex に配布する個人スキル
├── themes/              共通テーマ（色・フォント・壁紙）
├── secrets/             agenix で暗号化したシークレット
└── devshell/            開発用ツール（nixd、nixfmt、shellcheck など）
```

### 読み込みの流れ

```text
flake.nix
└── nixosConfigurations.<host>
    ├── modules/common            全ホスト
    │   └── home-manager.nix  →  home/keewai/common
    └── hosts/<host>
        └── (citrus のみ) modules/desktop  →  home/keewai/desktop
```

新しいホストを増やす場合は `hosts/<名前>/default.nix` を作り、
`flake.nix` のホスト一覧に名前を追加します。デスクトップにしたい場合は
`../../modules/desktop` を imports に加えます。

## やりたいこと別の編集先

| やりたいこと | 編集するファイル |
| --- | --- |
| CLI ツールを追加 | [home/keewai/common/packages.nix](home/keewai/common/packages.nix) |
| シェル・エイリアス・プロンプト | [shell.nix](home/keewai/common/shell.nix)、[starship.toml](home/keewai/common/starship.toml) |
| Git / GitHub CLI | [git.nix](home/keewai/common/git.nix) |
| Claude Code / Codex | [coding-agents.nix](home/keewai/common/coding-agents.nix) |
| 個人スキル | [skills/](skills/)（配布は [skills.nix](home/keewai/common/skills.nix)） |
| 設定不要な GUI アプリを追加 | [home/keewai/desktop/applications.nix](home/keewai/desktop/applications.nix) |
| ウィンドウ・モニター・キー割り当て | [hyprland.lua](home/keewai/desktop/hyprland.lua) |
| Hyprland 本体・ログイン画面 | [modules/desktop/hyprland.nix](modules/desktop/hyprland.nix) |
| パネル・ランチャー・通知・壁紙・アイドル | [hypr-island.nix](home/keewai/desktop/hypr-island.nix)（[keewai704/hypr-island](https://github.com/keewai704/hypr-island)） |
| 日本語入力 | [input-method.nix](home/keewai/desktop/input-method.nix)、[modules/desktop/input-method.nix](modules/desktop/input-method.nix) |
| 端末・ブラウザー・ファイル管理 | [kitty.nix](home/keewai/desktop/kitty.nix)、[browser.nix](home/keewai/desktop/browser.nix)、[firefox.nix](home/keewai/desktop/firefox.nix)、[file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Discord | [legcord.nix](home/keewai/desktop/legcord.nix) |
| Steam | [modules/desktop/steam.nix](modules/desktop/steam.nix)、[steam-theme.nix](home/keewai/desktop/steam-theme.nix) |
| 配色・フォント | [themes/tokyo-night-black](themes/tokyo-night-black/default.nix) |
| citrus のハードウェア | [hosts/citrus/](hosts/citrus/) |
| orange のサービス・ポート・保存先 | [hosts/orange/services/](hosts/orange/services/)、[settings.nix](hosts/orange/settings.nix) |

判断に迷ったら次の基準で置き場所を決めます。

- **ログイン、ドライバー、udev、PAM、デーモンなど OS との統合** → NixOS（`modules/` か `hosts/`）
- **自分だけが使うアプリや設定ファイル** → Home Manager（`home/keewai/`）
- **特定マシンのハードウェアに依存するもの** → `hosts/<host>/`

## よく使うコマンド

```sh
sudo nixos-rebuild test --flake .#citrus     # 一時的に適用して動作確認（再起動で戻る）
sudo nixos-rebuild switch --flake .#citrus   # 本適用（起動時の既定にもなる）
nix flake update <入力名>                    # 特定の入力だけ更新
nix fmt                                      # Nix ファイルを整形
nix develop                                  # 言語サーバーや整形ツール入りのシェル
nix build .#<パッケージ名>                    # pkgs/ のパッケージを単体ビルド
```

`nixos-rebuild` は必ず実行中のマシン自身の名前（`hostname` の結果）を指定します。

## コーディングエージェント

[sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix) の Claude Code と、
[sadjow/codex-cli-nix](https://github.com/sadjow/codex-cli-nix) の Codex を全ホストに入れています。

- Claude Code はトークン節約のため、次の環境変数を既定値にしています。
  シェルで別の値を `export` すればそちらが優先されます。
  - `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`（入力候補の自動生成を無効）
  - `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1`（簡潔なシステムプロンプト）
  - `ENABLE_CLAUDEAI_MCP_SERVERS=false`（claude.ai のコネクタを読み込まない）
- `~/.claude/settings.json` と `~/.codex/config.toml` は Nix で管理していないので、
  アプリ側から自由に変更できます。
- [skills/](skills/) の各スキルは `~/.claude/skills/` と `~/.agents/skills/` の両方にリンクされます。

| スキル | 用途 |
| --- | --- |
| `ponytail` | 実装を単純に保つ（KISS / YAGNI）。`ponytail lite/full/ultra`、`stop ponytail` で切替 |
| `superpowers` | 設計・計画・デバッグ・レビューなど大きめの作業の進め方 |
| `add-nix-skill` | このリポジトリでスキルを追加・修正するとき |
| `apple-device-usb` | USB / Wi-Fi 経由で iPhone・iPad を操作 |
| `faster-whisper` | 音声・動画の文字起こし |

リポジトリ専用の検証手順は [.agents/skills/nixos-validation](.agents/skills/nixos-validation/SKILL.md) にあります。

## citrus（デスクトップ）

- **画面構成**：Hyprland + [hypr-island](https://github.com/keewai704/hypr-island)（ノッチ型の Dynamic Island。メディア、ランチャー、通知、クリップボード、壁紙、コントロール）。`Super+D` で開閉、`Super+F1` でショートカット一覧。
- **配色**：Stylix が GTK・Qt・Kitty・hypr-island を、[テーマ](themes/tokyo-night-black/default.nix) が Hyprland の枠線などを担当。
- **Hyprland**：IME の修飾キー対応パッチを当てた独自ビルド（[pkgs/hyprland](pkgs/hyprland/)）。
- **日本語入力**：Hazkey。keyd で `` Alt+` `` を変換キーに割り当て、Logitech 製キーボードは除外。
- **ブラウザー**：既定は Firefox（[keewai704/my-firefox-nix](https://github.com/keewai704/my-firefox-nix)）。Brave Origin も利用可。
- **Bitwarden**：デスクトップアプリと SSH エージェント。CLI は `rbw`（hypr-island が Vaultwarden 向けに初期化。初回は `rbw login`）。
- **Apple Music**：[keewai704/siora](https://github.com/keewai704/siora)。起動は `siora`。

### Sunshine 配信

Hyprland 上に `SUNSHINE` という仮想画面を作り、NVENC で Moonlight に配信します。
管理画面は citrus 上の `https://localhost:47990` のみ。

| Moonlight のアプリ | 動作 |
| --- | --- |
| `Extend Display` | 既存画面の右に仮想画面を追加 |
| `Steam Big Picture` | 仮想画面だけにして Steam Big Picture を起動 |
| `Client Only` | 仮想画面だけを表示 |

低遅延の例：

```sh
moonlight stream citrus "Extend Display" --1080 --fps 120 --bitrate 40000 --video-codec H.264 --video-decoder hardware --no-vsync --no-frame-pacing --no-hdr
```

切断だけではアプリは動き続けます。元の画面構成に戻すには Moonlight で「アプリを終了」します。
配信のため画面ロックは無効です（hypr-island のロック連携と `Super+Alt+L` を外し、アイドル 660 秒で画面消灯のみ）。

## orange（サーバー）

外部からの Web アクセスは **Tailscale Serve (HTTPS 443) → nginx (127.0.0.1:8000) → 各アプリ（loopback）** の一本道です。
アプリを LAN やワイルドカードアドレスで公開しません。詳しい規則は [AGENTS.md](AGENTS.md#orange-web-exposure)。

| サービス | URL・用途 | 設定 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich.nix](hosts/orange/services/immich.nix) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden.nix](hosts/orange/services/vaultwarden.nix) |
| Samba | HDD 共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | Fabric サーバー | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale Exit Node | 出口ノード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |
| 公開経路 | nginx と Tailscale Serve | [web.nix](hosts/orange/services/web.nix) |

- ポート・パス・URL は [settings.nix](hosts/orange/settings.nix) にまとめています。
- 起動順は「HDD マウント → 共有ディレクトリ準備 → 既存データ取り込み → アプリ」です（[storage.nix](hosts/orange/services/storage.nix)）。
- [local-backup](hosts/orange/services/local-backup.nix) がバックアップ、[health-monitor](hosts/orange/services/health-monitor.nix) が 15 分ごとに異常を Discord へ通知、
  [smart-tests](hosts/orange/services/smart-tests.nix) がディスク診断、[maintenance](hosts/orange/services/maintenance.nix) がログ掃除・TRIM・Store 保守を行います。
- 長いシェル処理は `.sh` テンプレートに置き、`@名前@` を Nix 側で置換して使います（テンプレートを直接実行しない）。

## パッケージと入力の方針

- [pkgs/default.nix](pkgs/default.nix) に並べたものは `nix build .#<名前>` で単体ビルドできます。
- パッチは対象パッケージのディレクトリに置きます。
- `keewai704` 所有の入力（hypr-island、siora、my-firefox-nix）は `?ref=main` を明示し、適用前に毎回 `nix flake update` で最新の main に更新します。
- 非自由パッケージは全体で許可しています（`allowUnfree = true`）。
- `system.stateVersion` / `home.stateVersion` は互換性の基準なので、アップデートに合わせて変えません。
