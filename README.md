# nixos-configuration

自宅サーバー `orange` とデスクトップPC `citrus`（ともに `x86_64-linux`）の NixOS 設定です。

OS・ハードウェア・システムサービスは **NixOS**、個人のアプリや設定は **Home Manager** で管理します。
作業ルール（検証・コミット・適用の手順）は [AGENTS.md](AGENTS.md) にあります。

## ディレクトリ構成

```text
.
├── flake.nix            入力（依存リポジトリ）、各ホストの構成、開発用シェル
├── hosts/orange/        ハードウェア、GPU、起動、settings.nix、services/ にサーバー機能
├── hosts/citrus/        デスクトップPCのハードウェア、GPU、起動、desktop/ にデスクトップ機能、installer/ にインストーラーISO
├── modules/common/      Nix、ネットワーク、ユーザー、Home Manager の接続
├── modules/tailnet-web/ nginx と Tailscale Serve の入口、T3 Code の公開経路（orange と citrus で共有）
├── home/keewai/common/  個人設定（シェル、Git、コーディングエージェント、T3 Code）
├── pkgs/                自作・改造パッケージとパッチ
├── skills/              Claude Code・Codex に配る個人スキル
└── secrets/             agenix で暗号化した秘密情報
```

1つの機能が複数のファイルを使う場合は、ディレクトリにまとめて `default.nix` を入口にします
（例：`home/keewai/common/shell/`、`hosts/orange/services/tv/`）。シェルスクリプトなどの素材も、
使う側の `.nix` と同じ場所に置きます。

### 読み込みの流れ

```text
flake.nix
├── nixosConfigurations.orange
│   ├── modules/common
│   │   └── home-manager.nix  →  home/keewai/common
│   └── hosts/orange
│       └── services/        default.nix がサーバー機能を明示的に読み込む
├── nixosConfigurations.citrus
│   ├── modules/common
│   └── hosts/citrus
│       ├── desktop/         Umbriel・Noctalia・日本語入力・フォント・壁紙
│       └── services/        GPU サービス（STT・PLaMo・Immich の機械学習）、Wake-on-LAN、Web 公開
└── nixosConfigurations.citrus-installer
    └── hosts/citrus/installer/  インストーラーISO（デスクトップ構成＋インストーラー）
```

## やりたいこと別の編集先

| やりたいこと | 編集するファイル |
| --- | --- |
| CLI ツールを追加 | [home/keewai/common/packages.nix](home/keewai/common/packages.nix) |
| シェル・エイリアス・プロンプト | [shell/](home/keewai/common/shell/default.nix)（`starship.toml` も同じ場所） |
| Git / GitHub CLI | [git.nix](home/keewai/common/git.nix) |
| Claude Code・Codex・スキル・MCP サーバー | [coding-agents/](home/keewai/common/coding-agents/default.nix)、[skills/](skills/) |
| T3 Code（nightly サーバー） | [t3code.nix](home/keewai/common/t3code.nix)、[pkgs/t3code](pkgs/t3code/)、[公開経路](modules/tailnet-web/t3code.nix) |
| orange のハードウェア・GPU・起動 | [hosts/orange/](hosts/orange/)、[graphics.nix](hosts/orange/graphics.nix) |
| orange のサービス・ポート・保存先 | [hosts/orange/services/](hosts/orange/services/)、[settings.nix](hosts/orange/settings.nix) |
| citrus のハードウェア・GPU・起動 | [hosts/citrus/](hosts/citrus/)、[graphics.nix](hosts/citrus/graphics.nix) |
| citrus のデスクトップ・日本語入力 | [desktop/](hosts/citrus/desktop/) |
| citrus のインストーラーISO | [installer/](hosts/citrus/installer/default.nix)、[.github/workflows/citrus-installer.yml](.github/workflows/citrus-installer.yml) |
| orange の USB チューナー・EDCB・KonomiTV | [tv/](hosts/orange/services/tv/)、[pkgs/](pkgs/) |

迷ったときは次の基準で置き場所を決めます。

