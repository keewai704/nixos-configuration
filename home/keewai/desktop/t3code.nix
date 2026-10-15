{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.local.t3code.override {
    claude-code = config.programs.claude-code.finalPackage;
    codex = config.programs.codex.package;
    gh = config.programs.gh.package;
    git = config.programs.git.package;
  };
  settings = {
    "desktop-settings.json" = {
      localEnvironmentEnabled = true;
      serverExposureMode = "local-only";
      tailscaleServeEnabled = true;
      tailscaleServePort = 443;
      updateChannel = "nightly";
      updateChannelConfiguredByUser = true;
    };
    "settings.json".providerInstances = {
      codex = {
        driver = "codex";
        enabled = true;
        config = {
          setupMode = "existing";
          binaryPath = lib.getExe config.programs.codex.package;
          homePath = "${config.home.homeDirectory}/.codex";
        };
      };
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
  home.packages = [ package ];

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
      ) settings
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
      Environment = [
        "PATH=/run/wrappers/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
        "SHELL=${lib.getExe pkgs.zsh}"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
