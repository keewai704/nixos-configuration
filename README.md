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
│   ├── citrus/          ハードウェア、起動、音声、Sunshine など
│   └── orange/          ハードウェア、ストレージ、services/ にサーバー機能
├── modules/             複数ホストで使う NixOS 設定
│   ├── common/          全ホスト共通（Nix、ネットワーク、ユーザー、Home Manager 接続）
│   └── desktop/         デスクトップ用 OS 設定（Hyprland、Steam、Stylix など）
├── home/keewai/         個人設定（Home Manager）
│   ├── common/          全ホスト共通（シェル、Git、スキル）
│   └── desktop/         デスクトップ用アプリ（ブラウザー、端末、入力、Discord など）
├── pkgs/                自作・改造パッケージとパッチ
├── skills/              Claude Code に配布する個人スキル
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
| DSH Web / Claude Code / Codex | [deepseek-harness.nix](home/keewai/desktop/deepseek-harness.nix)、[pkgs/deepseek-harness](pkgs/deepseek-harness/)、[modules/desktop/deepseek-harness.nix](modules/desktop/deepseek-harness.nix) |
| 個人スキル・MCP サーバー（Claude Code / Codex 共通） | [skills/](skills/)、[coding-agents](home/keewai/common/coding-agents/default.nix) |
| 設定不要な GUI アプリを追加 | [home/keewai/desktop/applications.nix](home/keewai/desktop/applications.nix) |
| ウィンドウ・モニター・キー割り当て | [hyprland.lua](home/keewai/desktop/hyprland.lua) |
| Hyprland 本体・ログイン画面 | [modules/desktop/hyprland.nix](modules/desktop/hyprland.nix) |
| パネル・ランチャー・通知・壁紙・ウィジェット | [island.nix](home/keewai/desktop/island.nix)（[keewai704/Island](https://github.com/keewai704/Island)） |
| 日本語入力 | [input-method.nix](home/keewai/desktop/input-method.nix)、[modules/desktop/input-method.nix](modules/desktop/input-method.nix) |
| 端末・ブラウザー・ファイル管理 | [kitty.nix](home/keewai/desktop/kitty.nix)、[browser.nix](home/keewai/desktop/browser.nix)、[file-manager.nix](home/keewai/desktop/file-manager.nix) |
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

Before activating citrus, run `python3 pkgs/kernel-drivers/update.py` to refresh
the latest stable upstream Linux and NVIDIA releases and their source hashes.
Commit `pkgs/kernel-drivers/sources.json` with the configuration. The kernel keeps
Clang 22, ThinLTO, `-O3`, 1000 Hz, and dynamic preemption without CachyOS patches.
Rust drivers are disabled because upstream does not support Rust with both LTO
and BTF enabled.
Citrus uses `localmodconfig` with an explicit module list in `hosts/citrus/kernel.nix`
to omit unused hardware drivers. Filesystems, network protocols, input devices,
USB storage/serial/network adapters, and virtualization support are retained.
Update the module list when adding hardware outside these groups.
The BEITONG xpad fix is rebuilt with the kernel through `boot.extraModulePackages`.

## コーディングエージェント

デスクトップには [DeepSeek Harness](https://github.com/deepseek-ai/DeepSeek-Harness) の Web 画面を入れています。

- 設定は [deepseek-harness.nix](home/keewai/desktop/deepseek-harness.nix) にあります。
  `dsh` または `dsh web`、アプリランチャーの「DeepSeek Harness」で認証付きの URL をブラウザーに開きます。
  `dsh web --no-open` はブラウザーを開かずに URL を表示します。
- バックエンドは DSH の既定ポート `127.0.0.1:3080` で待ち受けます。
  tailnet 内の公開 URL は `https://citrus.tail1e65cd.ts.net:8443/` で、Tailscale Serve が HTTPS を提供します。
  [modules/desktop/deepseek-harness.nix](modules/desktop/deepseek-harness.nix) が `keewai` を Tailscale の operator にします。
- Codex は DSH の subscriptions バンドル、Claude Code は Claude プラグインで使います。
  Claude Code の実行ファイルは [sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix) から取得し、DSH の実行環境にだけ追加します。
- Claude Code と Codex の設定（`~/.claude`、`~/.codex`）は基本的に Nix で管理していません。
  例外として [coding-agents](home/keewai/common/coding-agents/default.nix) が両方へ共通にスキルと MCP サーバーを配ります。
  - スキル: `codingAgents.skills`（[skills/](skills/) の全ディレクトリを自動登録）を `~/.claude/skills/` と `~/.agents/skills/`（Codex）にリンクします。
    [shadcn/ui の公式スキル](https://ui.shadcn.com/docs/skills)は [shadcn.nix](home/keewai/common/coding-agents/shadcn.nix) で取得元のコミットとハッシュを固定し、参照資料とスクリプトを含めて配布します。実行に必要な Node.js・npm・npx も同じ設定で導入します。
  - MCP: `codingAgents.mcpServers.<name> = { command; args; env; }` を、Home Manager の有効化時に `~/.claude.json` の `mcpServers` と `~/.codex/config.toml` の `[mcp_servers]` へ書き込みます。
    Nix から外したサーバーだけを削除し、手動で追加したサーバーや他の設定はそのまま残します。
- [hypruse](https://github.com/IlyasKhallouki/hypruse)（デスクトップのみ）は [computer-use.nix](home/keewai/desktop/computer-use.nix) で MCP サーバー `hypruse` として登録しています。
- UI デザインは [Penpot](https://design.penpot.app/) を使います。[penpot-mcp.nix](home/keewai/desktop/penpot-mcp.nix) がデスクトップ用 MCP とプラグインを提供します。接続手順と Apple 系アプリ向けアセットは [penpot-apple-design](skills/penpot-apple-design/SKILL.md) にまとめています。

| スキル | 用途 |
| --- | --- |
| `ponytail` | 実装を単純に保つ（KISS / YAGNI）。`ponytail lite/full/ultra`、`stop ponytail` で切替 |
| `superpowers` | 設計・計画・デバッグ・レビューなど大きめの作業の進め方 |
| `add-nix-skill` | このリポジトリでスキルを追加・修正するとき |
| `apple-device-usb` | USB / Wi-Fi 経由で iPhone・iPad を操作 |
| `penpot-apple-design` | Penpot の操作と、iOS・iPadOS・macOS・Apple 風 UI 向けアセットの選定・実装への受け渡し |
| `faster-whisper` | 音声・動画の文字起こし |
| `shadcn` | shadcn/ui の部品の導入・調整、`DESIGN.md` に基づく配色・書体・部品の設計 |

リポジトリ専用の検証手順は [.agents/skills/nixos-validation](.agents/skills/nixos-validation/SKILL.md) にあります。

## citrus（デスクトップ）

- **画面構成**：Hyprland + [Island](https://github.com/keewai704/Island)（[impasto](https://github.com/andreumassanet/impasto) のダイナミックアイランドとデスクトップウィジェットに、[HyprFlux](https://github.com/ahmad9059/HyprFlux) の壁紙エフェクトを加えたもの）。`Super+Space` でランチャー、`Super+I` でコントロールセンター、`Super+Shift+Space` で壁紙、`Super+F1` でショートカット一覧。
- **配色**：Stylix が GTK・Qt・Kitty を、[テーマ](themes/tokyo-night-black/default.nix) が Hyprland の枠線などを担当。Island は壁紙から配色を取り、初期の壁紙は Stylix の画像。
- **Hyprland**：公式 flake の main を hyprland.cachix.org のビルド済みバイナリで導入。
- **日本語入力**：Hazkey。keyd で `` Alt+` `` を変換キーに割り当て、Logitech 製キーボードは除外。
- **ブラウザー**：既定は [Helium](https://github.com/imputnet/helium-linux)（公式リリースを [pkgs/helium](pkgs/helium/) でパッケージ化。nixpkgs の Widevine CDM を読み込ませて DRM 動画も再生可）。TwinStar・OpenMouse の WebHID 設定アプリも Helium のアプリモードで開きます。
- **Bitwarden**：デスクトップアプリと SSH エージェント。
- **Apple Music**：[keewai704/siora](https://github.com/keewai704/siora) の最新リリースの AppImage。Home Manager の適用時に `gh` の認証で `~/.local/share/siora/` へ取得・更新します（手動は `siora-update`）。起動は `siora`。

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
配信のため画面ロックは無効です（Island のアイドル時ロック・消灯は既定で無効、ロックのキー割り当てもなし）。

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
- `keewai704` 所有の入力（Island、hypr-brightness）は `?ref=main` を明示し、適用前に毎回 `nix flake update` で最新の main に更新します。
- `claude-code`・`meltype-release`・`meltype-tags` も適用前に毎回 `nix flake update` で最新リリースに更新します。
- 非自由パッケージは全体で許可しています（`allowUnfree = true`）。
- `system.stateVersion` / `home.stateVersion` は互換性の基準なので、アップデートに合わせて変えません。
