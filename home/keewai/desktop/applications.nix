{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  agentInstructions = ''
    Always write your responses to the user in Japanese, even when instructions, code, or tool output are in another language. Keep code, commands, identifiers, and file contents in their original language.
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
