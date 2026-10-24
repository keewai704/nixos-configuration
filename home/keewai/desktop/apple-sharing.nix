{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  airdrop = pkgs.writeShellApplication {
    name = "airdrop";
    runtimeInputs = [
      osConfig.services.owly.package
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.util-linux
      pkgs.xdg-user-dirs
      pkgs.zenity
    ];
    text = builtins.readFile ./airdrop.sh;
  };
in
{
  home.packages = [
    airdrop
    pkgs.uxplay
  ];

  systemd.user.services.uxplay = {
    Unit = {
      Description = "AirPlay video and audio receiver";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.uxplay} -n ${lib.escapeShellArg osConfig.networking.hostName} -nh -p 7000 -avdec -vs waylandsink -as pulsesink";
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.desktopEntries = {
    airdrop-receive = {
      name = "AirDrop Receive";
      comment = "Receive files from Apple devices";
      icon = "folder-download";
      exec = "${lib.getExe pkgs.kitty} --title AirDrop ${lib.getExe airdrop} receive";
      categories = [
        "Network"
        "FileTransfer"
      ];
    };
    airdrop-send = {
      name = "AirDrop Send";
      comment = "Send files to an Apple device";
      icon = "document-send";
      exec = "${lib.getExe pkgs.kitty} --title AirDrop ${lib.getExe airdrop} send %F";
      categories = [
        "Network"
        "FileTransfer"
      ];
    };
  };
}
