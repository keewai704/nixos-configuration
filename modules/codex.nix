{
  config,
  lib,
  pkgs,
  ...
}:

let
  userName = "keewai";
  sharedMcpServers = config.home-manager.users.${userName}.programs.mcp.servers;

  toCodexMcpServer =
    name: server:
    let
      disabled = server.disabled or null;
      enabled = server.enabled or null;
      connectionSettings = lib.removeAttrs server [
        "disabled"
        "headers"
        "serverUrl"
        "type"
      ];
      httpHeaders = lib.optionalAttrs ((server.headers or { }) != { }) {
        http_headers = server.headers;
      };
      enabledSetting = lib.optionalAttrs (enabled == null && disabled != null) {
        enabled = !disabled;
      };
      toolApproval = lib.optionalAttrs (name == "cua-driver") {
        default_tools_approval_mode = "writes";
      };
      codexSettings = connectionSettings // httpHeaders // enabledSetting // toolApproval;
    in
    lib.filterAttrs (_: value: value != null && value != [ ] && value != { }) codexSettings;

  codexSystemConfig = (pkgs.formats.toml { }).generate "codex-config.toml" {
    model = "gpt-6-astra";
    model_context_window = 872000;
    model_reasoning_effort = "xhigh";
    plan_mode_reasoning_effort = "xhigh";
    features = {
      multi_agent = false;
      context_management = {
        experimental_mode = true;
      };
      token_budget.enabled = true;
      token_budget.use_history_notes_extension = true;
    };
    developer_instructions = ''
      既定はGPT-6 Astra、通常・Planともxhigh。sub-agentは使わず、設計から実装、検証、最終レビューまで自分で行う。別タスクや別エージェントへの送信で委譲を代用しない。

      コードと設定は人間が読み、レビューし、保守するものとして、必ず読みやすくする。意図が伝わる名前、素直な制御フロー、責務に合う構成を優先し、短さだけを目的とした圧縮や技巧的な省略を避ける。コメントは必要な判断理由や制約を説明する。

      依頼と会話から成果物・範囲・完了条件を判断し、必要な修正と検証まで継続する。監査・助言だけの依頼では別途指定された変更だけ実装する。通常の判断は既存の構成から決め、結果・範囲・権限が実質的に変わる不明点だけ確認し、独立した作業は進める。

      承認済みの工程は再確認しない。スキルは範囲や権限を広げず、ユーザーの明示指示をスキルの指針より優先する。スキルによる停止・追加確認にはSKILL.mdのリンクと短い引用を添え、明記された要件と自分の解釈を区別する。

      commitは依頼とリポジトリの規約に従う。push・公開・外部送信・破壊的操作は、その操作への明示指示または継続承認の範囲で行う。push先のremote・ブランチと既存コミットを含む送信範囲を調べ、未承認部分だけ確認する。force pushはしない。実装・ローカル適用・公開の成否は分けて報告する。

      指示・スキルは狭い発火条件、必要に応じた詳細の参照、明確な判断境界と完了条件で設計し、不要な一律手順を増やさない。スキルは単語への言及ではなく依頼された操作で選ぶ。Figma系はFigma連携が必要な場合に使い、figma-swiftuiはFigmaとSwiftUIの変換に限定する。一般的なiPad操作には使わない。google-docsはGoogle Docsの作成・編集・テンプレート適用・検証に使い、参照文書は必要な操作ごとに読む。テンプレート保持、データ保護、ツールの必須手順は保つ。

      実行環境・対象の確認は外部検索より先に行ってよい。OpenAIの最新・不確かな仕様が必要なら関連する公式文書の本文を確認し、無関係な移行手順は読まない。未変更の資料と合格済みの検証は再利用し、変更・失敗・未解決の懸念に応じて検証を広げる。配置、パッケージ所有権、適用手順は対象のAGENTS.mdに従う。

      結論と根拠を簡潔に示し、求められた説明は十分に行う。要件・品質・安全性・必要な検証を節約のために省かない。対応コマンドの出力は `rtk <command>` で絞り、正確な未加工出力が必要なら `rtk proxy <command>` を使う。
    '';
    mcp_servers = lib.mapAttrs toCodexMcpServer sharedMcpServers;
  };

in
{
  imports = [ ./codex-ponytail.nix ];

  environment.etc = {
    "codex/config.toml".source = codexSystemConfig;
  };
}