- **ログイン、ドライバー、udev、PAM、デーモンなど OS との連携** → NixOS（`modules/` か `hosts/`）
- **自分だけが使うアプリや設定ファイル** → Home Manager（`home/keewai/`）
- **特定のマシンのハードウェアに依存するもの** → `hosts/<host>/`

## よく使うコマンド

```sh
nix flake update                                                  # 入力をまとめて更新（適用の前に毎回実行してコミット）
sudo systemd-run --scope --slice=nix.slice ionice -c 3 nixos-rebuild test --accept-flake-config --flake .#orange    # 一時的に適用して動作確認（再起動で戻る）
sudo systemd-run --scope --slice=nix.slice ionice -c 3 nixos-rebuild switch --accept-flake-config --flake .#orange  # 本適用（起動時の既定にもなる）
nix fmt                                                           # Nix ファイルを整形
nix develop                                                       # 言語サーバーや整形ツール入りのシェル
nix build --accept-flake-config .#<パッケージ名>                   # pkgs/ のパッケージを単体でビルド
```

適用前に `hostnamectl --static` と `/etc/hostname` の一致を確認し、
`nixos-rebuild` には確認した実行中のホスト名を指定します。
`hostnamectl` が使えない場合は `hostname` を代わりに使います。

`nix` は、`gh auth login --hostname github.com` で認証済みなら、実行時に GitHub CLI から
トークンを取得して GitHub 入力と GitHub API への直接アクセスに使います。認証情報がなければ
認証なしで実行します。トークンは Nix ストアやリポジトリに保存せず、API 用の一時認証ファイルは
コマンド終了時に削除します。既存の Nix 設定と他のホスト用の認証情報も引き継ぎます。

## バイナリキャッシュ

`flake.nix` の `nixConfig` と `modules/common/nix.nix` に、nix-community のキャッシュの URL と
署名鍵を書いています。`nixConfig` には import や計算式が使えないため、両方を手で同じ内容に保ちます。
Claude Code と Codex は `nixpkgs` をこの flake に合わせてビルドするため、上流のキャッシュとは
ストアパスが一致しません。どちらも配布バイナリを取得するだけなので、キャッシュは登録していません。

- 新しい設定を適用する前の最初のビルドでもキャッシュを使えるよう、`nixos-rebuild` と `nix build` には
  `--accept-flake-config` を付けます。初回の適用前に単体ビルドするときは
  `sudo systemd-run --scope --slice=nix.slice ionice -c 3 nix build --accept-flake-config --no-link .#<パッケージ>` を使います
  （信頼されていない利用者は、flake を受け入れても新しいキャッシュや鍵を追加できないため）。
