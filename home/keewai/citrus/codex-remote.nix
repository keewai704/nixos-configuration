{ config, lib, ... }:
{
  systemd.user.services.codex-remote = {
    Unit.Description = "Codex app-server with authenticated Remote Control";

    Service = {
      Type = "exec";
      # The native Unix socket remains private; Remote Control connects outward.
      # This startup flag is verified against the pinned Codex 0.154 source.
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
