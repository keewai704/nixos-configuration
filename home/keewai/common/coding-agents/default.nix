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

  isHttp = server: server.url != null;

  claudeMcpServers = lib.mapAttrs (
    _: server:
    if isHttp server then
      {
        type = "http";
        inherit (server) url;
      }
      // lib.optionalAttrs (server.headersHelper != null) { inherit (server) headersHelper; }
    else
      {
        type = "stdio";
        inherit (server) command args env;
      }
  ) cfg.mcpServers;

  codexMcpServers = lib.mapAttrs (
    _: server:
    if isHttp server then
      {
        inherit (server) url;
      }
      // lib.optionalAttrs (server.headersHelper != null) { http_headers_helper = server.headersHelper; }
    else
      {
        inherit (server) command args env;
      }
  ) cfg.mcpServers;

  mcpServers = pkgs.writeText "coding-agent-mcp-servers.json" (builtins.toJSON claudeMcpServers);

  syncConfig = pkgs.writers.writePython3 "sync-coding-agent-config" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./sync-config.py);
in
{
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
            command = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            headersHelper = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Command that prints a JSON object of HTTP headers for an HTTP server.";
            };
          };
        }
      );
      default = { };
      description = "Stdio or HTTP MCP servers registered in Claude Code and Codex user configuration.";
    };
  };

  config = {
    assertions = lib.mapAttrsToList (name: server: {
      assertion = (server.command == null) != (server.url == null);
      message = "codingAgents.mcpServers.${name} needs exactly one of command or url.";
    }) cfg.mcpServers;

    programs.codex = {
      enable = true;
      mutableSettings = true;
      package = inputs.codex.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings = {
        developer_instructions = builtins.readFile ./codex-instructions.md + "\n" + sharedInstructions;
        mcp_servers = lib.mkIf (cfg.mcpServers != { }) codexMcpServers;
      };
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
