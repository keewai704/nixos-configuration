{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.t3code-server;
  package = pkgs.callPackage ../../../pkgs/t3code {
    releases = inputs.t3code-releases;
    claude-code = config.programs.claude-code.finalPackage;
    codex = config.programs.codex.package;
    gh = config.programs.gh.package;
    git = config.programs.git.package;
  };
in
{
  options.services.t3code-server = {
    enable = lib.mkEnableOption "T3 Code nightly server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];
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
        Environment = [
          "PATH=/run/wrappers/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
          "SHELL=${lib.getExe pkgs.zsh}"
          "T3CODE_HOME=${config.home.homeDirectory}/.t3"
        ];
        KillMode = "mixed";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 60;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
