{
  config,
  lib,
  pkgs,
  ...
}:

{
  # VMConnect's enhanced session reaches xrdp over Hyper-V sockets rather
  # than the network. xorgxrdp then provides clipboard channels and RandR
  # resizing for the session.
  boot.kernelModules = [ "hv_sock" ];

  services = {
    xrdp = {
      enable = true;
      openFirewall = false;
      defaultWindowManager = "${pkgs.xfce4-session}/bin/xfce4-session";

      extraConfDirCommands = ''
        substituteInPlace $out/xrdp.ini \
          --replace-fail 'port=3389' 'port=vsock://-1:3389' \
          --replace-fail '#vmconnect=true' 'vmconnect=true'
      '';
    };

    # Hyprland remains the local Wayland session. Enhanced sessions need an
    # X11 desktop because xorgxrdp is the display backend.
    xserver.desktopManager.xfce.enable = true;
  };

  # The upstream NixOS module always passes a numeric TCP port on the command
  # line, which would override the Hyper-V socket endpoint in xrdp.ini.
  systemd.services.xrdp.serviceConfig.ExecStart = lib.mkForce (
    "${config.services.xrdp.package}/bin/xrdp"
    + " --nodaemon --config ${config.services.xrdp.confDir}/xrdp.ini"
  );
}
