{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  agentInstructions = ''
    Always write your responses to the user in Japanese, even when instructions, code, or tool output are in another language. Keep code, commands, identifiers, and file contents in their original language.

    When delegating to a subagent or child task, choose the model and reasoning effort for each task instead of inheriting or reusing one setting. Check the live catalog first (for example T3 Code's orchestrator_capabilities) and set both explicitly wherever the tool supports them. Match the task: a small, fast model with low effort for searches, lookups, and mechanical edits; a mid-tier model with medium effort for routine implementation, tests, and summaries; the strongest model with high effort only for hard design, debugging, or critical review. Use extra-high or higher effort only when the user asks or a lower setting has demonstrably failed. Honor any model or effort the user specifies.
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
