{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  agentInstructions = ''
    Always write your responses to the user in Japanese, even when instructions, code, or tool output are in another language. Keep code, commands, identifiers, and file contents in their original language.

    When delegating to a subagent or child task, use only these Codex model and reasoning effort pairs, set explicitly through T3 Code's delegate_task (providerInstanceId codex, reasoningEffort option), and choose one per task instead of reusing one setting: gpt-6-luna with max for searches, lookups, and mechanical edits; gpt-6.1-sol with medium for routine implementation, tests, and summaries; gpt-6-astra with xhigh for hard design, debugging, or critical review. Do not use native subagent tools or other models for delegation. Honor any model or effort the user specifies.
  '';
in
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.moonlight-qt
    pkgs.pavucontrol
    (pkgs.callPackage ../../../pkgs/t3code {
      release = inputs.t3code-release;
      claude-code = inputs.claude-code.packages.${system}.default;
      codex = inputs.codex-cli.packages.${system}.default;
    })
  ];

  home.file.".claude/CLAUDE.md".text = agentInstructions;
  home.file.".codex/AGENTS.md".text = agentInstructions;
}
