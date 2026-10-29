{
  config,
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
in
{
  options.services.t3code = {
    enable = lib.mkEnableOption "T3 Code nightly as a headless loopback server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Loopback port of the headless server.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

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
  };
}
