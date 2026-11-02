{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.searxng;
  settings = (pkgs.formats.yaml { }).generate "searxng-settings.yml" {
    use_default_settings = true;
    server = {
      bind_address = "127.0.0.1";
      inherit (cfg) port;
      secret_key = "loopback-only";
      limiter = false;
    };
    search.formats = [
      "html"
      "json"
    ];
    engines = map (name: {
      inherit name;
      disabled = true;
    }) cfg.disabledEngines;
  };
in
{
  options.services.searxng = {
    enable = lib.mkEnableOption "SearXNG as the coding agents' loopback web search";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Loopback port of the search server.";
    };
    disabledEngines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "duckduckgo"
        "google"
        "qwant"
      ];
      description = "Engines that this host's network always gets blocked or timed out by.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.searxng = {
      Unit = {
        Description = "SearXNG metasearch server";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = lib.getExe pkgs.searxng;
        Environment = [ "SEARXNG_SETTINGS_PATH=${settings}" ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    codingAgents.mcpServers.searxng = {
      command = lib.getExe pkgs.mcp-searxng;
      env.SEARXNG_URL = "http://127.0.0.1:${toString cfg.port}";
    };

    programs.claude-code.settings.permissions.deny = [ "WebSearch" ];
    programs.codex.settings.web_search = "disabled";
  };
}
