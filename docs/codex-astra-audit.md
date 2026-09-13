# GPT-6 Astra 向け指示監査と改善

監査・改善日: 2026-09-13。実行ホストは `citrus-vm`。
Eric Provencher の
[Rethinking skills and prompts for GPT-6 Astra](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
と[公式Astraガイド](https://developers.openai.com/api/docs/guides/latest-model)を
踏まえ、指示の責任範囲、発火条件、判断の境界、完了条件を整理した。

初回の設定変更は `4ef46e0`。通常・PlanをAstra / xhighに揃え、
sub-agentを無効化し、Luna自動委譲スキルの配布を止めた。
続く改善では、以下のように内容を分けた。

## 指示の置き場所

| 内容 | 所有する場所 | 改善した点 |
| --- | --- | --- |
| ファイル配置・パッケージ所有権 | [AGENTS.md](../AGENTS.md) | READMEは配置判断時、package-auditは所有権変更時に参照する |
| 実行ホスト・リモート境界 | AGENTS.md | 同じ環境で確認済みのホスト情報を再利用し、環境が変われば再確認する |
| 検証・commit・NixOS適用 | AGENTS.md | 変更種別の表で一元化し、VMのCitrus継承を明示する |
| コマンドの使用例 | [development.md](development.md) | AGENTSの方針を参照する実行ガイドとし、重複する完了条件をなくす |
| モデル・自律的な完遂・確認条件 | [Codex追加指示](../hosts/citrus/codex.nix) | 全プロジェクト共通の `developer_instructions` として定義する |
| push・公開・外部送信 | Codex追加指示 | 操作と送信範囲を含む明示指示・継続承認を使い、同じ承認は再確認しない |
| スキル選択と参照順序 | Codex追加指示 | 単語一致で発火させず、必要な操作に応じて参照を読む |
| MCP固有の構成と確認 | [add-nix-mcp](../skills/add-nix-mcp/SKILL.md) | 固定入力、資格情報、生成設定、smoke checkを残して共通工程をAGENTSへ集約する |
| 個人スキル固有の作成と配布確認 | [add-nix-skill](../skills/add-nix-skill/SKILL.md) | validator、配布先、発火・非発火の確認を残して共通工程をAGENTSへ集約する |
| コード簡潔化の具体的判断 | [Ponytail](../skills/ponytail/SKILL.md) | hookは短い参照案内だけにし、本文はcoding時に読む |

Home Managerの配置・所有権の詳細はこのNixOSリポジトリ固有なので、
全タスクに入る追加指示から外した。全体指示にこのリポジトリだけのcommitや
適用義務を持ち込まず、他のリポジトリではその場所の規約に従う。

## 具体的な振る舞い

- **完遂:** 実装依頼は必要な修正と検証まで継続する。監査や助言だけの依頼は、
  別途指定された変更を除いて調査・提案を成果物とする。
- **確認:** 結果、範囲、権限が実質的に変わる不明点だけ確認し、独立した作業は進める。
  スキルの手順を追加権限と解釈しない。
- **Git:** このリポジトリではtask commitを必須とするが、pushは別の承認範囲。
  送信する既存コミットを含めて承認済みなら再確認しない。公開だけ失敗した場合も
  完了済みの実装・適用と分けて報告する。
- **ホスト:** MCP・スキルの適用を `citrus` の名前に固定しない。
  `citrus-vm` で共有Codex設定を変えた場合もローカルの適用ゲートを実行する。
- **検証:** `nix flake check` に含まれる評価を毎回 `--no-build` で重複させない。
  未変更入力の合格結果を再利用する。実システムの `test → health → switch → health`
  は異なる状態の確認なので維持する。
- **Ponytail:** 起動hookが本文全体を常時投入する方式を止めた。active levelと
  `/etc/codex/skills/ponytail/SKILL.md` への案内を注入する。
  lite/full/ultra、off、defaultの制御を保持し、SubagentStart hookは登録しない。

ホストの一致確認、無関係な変更の保護、秘密情報をNix storeへ入れない規則、
Orangeの443/loopback構成、実機操作の校正は維持した。短縮のために、
承認境界、必要な検証、テンプレート保持、ツール固有の必須手順は削除していない。

## 外部スキルの補正と限界

Figma系スキルはFigmaの操作・連携が実際に必要な場合に限り、
`figma-swiftui` はFigmaとSwiftUIの変換に限定する。
一般的なiPad操作はFigmaスキルを起動する理由にならない。
Google Docsは対象の作成・編集・テンプレート適用・検証のときに使い、
内部の参照文書を操作に応じて読む。環境や対象の確認は公式検索より先に行える。

これはNix管理の追加指示によるルーティングと読み込み方の補正である。
外部プラグインのdescription原文そのものは短縮していない。
確認した[公式設定リファレンス](https://learn.chatgpt.com/docs/config-file/config-reference)は
`skills.config` にパスと有効・無効の設定を示すが、descriptionの上書きは示していない。
既存機能を失う無効化、競合するコピー、更新で消えるキャッシュ編集は採用しなかった。
したがって外部カタログの文字数削減は配布側の更新が必要で、削減済みとは扱わない。

## 確認方法

変更した個人スキルはbundled validator、リンク確認、以下のシナリオの手動レビューで
確認する。別モデルによる評価や料金・速度の比較実験は行わない。

| 代表的な依頼 | 期待する判断 |
| --- | --- |
| READMEの誤字修正 | 対象箇所を直して文書確認・commit。全体構成の再読やNixOS適用は不要 |
| VM上のCodex設定変更 | AGENTSに従いCitrus/VMをローカルbuildし、VMだけtest・health・switch・health |
| Orange専用の宣言変更 | Orangeをローカル検証・build・commitし、VMへ適用せずリモート操作もしない |
| 個人スキル更新 | creatorとNix固有の配布確認を使い、共通ゲートはAGENTSから一度だけ適用 |
| iPadのスクリーンショット | USB操作スキルを選び、FigmaやPonytailを起動しない |
| 大きな調査で行き詰まる | 自分で継続し、sub-agentを起動しない |
| 承認済みのbranchをpush | 実際の送信範囲を確認し、承認済みなら再度質問しない |

[checks/ponytail-hooks.cjs](../checks/ponytail-hooks.cjs) は実行する回帰確認で、
隔離した一時state/configを使ってpackaged hookのJSON出力、短いcontext、
モード切替、通常プロンプトでの無出力、off、次セッションのdefaultを確認する。
Nix変更の静的検査、flake check、影響ホストのbuildとローカル適用はAGENTSのゲートに従う。
