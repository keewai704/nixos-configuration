{
  config,
  lib,
  pkgs,
  ...
}:
let
  paseo = pkgs.callPackage ../../../pkgs/paseo { };
in
{
  home = {
    packages = [ paseo ];

    file.".paseo/config.json".text = builtins.toJSON {
      version = 1;
      daemon = {
        listen = "127.0.0.1:6767";
        relay.enabled = false;
      };
      features = {
        webUi.enabled = true;
        dictation.enabled = false;
        voiceMode.enabled = false;
      };
      agents.providers.codex.command = [ (lib.getExe config.programs.codex.package) ];
    };
  };

  systemd.user.services.paseo = {
    Unit = {
      Description = "Paseo coding agents and web UI";
      X-Restart-Triggers = [ config.home.file.".paseo/config.json".source ];
    };

    Service = {
      Type = "exec";
      ExecStart = "${paseo}/bin/paseo-server";
      WorkingDirectory = config.home.homeDirectory;
      Environment = [
        "PASEO_HOME=${config.home.homeDirectory}/.paseo"
        "CODEX_HOME=${config.home.homeDirectory}/.codex"
      ];
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 60;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
