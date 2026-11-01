{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.rustxng;
in
{
  options.services.rustxng = {
    enable = lib.mkEnableOption "RustXNG as the coding agents' loopback web search";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Loopback port of the search server.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.rustxng = {
      Unit = {
        Description = "RustXNG metasearch server";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.local.rustxng} --bind 127.0.0.1 --port ${toString cfg.port}";
        Environment = [ "RUST_LOG=warn" ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    codingAgents.mcpServers.rustxng = {
      command = lib.getExe pkgs.mcp-searxng;
      env.SEARXNG_URL = "http://127.0.0.1:${toString cfg.port}";
    };

    programs.claude-code.settings.permissions.deny = [ "WebSearch" ];
    programs.codex.settings.web_search = "disabled";
  };
}
