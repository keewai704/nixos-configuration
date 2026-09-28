# nixos-configuration

`x86_64-linux` 向けの NixOS / Home Manager 構成です。

| ホスト | 役割 |
| --- | --- |
| `citrus` | Windows 11 / WSL2 上の開発・CLI 環境 |
| `orange` | 自宅サーバー（Immich、Vaultwarden、Samba、Minecraft、バックアップ） |

作業・検証・コミット・適用の規則は [AGENTS.md](AGENTS.md) を参照してください。

## 構成

```text
flake.nix
├── modules/common/                  Nix、ユーザー、ネットワークの共通既定値
│   └── home-manager.nix
│       └── home/keewai/common/       シェル、Git、開発ツール、エージェント、スキル
├── hosts/citrus/
│   ├── default.nix                  ホスト名とプロファイルの接続
│   └── wsl.nix                      NixOS-WSL、Windows 連携、ネットワークの上書き
│       └── home/keewai/wsl/          Windows の既定アプリを開く CLI 連携
└── hosts/orange/                     サーバーのハードウェアとサービス
```

| 変更対象 | 編集先 |
| --- | --- |
| CLI パッケージ | [home/keewai/common/packages.nix](home/keewai/common/packages.nix) |
| シェル・プロンプト | [shell.nix](home/keewai/common/shell.nix)、[starship.toml](home/keewai/common/starship.toml) |
| Git / GitHub CLI | [git.nix](home/keewai/common/git.nix) |
| Claude Code / Codex / MCP | [coding-agents.nix](home/keewai/common/coding-agents.nix) |
| 個人スキル | [skills/](skills/)、[配布設定](home/keewai/common/skills.nix) |
| WSL と Windows の連携 | [hosts/citrus/wsl.nix](hosts/citrus/wsl.nix)、[home/keewai/wsl](home/keewai/wsl/default.nix) |
| 開発シェル | [devshell/default.nix](devshell/default.nix) |
| orange のサービス | [hosts/orange/services/](hosts/orange/services/)、[settings.nix](hosts/orange/settings.nix) |

## citrus（WSL2）

Windows がカーネル、ディスク、ネットワーク、DNS、GPU ドライバーを管理します。
NixOS-WSL が systemd、Windows 実行ファイルとの相互運用、`/mnt/c` を提供します。
物理 PC 用のブートローダー・ディスク設定・Hyprland・NVIDIA カーネルモジュール・
音声デーモン・指紋認証・Sunshine は構成から取り除いています。
Windows アプリはインストールしません。スタートメニューへの Linux ランチャー生成も無効です。

- Linux ユーザーは `keewai`、ホスト名は `citrus`。zsh と既存のプロンプト・補完を使います。
- Git、GitHub CLI、Python、ripgrep、gws、既存 CLI ツールを引き継ぎます。
- Claude Code / Codex と Context7 / Serena MCP、個人スキルを引き継ぎます。
  認証情報は別途ログインが必要です。Windows 側の資格情報をコピーしません。
- `programs.nix-ld` により、一般的な Linux 向け開発ツールの動的リンクを補助します。
- `open <パスまたはURL>` / `wsl-open` は既存の Windows 既定アプリを利用します。
- Windows 側の Tailscale を利用するため、WSL 内の Tailscale、SSH サーバー、
  NetworkManager は無効です。通信の公開制御は Windows / WSL のファイアウォール側です。
- Whisper は CPU 版です。Apple USB CLI は残りますが、USB 利用には別途転送設定が必要です。
- 日本語ロケール、Asia/Tokyo、既存のパスワード不要 sudo 設定を維持します。

PowerShell から起動します。

```powershell
wsl -d citrus
wsl -d citrus --cd /home/keewai/nixos-configuration
```

作業リポジトリは Linux ファイルシステム上の `/home/keewai/nixos-configuration` に置きます。

```sh
cd ~/nixos-configuration
nix develop
sudo nixos-rebuild test --flake .#citrus --no-write-lock-file
sudo nixos-rebuild switch --flake .#citrus --no-write-lock-file
```

`test` の後にネットワークと systemd の失敗ユニット、変更機能を確認してから `switch` します。
`system.stateVersion` / `home.stateVersion` は `26.05` のまま維持します。
入力は `flake.lock` に固定されます。必要な入力のみ `nix flake update <入力名>` で更新します。

### 新しい PC への導入

[NixOS-WSL の公式手順](https://nix-community.github.io/NixOS-WSL/install.html)に従い、
公式 `nixos.wsl` のチェックサムを検証して `citrus` として WSL2 にインポートします。
既存ディストリビューションは登録解除しません。

初回のみ、配布イメージの `/etc/nixos/configuration.nix` で `wsl.defaultUser = "keewai";`、
`networking.hostName = "citrus";` を設定し、`sudo nixos-rebuild boot` を実行します。
[ユーザー名変更手順](https://nix-community.github.io/NixOS-WSL/how-to/change-username.html)に従い、
PowerShell で次を実行してから、リポジトリの構成を適用します。

```powershell
wsl --terminate citrus
wsl -d citrus --user root -- true
wsl --terminate citrus
wsl -d citrus
```

`hostnamectl --static` と `/etc/hostname` がともに `citrus` であることを確認します。
再起動が必要な WSL 設定変更でも `wsl --terminate citrus` を用い、他の WSL 環境を停止させません。
通常の更新を戻す場合は `sudo nixos-rebuild switch --rollback` を使います。

## コーディングエージェント

Claude Code と Codex は Home Manager で管理します。
`~/.claude/settings.json` と `~/.codex/config.toml` は編集可能で、
有効化時に管理対象の設定・MCP 定義をマージします。
`skills/` は `~/.claude/skills/` と `~/.agents/skills/` にリンクされます。
Linux デスクトップ専用の cua-driver は含みません。

リポジトリの検証手順は [.agents/skills/nixos-validation](.agents/skills/nixos-validation/SKILL.md) にあります。

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
