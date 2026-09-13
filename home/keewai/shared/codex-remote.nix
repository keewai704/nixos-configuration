{ config, lib, ... }:
{
  systemd.user.services.codex-remote = {
    Unit.Description = "Codex app-server with authenticated Remote Control";

    Service = {
      Type = "exec";
      ExecStart = "${lib.getExe config.programs.codex.package} app-server --listen unix:// --remote-control";
      WorkingDirectory = config.home.homeDirectory;
      Environment = [ "CODEX_HOME=${config.home.homeDirectory}/.codex" ];
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 60;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
