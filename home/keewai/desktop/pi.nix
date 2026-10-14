{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.callPackage ../../../pkgs/pi { };
  modules = "${package}/lib/pi/node_modules";
  sgrep = pkgs.callPackage ../../../pkgs/sgrep { };
  claude = config.programs.claude-code.finalPackage;
  agentDir = "${config.home.homeDirectory}/.pi/agent";
  publicUrl = "https://citrus.tail1e65cd.ts.net:8443/";
  initialSettings = pkgs.writeText "pi-settings.json" (
    builtins.toJSON {
      defaultProvider = "claude-bridge";
      defaultModel = "claude-sonnet-5-5";
      enableInstallTelemetry = false;
      enableAnalytics = false;
      cacheWarming = "off";
      shellPath = lib.getExe pkgs.bashInteractive;
    }
  );
  launcher = pkgs.writeShellApplication {
    name = "pi-web";
    runtimeInputs = [
      pkgs.systemd
      pkgs.xdg-utils
    ];
    text = ''
      case "''${1:-}" in
        --password)
          exec ${lib.getExe pkgs.python3} ${../../../pkgs/pi/web-launch.py} --show-password
          ;;
        --no-open)
          printf '%s\n' ${lib.escapeShellArg publicUrl}
          ;;
        "")
          systemctl --user start pi-web.service pi-web-tailscale.service
          printf '%s\n' 'Use pi-web --password to show the login password.'
          exec xdg-open ${lib.escapeShellArg publicUrl}
          ;;
        *)
          printf '%s\n' 'Usage: pi-web [--no-open|--password]' >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  home.packages = [
    package
    sgrep
    launcher
  ];

  home.file = {
    ".pi/agent/APPEND_SYSTEM.md".text = ''
      # Code search

      Prefer Context.dev's `sgrep` via the bash tool over ripgrep for code discovery.
      Search by intent with `sgrep "plain English description" ./path`; use `-n 10`
      to limit results or `--json` for structured output. Narrow the search path.
      Results are approximate: read the matching source before drawing conclusions.
      Use `rg` only for exact names, literal text, regexes, or file enumeration.
      To rank focused regex matches, run both commands from the same directory:
      `rg --json -C 3 'pattern' ./path | sgrep "search intent" --stdin`.
      Do not alias rg to sgrep: their command-line interfaces differ.
      Searches stay local. The first search downloads model/parser assets;
      if downloads fail, report the limitation and use exact search as a fallback.
    '';
    ".pi/agent/node_modules".source = modules;
    ".pi/agent/extensions/pi-claude-bridge".source = "${modules}/pi-claude-bridge";
    ".pi/agent/extensions/pi-codex-web-run".source = "${modules}/@howaboua/pi-codex-web-run";
    ".pi/agent/claude-bridge.json".text = builtins.toJSON {
      askClaude.enabled = false;
      provider = {
        plan = "pro";
        longContextExtraUsage = false;
        strictMcpConfig = true;
        autoMemoryEnabled = false;
        pathToClaudeCodeExecutable = lib.getExe claude;
      };
    };
  };

  home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ ! -e ${lib.escapeShellArg "${agentDir}/settings.json"} ]; then
      run install -m 600 ${initialSettings} ${lib.escapeShellArg "${agentDir}/settings.json"}
    fi
  '';

  xdg.desktopEntries.pi-web = {
    name = "Pi Web";
    genericName = "Coding Agent Web UI";
    exec = "pi-web";
    icon = "utilities-terminal";
    categories = [ "Development" ];
    terminal = false;
  };

  systemd.user.services = {
    pi-web = {
      Unit.Description = "Pi coding agent Web UI";
      Service = {
        ExecStart = "${package}/bin/pi-web-server";
        WorkingDirectory = config.home.homeDirectory;
        RuntimeDirectory = "pi-web";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        Environment = [
          "PI_CODING_AGENT_DIR=${agentDir}"
          "PI_WEB_ALLOWED_HOSTS=citrus.tail1e65cd.ts.net"
          "PI_WEB_SKIP_VERSION_CHECK=1"
          "NEXT_TELEMETRY_DISABLED=1"
          "NODE_ENV=production"
          "SHELL=${lib.getExe pkgs.bashInteractive}"
          "PATH=/run/wrappers/bin:${
            lib.makeBinPath [
              package
              claude
              pkgs.nodejs
              pkgs.bashInteractive
              pkgs.git
              sgrep
              pkgs.ripgrep
              pkgs.fd
              pkgs.coreutils
            ]
          }:/etc/profiles/per-user/keewai/bin:/run/current-system/sw/bin"
        ];
        UnsetEnvironment = [
          "ANTHROPIC_API_KEY"
          "ANTHROPIC_AUTH_TOKEN"
          "ANTHROPIC_BASE_URL"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        SuccessExitStatus = [ 143 ];
        TimeoutStopSec = 30;
      };
      Install.WantedBy = [ "default.target" ];
    };

    pi-web-tailscale = {
      Unit = {
        Description = "Publish Pi Web over Tailscale HTTPS";
        After = [ "pi-web.service" ];
        Wants = [ "pi-web.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=8443 http://127.0.0.1:30141";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=8443 off";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
