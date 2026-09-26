{
  inputs,
  lib,
  pkgs,
  ...
}:
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

  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    [ -s "$settings" ] || run sh -c 'echo "{}" > "$1"' sh "$settings"
    tmp=$(mktemp)
    ${lib.getExe pkgs.jq} '.skipDangerousModePermissionPrompt = true' "$settings" > "$tmp"
    run sh -c 'cat "$1" > "$2"' sh "$tmp" "$settings"
    rm -f "$tmp"
  '';

  programs.codex = {
    enable = true;
    package = inputs.codex-cli.packages.${system}.default;
  };
}
