{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  claudeCode = inputs.claude-code.packages.${system}.default;
in
{
  programs.claude-code = {
    enable = true;
    package = pkgs.symlinkJoin {
      pname = "claude-code";
      inherit (claudeCode) version meta;
      paths = [ claudeCode ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/claude \
          --set-default CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION false \
          --set-default CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT 1 \
          --set-default ENABLE_CLAUDEAI_MCP_SERVERS false
      '';
    };
    enableMcpIntegration = false;
  };

  programs.codex = {
    enable = true;
    package = inputs.codex-cli.packages.${system}.default;
  };
}
