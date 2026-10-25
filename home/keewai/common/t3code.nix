{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.t3code;
  package = pkgs.local.t3code.override {
    claude-code = config.programs.claude-code.finalPackage;
    gh = config.programs.gh.package;
    git = config.programs.git.package;
  };
  environment = [
    "PATH=/run/wrappers/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
    "SHELL=${lib.getExe pkgs.zsh}"
  ];
  desktopSettings = {
    "desktop-settings.json" = {
      localEnvironmentEnabled = true;
      serverExposureMode = "local-only";
      tailscaleServeEnabled = true;
      tailscaleServePort = 443;
      updateChannel = "nightly";
      updateChannelConfiguredByUser = true;
    };
    "settings.json".providerInstances = {
      claudeAgent = {
        driver = "claudeAgent";
        enabled = true;
        config = {
          binaryPath = lib.getExe config.programs.claude-code.finalPackage;
          homePath = "${config.home.homeDirectory}/.claude";
        };
      };
    };
  };
in
{
  options.services.t3code = {
    mode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "desktop"
          "server"
        ]
      );
      default = null;
      description = "Run T3 Code nightly as the desktop app or as a headless loopback server.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Loopback port of the headless server.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode != null) {
      home.packages = [ package ];
    })

    (lib.mkIf (cfg.mode == "desktop") {
      home.activation.t3codeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: value:
            lib.hm.generators.mkImpureConfigMerger {
              inherit pkgs;
              format = "json";
              empty = "{}";
              jqOperation = "$dynamic * $static";
              path = "${config.home.homeDirectory}/.t3/userdata/${name}";
              staticSettings = pkgs.writeText "t3code-${name}" (builtins.toJSON value);
              mode = "600";
            }
          ) desktopSettings
        )
      );

      xdg.mimeApps.defaultApplications."x-scheme-handler/t3code" = [ "t3code.desktop" ];

      systemd.user.services.t3code = {
        Unit = {
          Description = "T3 Code nightly desktop and Tailscale HTTPS backend";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = lib.getExe package;
          WorkingDirectory = config.home.homeDirectory;
          UMask = "0077";
          Environment = environment;
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStopSec = 30;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })

    (lib.mkIf (cfg.mode == "server") {
      home.extraDependencies = [ inputs.t3code-releases.outPath ];

      systemd.user.services.t3code = {
        Unit = {
          Description = "T3 Code nightly server";
          After = [ "network.target" ];
        };
        Service = {
          ExecStart = "${package}/bin/t3 serve --mode web --host 127.0.0.1 --port ${toString cfg.port}";
          WorkingDirectory = config.home.homeDirectory;
          UMask = "0077";
          Environment = environment ++ [ "T3CODE_HOME=${config.home.homeDirectory}/.t3" ];
          KillMode = "mixed";
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStopSec = 60;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