- `accept-flake-config` を全体で有効にはしません。中身を確かめた flake のキャッシュ設定だけを受け入れます。
- `cache.nixos.org` はそのまま使います。
- citrus の CachyOS カーネル・ZFS は [nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel) のキャッシュ
  （`https://cache.lantian.pub/lantian`）、Proton-CachyOS は [Chaotic-Nyx](https://www.nyx.chaotic.cx/) のキャッシュ
  （`https://nyx-cache.chaotic.cx`）から取得します。URL と鍵は [flake.nix](flake.nix) の `nixConfig` にだけ書き、
  NixOS モジュールの側には書きません（pi.cachix.org と同じ扱いです）。
- キャッシュに載るのは、まったく同じストアパスのものだけです。自前のパッチを当てたパッケージなどは
  手元でビルドされます。署名の検証は無効にしません。

Nix デーモンと上記の適用コマンドは `nix.slice` にまとめ、CPU の競合時の優先度を下げ、メモリに2 GiBのソフト上限を設けています。
I/O はデーモン設定と `ionice -c 3` で idle クラスにし、読み取りと同期・直接書き込みの優先度を下げます。
バッファー経由の非同期書き戻しは、この優先度設定の対象外です（[Linux の仕様](https://man7.org/linux/man-pages/man2/ioprio_set.2.html)）。
Nix ストアの GC も同じ制御で動かします。
root のビルドはデーモンを経由しない場合があるため、`systemd-run` と `ionice` で同じ制御を適用します。
他の重い root のビルドにも `sudo systemd-run --scope --slice=nix.slice ionice -c 3 nix build …` を使います。

## コーディングエージェント

Claude Code・Codex・Pi は全ホストで Home Manager が導入し、どのシェルからでも使えます。
Pi は [pi.nix](https://github.com/lukasl-dev/pi.nix) の Home Manager モジュールで入れ、ビルド済みの成果物を
[pi.cachix.org](https://pi.cachix.org) から取得します。
`~/.claude` の設定やログイン情報は基本的に Nix で管理しません。例外として
[coding-agents/](home/keewai/common/coding-agents/default.nix) が次のものを配ります。

- **スキル**：[skills/](skills/) の全ディレクトリを `~/.claude/skills/` と `~/.agents/skills/` にリンクします。
  上流のスキル `yomiyasu`（[nanaism/yomiyasu](https://github.com/nanaism/yomiyasu)）と `imozuru`（[MaryCache/imozuru](https://github.com/MaryCache/imozuru)）は
  同名の flake 入力から同じ場所にリンクし、`nix flake update` で更新します。
  Pi は `~/.agents/skills/` を標準で読むため、同じスキルが使えます。
- **MCP サーバー**：`codingAgents.mcpServers.<名前>` に stdio の `{ command; args; env; }` か HTTP の `{ url; headersHelper; }` を書くと、
  適用時に `~/.claude.json` と `~/.codex/config.toml` へ書き込み、Pi には `~/.pi/agent/mcp.json` へ実行時に反映します。
  Pi の HTTP サーバーには、`headersHelper` が出力する `Authorization` ヘッダーだけを渡します。`headersHelper` は HTTP ヘッダーの JSON を出力するコマンドです。`~/.claude.json` では Nix から外したサーバーだけを消し、手で追加したサーバーはそのまま残します。
- **Web 検索**：[searxng.nix](home/keewai/common/searxng.nix) が nixpkgs の [SearXNG](https://github.com/searxng/searxng) を
  `127.0.0.1:8888` のユーザーサービスとして動かし、nixpkgs の `mcp-searxng` を `searxng` MCP サーバーとして登録します。
  Claude Code の `WebSearch` と Codex の組み込み `web_search` は無効にします。
  この回線で常にブロックまたはタイムアウトする DuckDuckGo・Google・Qwant は無効にしてあります。
- **ブラウザー操作**：[tinyfish/](home/keewai/common/tinyfish/default.nix) が [TinyFish](https://docs.tinyfish.ai/) の
  リモート MCP サーバーを `tinyfish` として登録します。API キーは `TINYFISH_API_KEY` か `~/.tinyfish/config.json`
  （`tinyfish auth login` と同じ形式）から適用時ではなく接続時に読み、Nix には保存しません。
  検索は SearXNG、ページの読み取りは TinyFish の `fetch_content`、クリックや入力が必要な操作だけ
  有料の `run_web_automation` を使うよう、[共通指示](home/keewai/common/coding-agents/shared-instructions.md)で振り分けます。
- **Pi の拡張機能**：[pi-blackhole](https://github.com/k0valik/pi-blackhole)（決定的なコンパクションと観察記憶）を
  同名の flake 入力のソースから `--extension` で読み込み、`nix flake update` で更新します。
- **Claude Code の共通指示**：[共通の UI・開発方針](home/keewai/common/coding-agents/shared-instructions.md)を
  `~/.claude/CLAUDE.md` に置きます。
- **Claude Code の共通設定**：`autoCompactWindow = 400000` と `env.CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT = "1"` を適用時に設定します。
- **Codex の共通指示**：[codex-instructions.md](home/keewai/common/coding-agents/codex-instructions.md) と共通の UI・開発方針を
  `~/.codex/config.toml` の `developer_instructions` に設定します。
  [OpenCode の方針](https://github.com/anomalyco/opencode/blob/dev/AGENTS.md)を参考にした実装・検証の指示が、
  全プロジェクトの新しい Codex セッションで組み込み指示に追加されます。
  プロジェクト固有の `AGENTS.md` の規約を尊重し、手動の設定やログイン情報は保持します。

| スキル | 用途 |
| --- | --- |
| `ponytail` | 実装を単純に保つ（KISS / YAGNI） |
| `superpowers` | 設計・計画・デバッグ・レビューなど大きめの作業の進め方 |
| `add-nix-skill` | このリポジトリでスキルを追加・修正するとき |
| `faster-whisper` | 音声・動画を RE-USE でノイズ除去してから GPU で文字起こし（citrus のみ） |
| `yomiyasu` | 成果物の日本語文書を推敲（共通指示で文書出力時に使用、通常の応答では不使用） |
| `imozuru` | 知らない分野を原文まで芋づる式に調べて保存 |

リポジトリ専用の検証手順は [.agents/skills/nixos-validation](.agents/skills/nixos-validation/SKILL.md) にあります。

### T3 Code nightly

[T3 Code](https://github.com/pingdotgg/t3code) は、orange と citrus で Home Manager の常駐サーバーとして動きます。
公開経路と接続先は両ホスト共通の [modules/tailnet-web/t3code.nix](modules/tailnet-web/t3code.nix)、
ユーザーサービスは [t3code.nix](home/keewai/common/t3code.nix) が管理します。
公式の nightly AppImage に含まれる CLI を `t3 serve` で実行し、グラフィカルセッションには依存しません。
リリース情報は、上流が更新する AUR の `.SRCINFO` を `t3code-nightly` 入力で固定します。
バージョンと AppImage の SHA256 を読み取り、更新は `nix flake update` と通常の適用手順で行います。
GitHub のダウンロード数は更新判定に含めません。
アプリ内の自動更新は無効です。

- Web 画面は orange では `https://orange.tail1e65cd.ts.net/t3/`、citrus では `https://citrus.tail1e65cd.ts.net/t3/` です。
  Tailscale Serve HTTPS 443 → `127.0.0.1:8000` の nginx → `127.0.0.1:3773` のサーバーで配信し、管理画面用の API と WebSocket も同じ HTTPS 入口を通ります。
  `/t3/` 用に Web 画面のルーター、ペアリング成功後の遷移、静的ファイル参照、PWA manifest をパッケージ内で補正します。
  HTTP MCP が返すスレッドリンクも、orange の HTTPS URL では `/t3/` を使います。
  公開元の URL は [settings.nix](hosts/orange/settings.nix) の `tailnetOrigin` から `services.t3code.webOrigin` を通じてパッケージへ渡します。
  ルートは Immich です。
  ゲスト共有リンクは、上流の T3 Connect の専用ホストを使います。
- 起動時にサービスが始まり、既存の `~/.t3` のペアリング、プロジェクト、会話履歴を使います。
  同じ `~/.t3` に対してデスクトップ版や別の `t3 serve` を同時起動しないでください。
- 端末のペアリングは **Settings → Sharing & access** または
  `t3 auth pairing create --base-url https://orange.tail1e65cd.ts.net` を使います。
  `t3 pair --tailscale` は共通の Serve 設定を変更するため使いません。
  ペアリングのリンクは認証情報なので、ほかの人に見せないでください。
- Claude は Home Manager の実行ファイルと通常の `~/.claude` のログインを使います。必要なら
  `claude auth login` のあと、T3 Code でプロバイダーを再検出します。
- GitHub は既存の `gh` のログインを使います。`gh auth status` で確かめ、必要なら `gh auth login` のあと
  **Settings → Source Control → Rescan** を選びます。トークンを Nix にコピーすることはありません。
- T3 Code は利用者の権限でコマンドを実行できます。
  tailnet 内だけの公開でも、隔離された環境になるわけではありません。

## citrus（デスクトップ）

AMD Ryzen 7 9800X3D・GeForce RTX 5070 Ti・M.2 2TB のデスクトップPCです。
カーネルは [nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel) が上流 CachyOS のパッチと設定でビルドした
`linuxPackages-cachyos-latest`（EEVDF・GCC・非LTO）と、CachyOS パッチ適用済みの ZFS を使います。
カーネルと ZFS は同 flake のバイナリキャッシュから全出力（out・dev・modules）ごと取得できるため、
NVIDIA モジュールのビルドや initrd の生成でカーネルを再ビルドしません。
NVIDIA ドライバーは nixpkgs より新しい 620.70.06（オープンカーネルモジュール）を
[graphics.nix](hosts/citrus/graphics.nix) の `nvidiaPackages.mkDriver` でバージョンとハッシュごと固定します。
`nix flake update` では更新されないため、更新するときはこの定義を書き換えます。
このモジュールだけはキャッシュに存在しないためカーネル更新のたびにローカルビルドされます。

デスクトップは Umbriel（コンポジター）+ Noctalia v5（シェル）+ Noctalia Greeter（ログイン画面）で、
いずれも nixpkgs と Home Manager のパッケージ・モジュールから入れます。
Noctalia のテーマ・壁紙・アプリテンプレートの既定値は [desktop/](hosts/citrus/desktop/) が配り、
設定GUIでの変更は Noctalia が状態ディレクトリに保存するため、再適用後も手元の変更が保持されます。
`~/.config/umbriel/config.toml` は [desktop/](hosts/citrus/desktop/) が Home Manager で配り、Umbriel の既定設定に Noctalia のテーマ（`noctalia.toml`）とモニターのモード指定を重ねます。
フォーカスはポインターに追従し、非アクティブなウィンドウは半透明になって背景のぼかしと [glass.glsl](hosts/citrus/desktop/glass.glsl) の光沢が掛かります。
外部モニターの輝度は ddcutil 経由で Noctalia から操作し、Alt+[ で下げ、Alt+] で上げます。
Mod+V で Noctalia のクリップボード履歴を開きます。

OpenAI 互換の文字起こし API を `https://citrus.tail1e65cd.ts.net/stt/v1` で提供します（[stt-server/](hosts/citrus/services/stt-server/)）。
RE-USE でノイズ除去してから Whisper large-v3 で文字起こしし、接続元は [settings.nix](hosts/citrus/settings.nix) の端末に限ります。

orange の Immich の機械学習は citrus の GPU で実行します。
Immich は orange の [citrus-wake](hosts/orange/services/citrus-wake/) に推論を依頼し、citrus-wake が
[immich-machine-learning.nix](hosts/citrus/services/immich-machine-learning.nix) へ中継します。
citrus が応答しないときは起こさずに 503 を返します。
機械学習のキューは普段は止めておき、[immich-ml-schedule](hosts/orange/services/immich-ml-schedule/) が
平日 9 時に citrus を Wake-on-LAN で起こしてキューを流し、自分で起こした場合は終わったらサスペンドさせます。

日本語入力は fcitx5 と [Meltype](https://github.com/aster-void/nix-meltype) です。
Discord は [Nixcord](https://github.com/4evy/nixcord) 経由の Equicord 入りで導入し、Bitwarden はデスクトップ版を入れます。
ブラウザーは Helium（Widevine 対応）を [helium-flake](https://github.com/amaanq/helium-flake) から、
Steam は [Millennium](https://docs.steambrew.app/) 入りで、[steam.nix](hosts/citrus/desktop/steam.nix) がテーマ（Material Theme）とプラグインを flake 入力から配ります。プラグインは `millennium-plugin-` で始まる入力を足すと導入され、`nix flake update` で更新します。テーマの色は Noctalia がテーマの配色ファイル（`css/main/colors/matugen.css`）へ、フォントは Millennium の Quick CSS（`~/.config/millennium/quick.css`）へ書き出し、パレットを変えると起動中の Steam にもすぐ反映されます。Proton-CachyOS を互換ツールとして導入し、`ntsync` モジュールと GameMode を有効にします。GameMode を使うゲームには起動オプション `gamemoderun %command%` を設定します。GameMode の間は `gpu-workloads.target` の GPU サービス（Immich の機械学習、PLaMo、STT）を止めて GPU を空け、終了すると起動し直します。Spotify と kitty も入っています。

M.2 は GPT の3パーティション構成です。[hardware-configuration.nix](hosts/citrus/hardware-configuration.nix) が
FAT32 の ESP（4GiB、ラベル `CITRUS-ESP`、`/boot`）、ZFS ルート（残り全部、プール `citrus`、データセット `root`）、
XFS のデータ領域（1TiB、ラベル `Data`、`/mnt/data`）をマウントします。

### インストーラーISO

[installer/default.nix](hosts/citrus/installer/default.nix) は citrus のデスクトップ構成（カーネル・ZFS・NVIDIA・
Umbriel・Noctalia・fcitx5/Meltype・コーディングエージェント込み）に NixOS インストーラーの基本構成を合わせた
ライブISOです。起動すると keewai として Umbriel セッションに自動ログインし（パスワードは `citrus`）、
kitty から Claude Code・Codex・Pi がそのまま使えます。インストール作業はこのライブ環境から
`nixos-install --flake` で行えます。Steam と同梱チャンネルだけは容量削減のため無効化しています。

ビルドは [GitHub Actions](.github/workflows/citrus-installer.yml)（手動実行）で行い、完成したISOは
artifact から取得します。カーネル・ZFS は lantian キャッシュから、NVIDIA モジュールは
runner 上でビルドされます。

## orange（サーバー）

外部からの Web アクセスは **Tailscale Serve（HTTPS 443）→ nginx（127.0.0.1:8000）→ 各アプリ（ループバック）** の一本道です。
アプリを LAN やすべてのアドレスに向けて公開しません。詳しい規則は [AGENTS.md](AGENTS.md#orange-web-exposure) にあります。

| サービス | URL・用途 | 設定 |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | [immich/](hosts/orange/services/immich/) |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | [vaultwarden/](hosts/orange/services/vaultwarden/) |
| T3 Code | `https://orange.tail1e65cd.ts.net/t3/` | [t3code.nix](hosts/orange/services/t3code.nix) |
| KonomiTV | `https://orange.tail1e65cd.ts.net/tv/` | [tv/](hosts/orange/services/tv/) |
| citrus の起動 | `https://orange.tail1e65cd.ts.net/wake/citrus`（muse からのみ） | [citrus-wake/](hosts/orange/services/citrus-wake/) |
| Samba | HDD の共有 | [samba.nix](hosts/orange/services/samba.nix) |
| Minecraft | Fabric サーバー | [minecraft.nix](hosts/orange/services/minecraft.nix) |
| Tailscale 出口ノード | 出口ノード | [tailscale-exit-node.nix](hosts/orange/services/tailscale-exit-node.nix) |
| 公開の経路 | nginx と Tailscale Serve | [modules/tailnet-web/](modules/tailnet-web/) |

- 複数の機能で共有するポート・パス・URL は [settings.nix](hosts/orange/settings.nix) にまとめています。
  テレビ内部の接続先と保存先は [tv/settings.nix](hosts/orange/services/tv/settings.nix) で管理します。
- サービスの追加は [services/default.nix](hosts/orange/services/default.nix) に明示し、公開ルートは各サービスの設定に置きます。
  プロキシは [proxy.nix](modules/tailnet-web/proxy.nix) を使い、ホスト・HTTPS・クライアントIPの転送を揃えます。
- Intel GPU と QSV のドライバーは [graphics.nix](hosts/orange/graphics.nix) が管理し、Immich とテレビから利用します。
- 起動の順番は「HDD のマウント → 共有ディレクトリの準備 → 既存データの取り込み → アプリ」です（[storage.nix](hosts/orange/services/storage.nix)）。
- [local-backup](hosts/orange/services/local-backup/) がバックアップ、[health-monitor](hosts/orange/services/health-monitor/) が
  15 分ごとに異常を Discord へ通知、[smart-tests](hosts/orange/services/smart-tests.nix) がディスクの診断、
  [maintenance](hosts/orange/services/maintenance.nix) がログの掃除・TRIM・Nix ストアの保守を受け持ちます。
  Minecraft は JustEnoughBackups のスナップショットから、サーバーを停止せずに保存します。
  Minecraft と Vaultwarden は、片方のバックアップに失敗しても、もう片方の保存を試みます。
  新しい世代を保存できた対象だけ、14日以上前の世代を削除します。保存に失敗した対象の履歴は保持します。
  一時アーカイブは終了時に削除し、強制終了で残った一時アーカイブと作業ディレクトリは次回実行時に回収します。
- 各サービスが `orange.healthMonitor.units` と `loopbackPorts` に監視対象を追加します。
  T3 Code は `userUnits` で `keewai` のユーザーサービスとして、PC/SC は `pcscd.socket` の待受として確認します。
  Web 監視は Immich、Vaultwarden、T3 Code、KonomiTV の応答を確認します。
- 長いシェル処理は機能ディレクトリ内の `.sh` テンプレートに書き、`@名前@` を `fillTemplate`（[services/default.nix](hosts/orange/services/default.nix)）で
  置き換えて使います。テンプレートを直接実行しないでください。

### テレビ

構成の入口は [tv/default.nix](hosts/orange/services/tv/default.nix) です。
[edcb.nix](hosts/orange/services/tv/edcb.nix) が番組表と録画予約、
[recording/](hosts/orange/services/tv/recording/default.nix) が録画後の変換、
[konomitv.nix](hosts/orange/services/tv/konomitv.nix) が視聴画面と公開経路を管理します。

Sony CECH-ZD1 J 2台を、機器ごとの `torne-receiver` → mirakc の順に接続し、KonomiTV のライブ受信と
BonDriver_LinuxMirakc → xtne6f 版 EDCB（Linux ネイティブ）の録画で共有します。
KonomiTV は EDCB バックエンドの `always_receive_tv_from_mirakurun` を有効にし、番組情報・録画予約は EDCB、放送波は mirakc から取得します。
Twitter 連携は利用せず、そのためのサーバー側ブラウザは導入していません。
mirakc は [settings.nix](hosts/orange/services/tv/settings.nix) で指定したループバックポートの内部接続だけで利用します。同じ放送波は共有し、異なる2つの放送波を同時受信できます。チューナー不足の場合は EDCB の録画を優先します。
内蔵 B-CAS スロットは専用 IFD と標準 pcscd で公開し、ライブは aribb25、EDCB は B25Decoder で復号します。映像は Intel QSV で変換します。
8TB HDD 上の録画専用ディレクトリは `/srv/storage/KonomiTV/Recordings`、キャプチャは `/srv/storage/KonomiTV/Captures`、設定・番組表は
`/var/lib/edcb` と `/var/lib/konomitv` に保存します。

再視聴を速くするため、視聴終了後も配信を最大120秒保持します。
画面で240pを選ぶと、ライブ視聴・録画再生とも H.264 で配信し、端末との互換性を確保します。
携帯回線の低遅延モードは初回適用時に有効化し、その後の手動変更は維持します。
専用ドライバーは libusb で直接制御し、初期化と校正を機器ごとの常駐プロセスで保持します。機器とUSB接続位置の対応は [tuners.nix](hosts/orange/services/tv/tuners.nix)、放送局は [channels.nix](hosts/orange/services/tv/channels.nix) で管理します。レジスター書き込みは USB コマンドへまとめ、受信に成功した周波数の TMCC を再利用します。フルセグと TMCC のロックに失敗した場合は自動探索へ戻し、放送局IDを指定した受信では、PAT の整合性とIDを確認してから配信します。受信要求は機器ごとに排他制御し、切断済みの要求は選局せず破棄します。切断時にはUSB転送と待機を解除します。
[px4_drv本家](https://github.com/nns779/px4_drv) の転送・バッファ設計を参考に、8本の非同期USB転送と受信バッファでUSB受信とアプリへの送信を分離しています。
直接利用するLinuxネイティブのBonDriver2は `/var/lib/edcb/lib/BonDriver_Torne0.so` と `BonDriver_Torne1.so` です。`CreateBonDriver` と EDCB の `CreateBonStruct` を公開し、選局、信号レベル、TS取得・待機・消去、開閉に対応します。同名の `.so.ini` で制御ソケットと放送局一覧を指定します。設定を省く場合は1台目のソケットとUHF 13〜62chを使います。
自動録画では `BonDriver_LinuxMirakc.so` の2枠を利用し、KonomiTVとの共有を維持します。直接BonDriverとmirakcは同一機器を同時には占有できません。直接利用するアプリは `tv` グループで実行してください。`keewai` のグループ追加を既存ログインへ反映するには再ログインが必要です。
NHK総合の京都・神戸とサンテレビ2は、EDCB の表示・EPG取得・検索を無効にし、KonomiTV の一覧にも反映します。

今後の録画は EDCB の `PostRecEnd.lua` からキューへ登録し、[録画処理](hosts/orange/services/tv/recording/default.nix)が AmatsukazeCLI と QSVEncC で映像を H.265 に変換し、tsreplace で元 TS の映像だけを置換します。
音声・字幕・番組情報・データ放送などの非映像パケットを PID ごとの件数と SHA256 で比較し、PMT の非映像情報、映像の全体デコードとフレーム時刻も検証します。
インターレース映像は CPU 版 KFM で24p・30p・60pの区間を判別し、逆テレシネとインターレース解除を切り替えた可変フレームレートで出力します。プログレッシブ映像はインターレース解除を省きます。変換後の各フレームの時刻が TS への置換で変わっていないことも確認します。
Amatsukaze の入力解析では末尾 PES の境界で数フレームの差が出るため、末尾3入力フレーム分の区間は PES 解析差を許容し、終了時刻の差を完了 JSON の `source_tail_difference_ms` に記録します。それより前の時刻欠落と、変換済み映像の TS 置換時のフレーム欠落は拒否します。
初回に局ロゴを自動検出・生成し、サービスIDと解像度ごとに `/var/lib/tv-recording/logos` へ保存します。以後はそのロゴを利用して CM解析とロゴ消しを行います。ロゴを生成できない初回録画は元 TS を残して失敗扱いにします。登録済みロゴの自動再検出は行わず、ロゴが表示されない区間はロゴを消さずに処理を続けます。
ロゴは作業ディレクトリ内で生成し、完成ファイルをキャッシュ側の一時ファイルへコピーしてから公開します。
CM は残し、解析結果を録画と同じ場所の `<録画名>.chapter.txt` に保存します。解析で区切りが見つからない場合も、先頭に「本編」チャプターを作成します。映像や音声の形式変更により複数ファイルへ分割される場合は、元 TS を残します。変換とロゴ生成の作業データは `/var/cache/tv-recording/work` に置きます。
中断で残った変換用の作業ディレクトリは、ワーカーの次回起動時に回収します。
映像の符号化方式を示す PMT と、必要な場合の PCR 配置は更新します。検証成功後に同じファイル名へ置換し、元 TS を削除します。
失敗時は元 TS を残し、ジョブを `/var/lib/tv-recording/failed`、ログを `/var/log/tv-recording` に保存します。既存録画の一括変換は行いません。

torne_drv・mirakc・mirakc-arib・BonDriver・EDCB・B25Decoder・tsreplace・Amatsukaze・KonomiTV と配布バイナリは [flake.nix](flake.nix) の入力で管理します。
mirakc は上流の `release` ブランチを追います。
KonomiTV は `master`、対応するバイナリは上流の nightly 配布を追います。
Amatsukaze は公式 CI の master ビルドを `amatsukaze-artifacts` 入力から選びます。
配布物の情報と取得したアーカイブはシステム世代で保持し、GC や CI の保存期限後の再評価に備えます。
更新は `nix flake update` と通常の Orange への適用で行い、ソースの revision と配布物の hash は `flake.lock` に残します。
Rust と Python の依存は取得元のロックから構築します。専用ドライバーは GPL-2.0 の torne_drv の中核を基に C で実装し、coax の実行・ビルド依存はありません。

## パッケージと入力の方針

- [pkgs/default.nix](pkgs/default.nix) に並べたパッケージは、設定から `pkgs.local.<名前>` で参照でき、
  `nix build .#<名前>` で単体ビルドもできます。パッチは対象パッケージのディレクトリに置きます。
- 更新の入口は `nix flake update` にそろえます。再現性のための revision と hash は `flake.lock` に残します。
- orange の Minecraft とその MOD は、バージョンやハッシュを手で管理しているため、
  `nix flake update` だけでは更新できません。
- 非自由パッケージは全体で許可しています（`allowUnfree = true`）。
- `system.stateVersion` と `home.stateVersion` は互換性の基準なので、アップデートに合わせて変えません。
