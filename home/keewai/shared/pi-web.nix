{
  config,
  lib,
  pkgs,
  ...
}:
let
  piWeb = pkgs.callPackage ../../../pkgs/pi-web {
    pi-coding-agent = config.programs.pi-coding-agent.package;
    runtimePackages = config.programs.pi-coding-agent.extraPackages;
  };
in
{
  home.packages = [ piWeb ];

  systemd.user.services.pi-web = {
    Unit.Description = "Pi Web coding agent interface";
    Service = {
      Type = "exec";
      ExecStart = "${lib.getExe piWeb} --hostname 127.0.0.1 --port 30141 --no-open";
      WorkingDirectory = config.home.homeDirectory;
      Environment = [
        "PI_CODING_AGENT_DIR=${config.home.homeDirectory}/.pi/agent"
        "PI_WEB_SKIP_VERSION_CHECK=1"
        "NEXT_TELEMETRY_DISABLED=1"
        "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        "SHELL=${lib.getExe pkgs.bash}"
      ];
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 60;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
