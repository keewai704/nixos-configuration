{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  confirm = pkgs.writeShellApplication {
    name = "airdrop-confirm";
    runtimeInputs = [ pkgs.zenity ];
    text = ''
      exec zenity --question --title=AirDrop --no-markup \
        --text="$1" --ok-label=Accept --cancel-label=Decline \
        --default-cancel --timeout=12
    '';
  };
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
      ExecStart = "${lib.getExe pkgs.uxplay} -n ${lib.escapeShellArg osConfig.networking.hostName} -nh -p 7000 -avdec -vs ximagesink -as pulsesink -hls";
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.airdrop-receive = {
    Unit = {
      Description = "AirDrop receiver with desktop confirmation";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe airdrop} receive --confirm-command ${lib.getExe confirm}";
      Restart = "always";
      RestartSec = 5;
      UMask = "0077";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.desktopEntries = {
    airdrop-receive = {
      name = "AirDrop Receive";
      comment = "Receive files from Apple devices";
      icon = "folder-download";
      exec = "${pkgs.systemd}/bin/systemctl --user restart airdrop-receive.service";
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
    airdrop-stop = {
      name = "AirDrop Stop";
      comment = "Stop receiving and release the Wi-Fi radio";
      icon = "network-offline";
      exec = "${pkgs.systemd}/bin/systemctl --user stop airdrop-receive.service";
      categories = [
        "Network"
        "FileTransfer"
      ];
    };
  };
}
