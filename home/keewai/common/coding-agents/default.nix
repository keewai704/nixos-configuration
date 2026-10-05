{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.codingAgents;
  skillRoot = ../../../../skills;

  skillLinks = lib.concatMapAttrs (name: source: {
    ".claude/skills/${name}" = {
      inherit source;
      force = true;
    };
    ".agents/skills/${name}" = {
      inherit source;
      force = true;
    };
  }) cfg.skills;

  mcpServers = pkgs.writeText "coding-agent-mcp-servers.json" (builtins.toJSON cfg.mcpServers);

  syncMcp = pkgs.writers.writePython3 "sync-coding-agent-mcp" {
    libraries = [ pkgs.python3Packages.tomlkit ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./sync-mcp.py);
in
{
  options.codingAgents = {
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Skill directories linked into Claude Code and Codex.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            command = lib.mkOption { type = lib.types.str; };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
          };
        }
      );
      default = { };
      description = "Stdio MCP servers registered in Claude Code and Codex user configuration.";
    };
  };

  config = {
    codingAgents.skills = lib.genAttrs (builtins.attrNames (builtins.readDir skillRoot)) (
      name: skillRoot + "/${name}"
    );

    home.file = skillLinks;

    home.activation.codingAgentMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${syncMcp} ${mcpServers}
    '';
  };
}
