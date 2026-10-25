# nixos-configuration

2台の NixOS マシンの設定です。どちらも `x86_64-linux` です。

| ホスト | 役割 |
| --- | --- |
| `citrus` | デスクトップ（Umbriel、Noctalia v5、NVIDIA、Steam、Sunshine 配信） |
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
│   └── desktop/         デスクトップ用 OS 設定（Umbriel、Steam、Stylix など）
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
| T3 Code nightly / HTTPS | [t3code.nix](home/keewai/desktop/t3code.nix), [pkgs/t3code](pkgs/t3code/) |
| 個人スキル・MCP サーバー（Claude Code） | [skills/](skills/)、[coding-agents](home/keewai/common/coding-agents/default.nix) |
| 設定不要な GUI アプリを追加 | [home/keewai/desktop/applications.nix](home/keewai/desktop/applications.nix) |
| ウィンドウ・キー割り当て | [umbriel.nix](home/keewai/desktop/umbriel.nix) |
| モニター・解像度 | [hosts/citrus/display.nix](hosts/citrus/display.nix) |
| Umbriel 本体・ログイン画面 | [modules/desktop/umbriel.nix](modules/desktop/umbriel.nix) |
| パネル・ランチャー・通知・壁紙・ウィジェット | [noctalia.nix](home/keewai/desktop/noctalia.nix) |
| 日本語入力 | [input-method.nix](home/keewai/desktop/input-method.nix)、[modules/desktop/input-method.nix](modules/desktop/input-method.nix) |
| 端末・ブラウザー・ファイル管理 | [kitty.nix](home/keewai/desktop/kitty.nix)、[browser.nix](home/keewai/desktop/browser.nix)、[file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Discord | [legcord.nix](home/keewai/desktop/legcord.nix) |
| Steam | [modules/desktop/steam.nix](modules/desktop/steam.nix)、[steam-css.nix](home/keewai/desktop/steam-css.nix) |
| アプリの配色・テンプレート | [noctalia-templates.nix](home/keewai/desktop/noctalia-templates.nix) |
| 共通フォント・初期パレット | [themes/tokyo-night-black](themes/tokyo-night-black/default.nix) |
| citrus のハードウェア | [hosts/citrus/](hosts/citrus/) |
| orange のサービス・ポート・保存先 | [hosts/orange/services/](hosts/orange/services/)、[settings.nix](hosts/orange/settings.nix) |

判断に迷ったら次の基準で置き場所を決めます。

- **ログイン、ドライバー、udev、PAM、デーモンなど OS との統合** → NixOS（`modules/` か `hosts/`）
- **自分だけが使うアプリや設定ファイル** → Home Manager（`home/keewai/`）
- **特定マシンのハードウェアに依存するもの** → `hosts/<host>/`

## よく使うコマンド

```sh
sudo nixos-rebuild test --accept-flake-config --flake .#citrus     # 一時的に適用して動作確認（再起動で戻る）
sudo nixos-rebuild switch --accept-flake-config --flake .#citrus   # 本適用（起動時の既定にもなる）
nix flake update                             # 入力をまとめて更新
nix flake update <入力名>                     # 特定の入力だけ更新
nix fmt                                      # Nix ファイルを整形
nix develop                                  # 言語サーバーや整形ツール入りのシェル
nix build .#<パッケージ名>                    # pkgs/ のパッケージを単体ビルド
```

`nixos-rebuild` は必ず実行中のマシン自身の名前（`hostname` の結果）を指定します。

Before activation, run `nix flake update` and commit its lock changes.

The flake's `nixConfig` mirrors the binary-cache URLs and signing keys from
`modules/common/nix.nix`, `hosts/citrus/kernel.nix`, and
`hosts/citrus/nvidia.nix`. Keep both declarations synchronized; flake cache
settings must be literal values, not imports or computed expressions.
Use `--accept-flake-config` with this repository's rebuilds and `nix build` so
the first build can use the caches before the new NixOS configuration is active.
Before that initial activation, run package bootstrap builds with
`sudo nix build --accept-flake-config --no-link .#<package>`: an untrusted daemon
client cannot add new substituters or signing keys merely by accepting a flake.
Do not enable `accept-flake-config` globally: only accept cache trust settings
from flakes you have reviewed. Accepting this flake enables all its declared
caches for that invocation; installed CUDA and CachyOS cache settings remain
Citrus-specific. This does not replace Nix's default `cache.nixos.org` cache.

Flox's public cache is a fallback at priority 50, below `cache.nixos.org`.
Its endpoint and signing key are published in `flox/flox`'s upstream `flake.nix`.
It supplies the exact CUDA-enabled Sunshine output used by the current lock,
without changing Sunshine's features or build inputs. Like other trusted binary
caches, it can sign any store path; this trust is not restricted to Sunshine.

A cache must contain the exact store path, not merely the same package version.
Local package patches, CUDA overrides, out-of-tree kernel modules, generated
configuration, and wrappers can still require local builds. Adding unrelated
cache URLs cannot provide those missing outputs. Keep signature verification
enabled and never trust an unpublished or compromised cache key to avoid builds.

Citrus builds a host-optimized kernel from xddxdd's `nix-cachyos-kernel` `master`
input and its own pinned package set. Select the latest release's ThinLTO package,
or the RC ThinLTO package when its base release is newer; a final release takes
precedence over RCs of the same release. This tracks the available mainline
series through `nix flake update`, including prereleases, rather than LTS or the
cache-gated `release` branch. Kernel, NVIDIA, and CachyOS ZFS sources remain
managed by that input, not independent local version manifests.

`hosts/citrus/kernel-config.nix` refines CachyOS's `.config` for the Ryzen 7
9800X3D: reproducible `znver5` compiler tuning, Clang ThinLTO, CachyOS's `-O3`,
and a 32-CPU limit. Disable automatic module expansion and omit unrelated PCI
Ethernet vendors, legacy storage controllers, Intel/old Radeon/Nouveau graphics,
SoC/FireWire audio, TV/radio hardware, and guest-only hypervisor support. Retain
Intel I226-V Ethernet, MT7925 Wi-Fi/Bluetooth, AMD integrated graphics, NVIDIA,
NVMe/AHCI, USB storage/networking, HID/gamepads, HDA/USB audio, common removable
filesystems, KVM hosting, containers, ZFS, and sched_ext/BPF/BTF. This is a reviewed
hardware profile, not an impure build-time `localmodconfig` or a snapshot that
removes every currently unloaded driver. New PCI hardware may require revisiting
the exclusions. NVIDIA, ZFS, and the BEITONG xpad module rebuild against this
kernel; do not expect a public cache hit for the customized outputs.

Keep the input's own nixpkgs so its kernel and modules use the upstream dependency
set. A successful build or activation cannot validate the new kernel's boot,
NVIDIA, or root-ZFS behavior; those require a subsequent boot. The old Lantian
binary cache and signing key are deliberately not trusted following the
upstream incident in `xddxdd/nix-cachyos-kernel#110`. Citrus instead trusts
`https://cache.xinux.uz`, the independently operated alternative documented by
upstream in its README and issue #89. Its published signing key verifies the
unmodified upstream kernel/module cache entries. This is not xddxdd's replacement
cache, and trusting it permits substitution of any store path, not only kernels.
The BEITONG xpad fix is rebuilt with the kernel through `boot.extraModulePackages`.

### Automatic CPU scheduler switching

`modules/desktop/scheduler.nix` runs `scx_loader --auto` as `scx-auto.service`,
replacing the always-running `scx.service`. The upstream policy attaches LAVD
after a logical CPU remains above 90% utilization for more than five seconds,
and returns to the kernel's fair scheduler (EEVDF) after the low-utilization
timer exceeds 30 seconds. This is load-triggered switching, not game detection
or merely LAVD's internal Auto power profile. Short load bursts and unexpected
child exits inherit the upstream controller's timer/recovery limitations.

This mode does not expose the loader's D-Bus interface; `scxctl` is not a control
interface for this service. Use `systemctl status scx-auto`,
`journalctl -u scx-auto`, and `/sys/kernel/sched_ext/state` to inspect it.
`sudo systemctl stop scx-auto` detaches its scheduler and restores EEVDF;
`sudo systemctl start scx-auto` resumes automatic control. Do not run another
sched_ext daemon alongside it. Kernel-version support alone is insufficient;
the customized configuration explicitly retains the BPF/BTF requirements.

## コーディングエージェント

Claude Code (`claude`) is installed through Home Manager's `programs.claude-code`
in the common profile. It is on the normal user PATH in every shell,
independently of T3 Code. Its existing credentials and editable settings are
preserved, and it follows the `claude-code` flake input.

- Claude Code の設定（`~/.claude`）は基本的に Nix で管理していません。
  例外として [coding-agents](home/keewai/common/coding-agents/default.nix) がスキルと MCP サーバーを配ります。
  - スキル: `codingAgents.skills`（[skills/](skills/) の全ディレクトリを自動登録）を `~/.claude/skills/` と `~/.agents/skills/` にリンクします。
    [shadcn/ui の公式スキル](https://ui.shadcn.com/docs/skills)は [shadcn.nix](home/keewai/common/coding-agents/shadcn.nix) で取得元のコミットとハッシュを固定し、参照資料とスクリプトを含めて配布します。実行に必要な Node.js・npm・npx も同じ設定で導入します。
  - MCP: `codingAgents.mcpServers.<name> = { command; args; env; }` を、Home Manager の有効化時に `~/.claude.json` の `mcpServers` へ書き込みます。
    Nix から外したサーバーだけを削除し、手動で追加したサーバーや他の設定はそのまま残します。
- Hyprland 専用の Hypruse MCP は Umbriel への移行に伴い登録を外しています。Noctalia のスクリーンショット機能は使えますが、Hypruse のデスクトップ操作 API の代替ではありません。ブラウザー操作には実行環境が提供するブラウザーツールを使います。
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

### T3 Code nightly

[T3 Code](https://github.com/pingdotgg/t3code) runs as a desktop app on citrus and a
headless user service on orange. Its official nightly
AppImage is selected from the GitHub release metadata pinned by `t3code-releases`;
the artifact URL and SHA-256 come from that same locked metadata. Update with
`nix flake update t3code-releases`, then follow the activation procedure above.
The in-app updater is disabled; Nix owns the application and its bundled `t3` CLI.

- Launch **T3 Code (Nightly)** or run `t3code`. The Home Manager user service starts
  it with the graphical session. Use `systemctl --user restart t3code` after an
  update, once active tasks have finished. Do not run a second `t3 serve` against
  the same `~/.t3` state directory.
- While the desktop app is running, its backend is loopback-only and Tailscale
  Serve exposes `https://citrus.tail1e65cd.ts.net/` to the tailnet over HTTPS 443,
  including WebSockets.
  This is not public internet access and does not use Funnel.
- Orange's `t3code` user service starts at boot and reuses `~/.t3`, including its
  environment identity, paired devices, projects, and conversation history.
  [t3code.nix](hosts/orange/services/t3code.nix) routes its API and WebSockets
  through the shared HTTPS 443 entry point. The root page remains Immich; use the
  native T3 app or `https://app.t3.codes/` to connect to the orange environment.
- Pair each browser or mobile device from **Settings → Connections**. On citrus,
  `t3 pair --tailscale` also works locally. On orange, use
  `t3 auth pairing create --base-url https://orange.tail1e65cd.ts.net` to preserve
  the shared nginx routing. Pairing links are credentials: keep them private.
  Opening the bare HTTPS URL does not authorize a new device.
- Claude uses its Home Manager executable and the ordinary `~/.claude` login. If
  needed, use `claude auth login`, then rescan the providers in T3 Code.
- GitHub uses the existing `gh` login and Home Manager's Git credential helper.
  Check with `gh auth status`; sign in with `gh auth login` if necessary, then
  choose **Settings → Source Control → Rescan**. No token is copied into Nix.
- Activation merges only the managed connection/provider fields into the existing
  settings. Projects, history, other preferences, and stored credentials remain.
  The app can run commands with the user's permissions; tailnet access does not
  make it a sandbox.

## citrus（デスクトップ）

- **画面構成**：Umbriel + Noctalia v5。`start-umbriel` がセッションを管理し、Home Manager の `noctalia.service` は `umbriel-session.target` で起動します。`Super+Space` でランチャー、`Super+,` で設定、`Super+V` でクリップボード、`Super+Tab` でワークスペース一覧。音量・マイクミュート・再生・明るさのメディアキーと `Print` のスクリーンショットにも対応します。
- **配色**：Noctalia で選んだパレットをアプリ全体に反映します。公式テンプレートで Umbriel・GTK 3/4・Qt 5/6・KDE・Kitty・btop を統一し、[コミュニティテンプレート](https://github.com/noctalia-dev/community-templates)で Legcord の System24・Fcitx5・bat・FZF・Starship・Helium・Claude Code・Codex CLI を連動させます。Steam は既存スキン用の CSS を同じパレットから生成します。GTK・Qt・Helium など、色を再読み込みしないアプリには再起動が必要です。
- **テーマの管理**：[noctalia-templates.nix](home/keewai/desktop/noctalia-templates.nix) に連携を集約します。コミュニティのソースは flake 入力で固定し、`nix flake update` で更新します。Nix 管理の設定との競合を避けるため、必要なテンプレートを User Templates として登録します。設定やフォントは Home Manager が管理し、生成される配色ファイルは Noctalia が管理します。FZF は生成したオプションファイルを起動ごとに読むため、シェル設定への色の追記は不要です。
- **フォントと初期設定**：Stylix は共通のフォント・アイコン・カーソルとコンソールの配色を担当します。Home Manager は NixOS 側の設定を継承します。初期パレットの [Tokyo Night Black](themes/tokyo-night-black/default.nix) は端末の ANSI 色も含めて一か所で定義し、ログイン後は Noctalia の選択に従います。初期の壁紙は [Surface Laptop Ultra Dark](themes/tokyo-night-black/surface-laptop-ultra-dark.png)（5120×2160）です。
- **更新とキャッシュ**：Umbriel と Noctalia は公式 `cachix` ブランチを追い、対応する署名付きキャッシュを利用します。各入力の nixpkgs は上書きせず、キャッシュと一致させます。
- Citrus's configured physical monitor and `SUNSHINE` each keep ten static
  workspaces. `Super+1` through `Super+0` select them; adding Shift moves a window.
  Unconfigured additional outputs retain Umbriel's default dynamic inventory.
- **日本語入力**：Hazkey。keyd で `` Alt+` `` を変換キーに割り当て、Logitech 製キーボードは除外。
- **ブラウザー**：既定は [Helium](https://github.com/imputnet/helium-linux)（公式リリースを [pkgs/helium](pkgs/helium/) でパッケージ化。nixpkgs の Widevine CDM を読み込ませて DRM 動画も再生可）。TwinStar・OpenMouse の WebHID 設定アプリも Helium のアプリモードで開きます。
- **Bitwarden**：デスクトップアプリと SSH エージェント。
- **Apple Music**：[keewai704/siora](https://github.com/keewai704/siora) の最新リリースの AppImage。Home Manager の適用時に `gh` の認証で `~/.local/share/siora/` へ取得・更新します（手動は `siora-update`）。起動は `siora`。

### Sunshine 配信

Umbriel 上に `SUNSHINE` という仮想画面を作り、NVENC で Moonlight に配信します。
管理画面は citrus 上の `https://localhost:47990` のみ。

Recovery restores each output's active workspace and surviving active-window
focus, then the original focused output. It does not visit inactive workspaces
to rebuild their internal focus history: doing so can prune anonymous empty
dynamic workspaces and change their logical positions. Surviving saved windows
must return to their logical workspace/output before the stream is torn down.

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
配信のため Noctalia のアイドル時ロック・消灯・サスペンドは明示的に無効化し、ロックのキー割り当ても設けません。Proton の Wayland ドライバーで配信画面を選ぶ必要があるゲームには、起動オプション `WAYLANDDRV_PRIMARY_MONITOR=SUNSHINE %command%` を個別に指定します。

## orange（サーバー）

外部からの Web アクセスは **Tailscale Serve (HTTPS 443) → nginx (127.0.0.1:8000) → 各アプリ（loopback）** の一本道です。
アプリを LAN やワイルドカードアドレスで公開しません。詳しい規則は [AGENTS.md](AGENTS.md#orange-web-exposure)。

| サービス | URL・用途 | 設定 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich.nix](hosts/orange/services/immich.nix) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden.nix](hosts/orange/services/vaultwarden.nix) |
| T3 Code | Native app / `https://app.t3.codes/`, environment `https://orange.tail1e65cd.ts.net` | [t3code.nix](hosts/orange/services/t3code.nix) |
| Samba | HDD 共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | Fabric サーバー | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale Exit Node | 出口ノード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |
| 公開経路 | nginx と Tailscale Serve | [web.nix](hosts/orange/services/web.nix) |

- ポート・パス・URL は [settings.nix](hosts/orange/settings.nix) にまとめています。
- 起動順は「HDD マウント → 共有ディレクトリ準備 → 既存データ取り込み → アプリ」です（[storage.nix](hosts/orange/services/storage.nix)）。
- [local-backup](hosts/orange/services/local-backup.nix) がバックアップ、[health-monitor](hosts/orange/services/health-monitor.nix) が 15 分ごとに異常を Discord へ通知、
  [smart-tests](hosts/orange/services/smart-tests.nix) がディスク診断、[maintenance](hosts/orange/services/maintenance.nix) がログ掃除・TRIM・Store 保守を行います。
- 長いシェル処理は `.sh` テンプレートに置き、`@名前@` を `fillTemplate`（[default.nix](hosts/orange/default.nix)）で置換して使います（テンプレートを直接実行しない）。

## パッケージと入力の方針

- [pkgs/default.nix](pkgs/default.nix) に並べたものは設定から `pkgs.local.<名前>` で参照でき、`nix build .#<名前>` で単体ビルドもできます。
- パッチは対象パッケージのディレクトリに置きます。
- 更新の入口は `nix flake update` に統一します。再現性のための revision と hash は `flake.lock` に残します。
- Umbriel／Noctalia は `cachix`、xddxdd のカーネル群は `master` を追います。バージョン番号の固定タグは使いません。
- The flake-update migration is not yet complete: custom packages such as Helium,
  xpad, Penpot MCP, and LiveSync, the shadcn skill source, and Orange's
  Minecraft/mod compatibility set still contain manually maintained versions or
  dependency hashes. Updating `flake.lock` alone does not update those sources.
- 非自由パッケージは全体で許可しています（`allowUnfree = true`）。
- `system.stateVersion` / `home.stateVersion` は互換性の基準なので、アップデートに合わせて変えません。
