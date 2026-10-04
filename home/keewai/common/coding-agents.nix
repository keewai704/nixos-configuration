{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  claudeCode = inputs.claude-code.packages.${system}.default;
  serena = lib.getExe inputs.serena.packages.${system}.default;
  serenaArgs = context: [
    "start-mcp-server"
    "--context=${context}"
    "--project-from-cwd"
    "--open-web-dashboard=False"
  ];
  gitCompletion = ''
    # Finishing changes

    In every Git repository and directory, finish each change request by committing the work,
    merging it into `main`, and pushing `main` to its remote. Work done on another branch or
    worktree is not finished until it is merged into `main` and `main` is pushed; do not stop at
    an unmerged branch, a local-only commit, or a pull request. This is standing authorization for
    those commits, merges, and pushes to `main`. Force pushes, history rewrites, and other remote
    operations still need explicit approval. If a conflict, failing check, or rejected push blocks
    this, report the blocker.
  '';
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
    enableMcpIntegration = true;
    mcpServers.serena = {
      type = "stdio";
      command = serena;
      args = serenaArgs "claude-code";
    };
    context = gitCompletion;
  };

  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    [ -s "$settings" ] || run sh -c 'echo "{}" > "$1"' sh "$settings"
    tmp=$(mktemp)
    ${lib.getExe pkgs.jq} '.skipDangerousModePermissionPrompt = true | .remoteControlAtStartup = true | .awaySummaryEnabled = false' "$settings" > "$tmp"
    run sh -c 'cat "$1" > "$2"' sh "$tmp" "$settings"
    rm -f "$tmp"
  '';

  programs.mcp = {
    enable = true;
    servers.context7.command = lib.getExe pkgs.context7-mcp;
  };
}
