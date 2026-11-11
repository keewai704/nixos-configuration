{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.searxng;
  blockedEngines = [
    "duckduckgo"
    "google"
    "qwant"
  ];
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
    }) blockedEngines;
  };
in
{
  options.services.searxng.port = lib.mkOption {
    type = lib.types.port;
    default = 8888;
    description = "Loopback port of the coding agents' web search server.";
  };

  config = {
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
