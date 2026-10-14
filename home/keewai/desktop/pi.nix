{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.callPackage ../../../pkgs/pi { };
  modules = "${package}/lib/pi/node_modules";
  agentDir = "${config.home.homeDirectory}/.pi/agent";
  publicUrl = "https://citrus.tail1e65cd.ts.net:8443/";
  initialSettings = pkgs.writeText "pi-settings.json" (
    builtins.toJSON {
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
    launcher
  ];

  home.file = {
    ".pi/agent/node_modules".source = modules;
    ".pi/agent/extensions/pi-openai-codex-device-login".source =
      "${modules}/pi-openai-codex-device-login";
    ".pi/agent/extensions/pi-codex-web-run".source = "${modules}/@howaboua/pi-codex-web-run";
  };

  home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ ! -e ${lib.escapeShellArg "${agentDir}/settings.json"} ]; then
      run install -m 600 ${initialSettings} ${lib.escapeShellArg "${agentDir}/settings.json"}
    fi
    run ${lib.getExe pkgs.python3} - ${lib.escapeShellArg "${agentDir}/settings.json"} <<'PY'
    import json
    from pathlib import Path
    import sys
    import tempfile

    path = Path(sys.argv[1])
    original = json.loads(path.read_text())
    settings = original.copy()
    if settings.get("defaultProvider") == "claude-bridge":
        settings.pop("defaultProvider")
        settings.pop("defaultModel", None)
    if "enabledModels" in settings:
        settings["enabledModels"] = [
            model for model in settings["enabledModels"] if not model.startswith("claude-bridge/")
        ]
    if settings != original:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as temporary:
            temporaryPath = Path(temporary.name)
            try:
                json.dump(settings, temporary, indent=2)
                temporary.write("\n")
                temporary.close()
                temporaryPath.replace(path)
            finally:
                temporaryPath.unlink(missing_ok=True)
    PY
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
              pkgs.nodejs
              pkgs.bashInteractive
              pkgs.git
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
