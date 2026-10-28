{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.codingAgents;
  skillRoot = ../../../../skills;
  sharedInstructions = builtins.readFile ./shared-instructions.md;

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

  syncConfig = pkgs.writers.writePython3 "sync-coding-agent-config" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./sync-config.py);
in
{
  imports = [ ./shadcn.nix ];

  options.codingAgents = {
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Skill directories linked into Claude Code.";
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
      description = "Stdio MCP servers registered in Claude Code user configuration.";
    };
  };

  config = {
    programs.codex = {
      enable = true;
      mutableSettings = true;
      package = inputs.codex.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings.developer_instructions =
        builtins.readFile ./codex-instructions.md + "\n" + sharedInstructions;
    };

    programs.claude-code = {
      enable = true;
      mutableSettings = true;
      package = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings = {
        autoCompactWindow = 400000;
        env.CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT = "1";
      };
    };

    codingAgents.skills = lib.genAttrs (builtins.attrNames (builtins.readDir skillRoot)) (
      name: skillRoot + "/${name}"
    );

    home.file = skillLinks // {
      ".claude/CLAUDE.md".text = sharedInstructions;
    };

    home.activation.codingAgentConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${syncConfig} ${mcpServers}
    '';
  };
}
