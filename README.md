# nixos-configuration

2台の NixOS マシンの設定です。どちらも `x86_64-linux` です。

| ホスト | 役割 |
| --- | --- |
| `citrus` | デスクトップ（Umbriel、Noctalia v5、NVIDIA、Steam、Sunshine 配信） |
| `orange` | 自宅サーバー（Immich、Vaultwarden、Samba、Minecraft、バックアップ） |

OS・ハードウェア・システムサービスは **NixOS**、個人のアプリや設定は **Home Manager** で管理します。
作業ルール（検証・コミット・適用の手順）は [AGENTS.md](AGENTS.md) にあります。

両ホストの Tailscale SSH は、[Tailworm の報告](https://tailworm.com/)への暫定対策として
TCP・Unix ソケットのローカル／リモート転送を禁止しています。SSH ログインは利用できます。
`tailscaled` のメモリは 1 GiB、スワップは 0 に制限し、メモリ枯渇時の影響を抑えます。
設定は [modules/common/network.nix](modules/common/network.nix) で管理します。

## ディレクトリ構成

```text
.
├── flake.nix            入力（依存リポジトリ）、ホスト一覧、開発用シェル
├── hosts/               マシンごとの設定
│   ├── citrus/          ハードウェア、起動、カーネル、音声、Sunshine など
│   └── orange/          ハードウェア、起動、settings.nix、services/ にサーバー機能
├── modules/             NixOS 側の共通設定
│   ├── common/          全ホスト共通（Nix、ネットワーク、ユーザー、Home Manager の接続）
│   └── desktop/         デスクトップの OS 側（Umbriel、Steam、Stylix、CPU スケジューラーなど）
├── home/keewai/         個人設定（Home Manager）
│   ├── common/          全ホスト共通（シェル、Git、コーディングエージェント、T3 Code）
│   └── desktop/         デスクトップ用アプリ（ブラウザー、端末、入力、Noctalia など）
├── pkgs/                自作・改造パッケージとパッチ
├── skills/              Claude Code に配る個人スキル
├── themes/              共通テーマ（色・フォント・壁紙）
└── secrets/             agenix で暗号化した秘密情報
```

1つの機能が複数のファイルを使う場合は、ディレクトリにまとめて `default.nix` を入口にします
（例：`home/keewai/desktop/noctalia/`、`apple-sharing/`）。シェルスクリプトや画像などの素材も、
使う側の `.nix` と同じ場所に置きます。

### 読み込みの流れ

```text
flake.nix
└── nixosConfigurations.<host>
    ├── modules/common            全ホスト
    │   └── home-manager.nix  →  home/keewai/common
    └── hosts/<host>
        └── (citrus のみ) modules/desktop  →  home/keewai/desktop
```

ホストを増やすときは `hosts/<名前>/default.nix` を作り、`flake.nix` のホスト一覧に名前を加えます。
デスクトップにする場合は、その imports に `../../modules/desktop` を加えます。

## やりたいこと別の編集先

| やりたいこと | 編集するファイル |
| --- | --- |
| CLI ツールを追加 | [home/keewai/common/packages.nix](home/keewai/common/packages.nix) |
| シェル・エイリアス・プロンプト | [shell/](home/keewai/common/shell/default.nix)（`starship.toml` も同じ場所） |
| Git / GitHub CLI | [git.nix](home/keewai/common/git.nix) |
| Claude Code・Codex・スキル・MCP サーバー | [coding-agents/](home/keewai/common/coding-agents/default.nix)、[skills/](skills/) |
| T3 Code（nightly サーバー） | [t3code.nix](home/keewai/common/t3code.nix)、[pkgs/t3code](pkgs/t3code/) |
| DeepSeek Harness・Claude/ChatGPT 接続・日本語 | [deepseek-harness](home/keewai/common/deepseek-harness/)、[pkgs/deepseek-harness](pkgs/deepseek-harness/) |
| 設定のいらない GUI アプリを追加 | [home/keewai/desktop/packages.nix](home/keewai/desktop/packages.nix) |
| ウィンドウ操作・キー割り当て | [umbriel.nix](home/keewai/desktop/umbriel.nix) |
| モニター・解像度 | [hosts/citrus/display.nix](hosts/citrus/display.nix) |
| Umbriel 本体・ログイン画面 | [modules/desktop/umbriel.nix](modules/desktop/umbriel.nix) |
| パネル・ランチャー・通知・壁紙 | [noctalia/](home/keewai/desktop/noctalia/default.nix) |
| アプリの配色テンプレート | [noctalia/templates/](home/keewai/desktop/noctalia/templates/default.nix) |
| 日本語入力 | [input-method.nix](home/keewai/desktop/input-method.nix)、[modules/desktop/input-method.nix](modules/desktop/input-method.nix) |
| 端末・ブラウザー・ファイル管理 | [kitty.nix](home/keewai/desktop/kitty.nix)、[browser.nix](home/keewai/desktop/browser.nix)、[file-manager.nix](home/keewai/desktop/file-manager.nix) |
| Discord | [legcord.nix](home/keewai/desktop/legcord.nix) |
| Steam | [modules/desktop/steam.nix](modules/desktop/steam.nix)、[scskiller/](home/keewai/desktop/scskiller/default.nix) |
| AirDrop・AirPlay | [apple-sharing/](home/keewai/desktop/apple-sharing/default.nix)、[hosts/citrus/apple-sharing.nix](hosts/citrus/apple-sharing.nix) |
| 共通フォント・初期パレット | [themes/tokyo-night-black](themes/tokyo-night-black/default.nix) |
| citrus のハードウェア | [hosts/citrus/](hosts/citrus/) |
| orange のサービス・ポート・保存先 | [hosts/orange/services/](hosts/orange/services/)、[settings.nix](hosts/orange/settings.nix) |

迷ったときは次の基準で置き場所を決めます。

- **ログイン、ドライバー、udev、PAM、デーモンなど OS との連携** → NixOS（`modules/` か `hosts/`）
- **自分だけが使うアプリや設定ファイル** → Home Manager（`home/keewai/`）
- **特定のマシンのハードウェアに依存するもの** → `hosts/<host>/`

## よく使うコマンド

```sh
nix flake update                                                  # 入力をまとめて更新（適用の前に毎回実行してコミット）
sudo nixos-rebuild test --accept-flake-config --flake .#citrus    # 一時的に適用して動作確認（再起動で戻る）
sudo nixos-rebuild switch --accept-flake-config --flake .#citrus  # 本適用（起動時の既定にもなる）
nix fmt                                                           # Nix ファイルを整形
nix develop                                                       # 言語サーバーや整形ツール入りのシェル
nix build --accept-flake-config .#<パッケージ名>                   # pkgs/ のパッケージを単体でビルド
```

`nixos-rebuild` には、必ず実行中のマシン自身の名前（`hostname` の結果）を指定します。

## バイナリキャッシュ

`flake.nix` の `nixConfig` には、`modules/common/nix.nix`、`hosts/citrus/kernel.nix`、
`hosts/citrus/nvidia.nix` と同じキャッシュの URL と署名鍵を書いています。
`nixConfig` には import や計算式が使えないため、両方を手で同じ内容に保ちます。

- 新しい設定を適用する前の最初のビルドでもキャッシュを使えるよう、`nixos-rebuild` と `nix build` には
  `--accept-flake-config` を付けます。初回の適用前に単体ビルドするときは
  `sudo nix build --accept-flake-config --no-link .#<パッケージ>` を使います
  （信頼されていない利用者は、flake を受け入れても新しいキャッシュや鍵を追加できないため）。
- `accept-flake-config` を全体で有効にはしません。中身を確かめた flake のキャッシュ設定だけを受け入れます。
- CUDA と CachyOS カーネル用のキャッシュは、インストール後の設定では citrus だけが使います。
  `cache.nixos.org` はそのまま使います。
- Flox の公開キャッシュは優先度 50 で、`cache.nixos.org` より後に使います。
  今のロックで使う CUDA 対応 Sunshine のビルド済みバイナリを得るためのものです。
  信頼したキャッシュは Sunshine に限らずどのパッケージにも署名できます。
- キャッシュに載るのは、まったく同じストアパスのものだけです。自前のパッチ、CUDA の上書き、
  独自カーネルとそのモジュールなどは手元でビルドされます。署名の検証は無効にしません。

## citrus（デスクトップ）

- **画面**：Umbriel と Noctalia v5。`start-umbriel` がセッションを管理し、Noctalia は
  `umbriel-session.target` と一緒に起動します。`Super+Space` でランチャー、`Super+,` で設定、
  `Super+V` でクリップボード、`Super+Tab` でワークスペース一覧です。音量・マイク・再生・明るさの
  メディアキーと、`Print` のスクリーンショットも使えます。
- **ワークスペース**：実モニターと `SUNSHINE` の画面にそれぞれ 10 個あります。
  `Super+1`〜`Super+0` で切り替え、`Shift` を足すとウィンドウを移動します。
  設定していない追加の画面は Umbriel の既定どおり動的に増減します。
- **配色**：Noctalia で選んだパレットをアプリ全体に反映します。公式テンプレートで Umbriel・GTK 3/4・
  Qt 5/6・KDE・Kitty・btop を、[コミュニティテンプレート](https://github.com/noctalia-dev/community-templates)で
  Legcord（System24）・Fcitx5・bat・FZF・Starship・Helium・Claude Code・Codex CLI をそろえます。
  Steam は既存スキン用の CSS を同じパレットから作ります。GTK・Qt・Helium などは再起動で反映されます。
- **テーマの管理**：[noctalia/templates/](home/keewai/desktop/noctalia/templates/default.nix) にまとめています。
  コミュニティのテンプレートは flake 入力で固定し、`nix flake update` で更新します。
  設定とフォントは Home Manager が、生成される配色ファイルは Noctalia が管理します。
- **フォントと初期設定**：Stylix が共通のフォント・アイコン・カーソルとコンソールの配色を受け持ちます。
  初期パレットの [Tokyo Night Black](themes/tokyo-night-black/default.nix) は端末の ANSI 色も含めて1か所で定義し、
  ログイン後は Noctalia の選択に従います。初期の壁紙は Surface Laptop Ultra Dark（5120×2160）です。
- **更新とキャッシュ**：Umbriel と Noctalia は公式の `cachix` ブランチを追い、その署名付きキャッシュを使います。
  キャッシュと一致させるため、各入力の nixpkgs は上書きしません。
- **日本語入力**：Fcitx5 と Meltype。keyd で `` Alt+` `` を変換キーに割り当てます（Logitech 製キーボードは除外）。
- **ブラウザー**：既定は [Helium](https://github.com/imputnet/helium-linux)（[pkgs/helium](pkgs/helium/)）。
  nixpkgs の Widevine CDM を読み込むので DRM 付きの動画も再生できます。TwinStar・OpenMouse の
  WebHID 設定アプリも Helium のアプリモードで開きます。
- **Bitwarden**：デスクトップアプリと SSH エージェント。
- **Apple Music**：[keewai704/siora](https://github.com/keewai704/siora) の最新リリースの AppImage。
  Home Manager の適用時に `gh` の認証で `~/.local/share/siora/` へ取得・更新します（手動では `siora-update`）。

### カーネル

xddxdd の `nix-cachyos-kernel`（`master` ブランチ）の入力と、その入力が固定する nixpkgs を使います。
最新リリースの ThinLTO 版を選び、RC の元になるリリースのほうが新しければ RC 版を選びます。
カーネル・NVIDIA ドライバー・CachyOS の ZFS モジュールのバージョンは、この入力に任せます。

[kernel-config.nix](hosts/citrus/kernel-config.nix) は Ryzen 7 9800X3D 向けに CachyOS の設定を絞り込みます。
`znver5` 向けの最適化、Clang ThinLTO、CPU 数の上限 32 を指定し、使わない PCI イーサネット、
古いストレージコントローラー、Intel・旧 Radeon・Nouveau のグラフィックス、テレビ・ラジオ関連、
仮想マシンのゲスト用機能などを外します。I226-V、MT7925、AMD 内蔵グラフィックス、NVIDIA、NVMe/AHCI、
USB、HID、音声、KVM、コンテナー、ZFS、sched_ext/BPF/BTF は残します。
新しい PCI 機器を挿したときは、外した項目を見直す必要があります。

この独自カーネルに合わせて NVIDIA・ZFS・BEITONG の xpad モジュールも手元でビルドされます。
ビルドや適用が成功しても、新しいカーネルで起動できるかは再起動するまでわかりません。
上流の事件（`xddxdd/nix-cachyos-kernel#110`）を受けて、旧 Lantian キャッシュは信頼しません。
代わりに上流の README と issue #89 で紹介されている `https://cache.xinux.uz` を使います。

### CPU スケジューラーの自動切り替え

[scheduler.nix](modules/desktop/scheduler.nix) が `scx_loader --auto` を `scx-auto.service` として動かします。
論理 CPU の使用率が 90% を超える状態が 5 秒続くと LAVD に切り替え、低い状態が 30 秒続くと
カーネル標準の EEVDF に戻します。ゲームの検出ではなく、負荷による切り替えです。

`scxctl` では操作できません。状態は `systemctl status scx-auto`、`journalctl -u scx-auto`、
`/sys/kernel/sched_ext/state` で確かめます。`sudo systemctl stop scx-auto` で EEVDF に戻り、
`start` で自動制御を再開します。ほかの sched_ext デーモンと同時に動かさないでください。

### Sunshine 配信

Umbriel 上に `SUNSHINE` という仮想画面を作り、NVENC で Moonlight に配信します。
管理画面は citrus 上の `https://localhost:47990` だけで開けます。

| Moonlight のアプリ | 動作 |
| --- | --- |
| `Extend Display` | 既存の画面の右に仮想画面を追加 |
| `Steam Big Picture` | 仮想画面だけにして Steam Big Picture を起動 |
| `Client Only` | 仮想画面だけを表示 |

低遅延の例：

```sh
moonlight stream citrus "Extend Display" --1080 --fps 120 --bitrate 40000 --video-codec H.264 --video-decoder hardware --no-vsync --no-frame-pacing --no-hdr
```

- 切断しただけではアプリは動き続けます。元の画面構成に戻すには、Moonlight で「アプリを終了」します。
- 戻すときは、各画面で開いていたワークスペースと選択中のウィンドウ、最後に選んでいた画面を元に戻します。
  開いていなかったワークスペースは訪れません（空のワークスペースが消えて並びが変わるのを防ぐため）。
- 配信のため、Noctalia のアイドル時のロック・消灯・サスペンドは無効にしています。
- Proton の Wayland ドライバーで配信画面を選ぶ必要があるゲームには、起動オプション
  `WAYLANDDRV_PRIMARY_MONITOR=SUNSHINE %command%` を個別に指定します。

## コーディングエージェント

Claude Code と Codex は全ホストで Home Manager が導入し、どのシェルからでも使えます。
`~/.claude` の設定やログイン情報は基本的に Nix で管理しません。例外として
[coding-agents/](home/keewai/common/coding-agents/default.nix) が次のものを配ります。

- **スキル**：[skills/](skills/) の全ディレクトリを `~/.claude/skills/` と `~/.agents/skills/` にリンクします。
  [shadcn/ui の公式スキル](https://ui.shadcn.com/docs/skills)は [shadcn.nix](home/keewai/common/coding-agents/shadcn.nix)
  で取得元を固定して配ります。
- **MCP サーバー**：`codingAgents.mcpServers.<名前> = { command; args; env; }` を、適用時に `~/.claude.json` へ書き込みます。
  Nix から外したサーバーだけを消し、手で追加したサーバーはそのまま残します。
- **Claude Code の共通指示**：全ホストで [共通の UI・開発方針](home/keewai/common/coding-agents/shared-instructions.md)を
  `~/.claude/CLAUDE.md` に置きます。citrus では [CLAUDE.md](home/keewai/common/coding-agents/CLAUDE.md) の
  日本語応答・Git 操作の方針も追加します（`codingAgents.globalInstructions`）。
- **Codex の共通指示**：[codex-instructions.md](home/keewai/common/coding-agents/codex-instructions.md) と共通の UI・開発方針を
  両ホストの `~/.codex/config.toml` の `developer_instructions` に設定します。
  [OpenCode の方針](https://github.com/anomalyco/opencode/blob/dev/AGENTS.md)を参考にした実装・検証の指示が、
  全プロジェクトの新しい Codex セッションで組み込み指示に追加されます。
  プロジェクト固有の `AGENTS.md` の規約を尊重し、手動の設定やログイン情報は保持します。
- UI デザインには [Penpot](https://design.penpot.app/) を使います。デスクトップ用 MCP は
  [penpot-mcp.nix](home/keewai/desktop/penpot-mcp.nix)、手順は [penpot-apple-design](skills/penpot-apple-design/SKILL.md) にあります。

| スキル | 用途 |
| --- | --- |
| `ponytail` | 実装を単純に保つ（KISS / YAGNI） |
| `superpowers` | 設計・計画・デバッグ・レビューなど大きめの作業の進め方 |
| `add-nix-skill` | このリポジトリでスキルを追加・修正するとき |
| `apple-device-usb` | USB や Wi-Fi 経由で iPhone・iPad を操作 |
| `penpot-apple-design` | Penpot の操作と、Apple 系 UI 向けアセットの選定 |
| `faster-whisper` | 音声・動画の文字起こし |
| `shadcn` | shadcn/ui の部品の導入・調整 |

端末操作 GUI と `apple-device-usb` の実装は
[iphone-control](https://github.com/keewai704/iphone-control) で管理します。
このリポジトリには flake 入力、導入設定、スキルの手順を置きます。

リポジトリ専用の検証手順は [.agents/skills/nixos-validation](.agents/skills/nixos-validation/SKILL.md) にあります。

### T3 Code nightly

[T3 Code](https://github.com/pingdotgg/t3code) は、両ホストとも Home Manager の常駐サーバーとして動きます。
共通設定は [t3code.nix](modules/common/t3code.nix)、ユーザーサービスは [t3code.nix](home/keewai/common/t3code.nix) が管理します。
公式の nightly AppImage に含まれる CLI を `t3 serve` で実行し、グラフィカルセッションには依存しません。
リリース情報は `t3code-releases` 入力で固定し、更新は `nix flake update` と通常の適用手順で行います。
アプリ内の自動更新は無効です。

- Web 画面は `https://orange.tail1e65cd.ts.net/t3/` と `https://citrus-1.tail1e65cd.ts.net/t3/` です。
  Tailscale Serve HTTPS 443 → `127.0.0.1:8000` の nginx → `127.0.0.1:3773` のサーバーで配信し、API と WebSocket も同じ HTTPS 入口を通ります。
  `/t3/` 用に Web 画面のルーター、静的ファイル参照、PWA manifest をパッケージ内で補正します。
  orange のルートは Immich、citrus のルートは `/t3/` への転送です。
- 起動時にサービスが始まり、既存の `~/.t3` のペアリング、プロジェクト、会話履歴を使います。
  同じ `~/.t3` に対してデスクトップ版や別の `t3 serve` を同時起動しないでください。
- 端末のペアリングは **Settings → Sharing & access** または
  `t3 auth pairing create --base-url https://orange.tail1e65cd.ts.net` を使います。
  citrus では URL を `https://citrus-1.tail1e65cd.ts.net` に置き換えます。
  `t3 pair --tailscale` は共通の Serve 設定を変更するため使いません。
  ペアリングのリンクは認証情報なので、ほかの人に見せないでください。
- Claude は Home Manager の実行ファイルと通常の `~/.claude` のログインを使います。必要なら
  `claude auth login` のあと、T3 Code でプロバイダーを再検出します。
- GitHub は既存の `gh` のログインを使います。`gh auth status` で確かめ、必要なら `gh auth login` のあと
  **Settings → Source Control → Rescan** を選びます。トークンを Nix にコピーすることはありません。
- T3 Code は利用者の権限でコマンドを実行できます。
  tailnet 内だけの公開でも、隔離された環境になるわけではありません。

### DeepSeek Harness pre-release

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) の npm `next` チャンネルを両ホストに導入します。
`dsh-web` ユーザーサービスが `http://127.0.0.1:3080` で Web UI を起動します。
ランチャーの **DeepSeek Harness** または `dsh-open` が認証付き URL をブラウザーで開きます。
ワークスペースを追加すると、既定の Claude Opus で会話できます。サービスの操作は
`systemctl --user restart dsh-web`、ログは `journalctl --user -u dsh-web` です。

- 独自の [dsh-claude-agent](pkgs/deepseek-harness/plugins/claude/) が公式 Claude Agent SDK を使います。
  Home Manager の Claude Code と通常の `claude auth login` の認証を使い、`supportedModels()` が返すモデル名・ID・推論レベルを表示します。
  既定の `claude-bridge` / `opus` を保持し、エイリアスが指す現行モデルも SDK に従います。
  会話・ツール結果の変換には [dsh-claude-bridge](https://github.com/shaneconner/dsh-claude-bridge) をライブラリとして使い、DSH のメッセージ形式と SDK の推論レベルに対応するパッチを同梱します。
  Nix の Node.js では `--expose-internals` で同じ内部ローダーを取得し、ネイティブアドオンの実行形式への依存を避けます。
- [dsh-mobile-maxxing](https://github.com/kuraneko1/dsh-mobile-maxxing) が PWA・通知・モバイル操作を提供します。
  両ホストとも Tailscale Serve HTTPS → ループバック nginx → `127.0.0.1:3080` で公開します。
  入口は `https://orange.tail1e65cd.ts.net/dsh/` と `https://citrus-1.tail1e65cd.ts.net/dsh/` です。
  `dsh-open` が開く認証付き URL を使います。認証トークンはログに含まれるため共有しないでください。
- 同じ配布元の [dsh-locale-ja](https://github.com/kuraneko1/dsh-mobile-maxxing/tree/main/packages/dsh-locale-ja) が言語選択に **日本語** を追加します。
  DSH の bundle 登録定義と現在のランタイムに対する依存宣言を Nix 側で補い、選択中の表示言語は保持します。
- 独自の [dsh-chatgpt-subscription](pkgs/deepseek-harness/plugins/chatgpt/) が **ChatGPT (subscription)** を追加します。
  Home Manager が導入する公式 Codex CLI の App Server を起動し、通常の `codex login` の認証と ChatGPT 契約に含まれる Codex / ChatGPT Work の利用枠を使います。
  `model/list` の全ページからモデル・推論レベルを取得し、モデル名を固定しません。会話と DSH ツールの変換には [dsh-codex-native](https://github.com/Tests4gptplay/dsh-codex-native) をライブラリとして使います。
  両接続のモデル一覧は30秒キャッシュし、5分ごとに再取得して変更を Web UI に通知します。旧接続プラグインの bundle は適用時に置き換えます。
- 独自の [dsh-subscription-usage](pkgs/deepseek-harness/plugins/usage/) がサイドバーに **使用状況** を追加します。
  **コスト・トークン・契約残量** を切り替え、過去24時間・7日・30日・90日とプロバイダー・モデルで絞り込めます。
  グラフ、モデル別内訳、キャッシュヒット率、API料金換算、単価の上書きに対応します。
  集計は別ワーカーで行い、会話本文をブラウザーへ返さず、ローカルの利用記録から統計値を作ります。
- 同じ配布元の CJK 修正コードを `rdsh-markdown-cjk` として登録し、PC・モバイル両方の Markdown 表示を修正します。
  URL 直後の日本語の括弧や太字の終端をリンクに巻き込まず、URL 内の日本語パスは保持します。
  修正版の配信パスでもコードの色付け用ファイルと CSS を取得できるよう、相対参照を補正します。
- 取得元は flake 入力、npm の依存関係はパッケージ内のロックで管理します。
  更新は `nix flake update` のあと、リポジトリのルートで
  `nix run --no-write-lock-file .#deepseek-harness.updateScript` を実行し、生成された変更もコミットします。
  適用時は指定のプラグインと Claude 実行パスを設定し、利用者が追加したプラグインやモデル選択を保持します。

### 使用状況の集計規則

実装時に調査した T3 Code `0.1.3-nightly.20261026.3717`（`1316d48`）の
[利用ガイド](https://github.com/pingdotgg/t3code/blob/1316d48b0c68151afd8b47eb0c11a114cf0b4daa/docs/user/usage.md)、
[トークン契約](https://github.com/pingdotgg/t3code/blob/1316d48b0c68151afd8b47eb0c11a114cf0b4daa/packages/contracts/src/usage.ts)、
[集計](https://github.com/pingdotgg/t3code/blob/1316d48b0c68151afd8b47eb0c11a114cf0b4daa/apps/server/src/usage/usageAggregation.ts)、
[料金計算](https://github.com/pingdotgg/t3code/blob/1316d48b0c68151afd8b47eb0c11a114cf0b4daa/apps/server/src/usage/usagePricing.ts)を確認し、次の規則を採用しています。

- 処理トークンは未キャッシュ入力・キャッシュ読取・キャッシュ書込・出力の合計です。推論トークンは出力の内数として表示し、合計と料金に二重加算しません。キャッシュヒット率の分母は入力3種の合計です。
- Claude は `projects/**/*.jsonl` のモデル・usage を読み、message ID と request ID による重複を除外します。SDK の呼び出しもこの履歴に残るため、DSH 側の同じ呼び出しは加算しません。
- Codex は `sessions` と `archived_sessions` を読み、累積カウンターの再送、再開、分岐でコピーされた履歴を区別します。DSH の ChatGPT 接続は ephemeral なため、こちらは DSH の圧縮セッション履歴から加算し、message ID で重複を除外します。不正・未完の記録は集計元の状態に表示します。
- 料金は T3 と同じ LiteLLM の料金表を24時間キャッシュし、手動更新は最短1分間隔です。キャッシュ単価・速度別単価・提供元の参考額を区別します。単価不明は未換算と表示し、明示した単価 `0` は無料として扱います。表示額は API 単価に換算した参考額です。
- 古い Codex 履歴に速度モードがない場合は、T3 の `statev2.sqlite` を読み取り専用で開き、[T3 と同じリクエスト開始時の選択](https://github.com/pingdotgg/t3code/blob/1316d48b0c68151afd8b47eb0c11a114cf0b4daa/apps/server/src/usage/CodexUsageHistory.ts)から補完します。新しい DSH 接続では Codex 設定の速度を記録します。互換処理の MIT ライセンスをパッケージ内に同梱しています。
- 日別の境界はブラウザーの IANA タイムゾーンを使い、過去24時間は時間別に表示します。
- 契約残量は T3 と同じ Claude SDK の usage コントロールと Codex `account/rateLimits/read` から取得します。5分キャッシュと手動更新に対応し、取得失敗を残量0として表示しません。全体の週間枠が尽きた場合はセッションの利用可能残量も0として表示します。

T3 は複数の接続先・アカウントもプールします。このプラグインは実行ホストの履歴と現在ログインしている Claude・ChatGPT を対象にします。
履歴のホームはプラグイン設定の `claudeHome` / `codexHome`、T3 の履歴 DB は `t3Database`（空文字で無効）、単価の上書きは使用状況の **モデル単価** で変更できます。

## orange（サーバー）

外部からの Web アクセスは **Tailscale Serve（HTTPS 443）→ nginx（127.0.0.1:8000）→ 各アプリ（ループバック）** の一本道です。
アプリを LAN やすべてのアドレスに向けて公開しません。詳しい規則は [AGENTS.md](AGENTS.md#orange-web-exposure) にあります。

| サービス | URL・用途 | 設定 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich.nix](hosts/orange/services/immich.nix) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden.nix](hosts/orange/services/vaultwarden.nix) |
| Obsidian LiveSync | `https://orange.tail1e65cd.ts.net/couchdb/` | [obsidian-livesync.nix](hosts/orange/services/obsidian-livesync.nix) |
| T3 Code | `https://orange.tail1e65cd.ts.net/t3/` | [t3code.nix](modules/common/t3code.nix) |
| Samba | HDD の共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | Fabric サーバー | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale 出口ノード | 出口ノード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |
| 公開の経路 | nginx と Tailscale Serve | [web.nix](hosts/orange/services/web.nix) |

- ポート・パス・URL は [settings.nix](hosts/orange/settings.nix) にまとめています。
- 起動の順番は「HDD のマウント → 共有ディレクトリの準備 → 既存データの取り込み → アプリ」です（[storage.nix](hosts/orange/services/storage.nix)）。
- [local-backup](hosts/orange/services/local-backup.nix) がバックアップ、[health-monitor](hosts/orange/services/health-monitor.nix) が
  15 分ごとに異常を Discord へ通知、[smart-tests](hosts/orange/services/smart-tests.nix) がディスクの診断、
  [maintenance](hosts/orange/services/maintenance.nix) がログの掃除・TRIM・Nix ストアの保守を受け持ちます。
- 長いシェル処理は `.sh` のテンプレートに書き、`@名前@` を `fillTemplate`（[default.nix](hosts/orange/default.nix)）で
  置き換えて使います。テンプレートを直接実行しないでください。

## パッケージと入力の方針

- [pkgs/default.nix](pkgs/default.nix) に並べたパッケージは、設定から `pkgs.local.<名前>` で参照でき、
  `nix build .#<名前>` で単体ビルドもできます。パッチは対象パッケージのディレクトリに置きます。
- 更新の入口は `nix flake update` にそろえます。再現性のための revision と hash は `flake.lock` に残します。
- Umbriel と Noctalia は `cachix`、xddxdd のカーネルは `master` を追います。バージョン番号の固定タグは使いません。
- まだ `nix flake update` だけでは更新できないものがあります。Helium、xpad、Penpot MCP、LiveSync の各パッケージ、
  shadcn スキルの取得元、orange の Minecraft とその MOD は、バージョンやハッシュを手で管理しています。
- 非自由パッケージは全体で許可しています（`allowUnfree = true`）。
- `system.stateVersion` と `home.stateVersion` は互換性の基準なので、アップデートに合わせて変えません。
