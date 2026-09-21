{
  config,
  lib,
  pkgs,
  ...
}:
let
  display = lib.getExe (pkgs.callPackage ../../pkgs/sunshine-display { });
  steam = lib.getExe config.programs.steam.package;
  desktop = name: mode: {
    inherit name;
    image-path = "desktop.png";
    prep-cmd = [
      {
        do = "${display} ${mode}";
        undo = "${display} restore";
      }
    ];
  };
in
{
  services.sunshine = {
    enable = true;
    package = pkgs.sunshine.override { cudaSupport = true; };
    capSysAdmin = false;
    settings = {
      sunshine_name = "citrus";
      capture = "wlr";
      encoder = "nvenc";
      output_name = "SUNSHINE";
      origin_web_ui_allowed = "pc";
      upnp = "disabled";
      nvenc_preset = 1;
      nvenc_twopass = "quarter_res";
    };
    applications.apps = [
      (desktop "Extend Display" "extend")
      (
        (desktop "Steam Big Picture" "client-only")
        // {
          image-path = "steam.png";
          detached = [ "${pkgs.util-linux}/bin/setsid ${steam} steam://open/bigpicture" ];
          prep-cmd = (desktop "" "client-only").prep-cmd ++ [
            { undo = "${steam} steam://close/bigpicture"; }
          ];
        }
      )
      (desktop "Client Only" "client-only")
    ];
  };

  networking.firewall = {
    allowedTCPPorts = [
      47984
      47989
      48010
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      48002
      48010
    ];
  };

  users.users.keewai.extraGroups = [ "uinput" ];

  boot.kernelModules = [ "uhid" ];
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-sunshine-uhid.rules" ''
      KERNEL=="uhid", SUBSYSTEM=="misc", GROUP="uinput", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uhid"
    '')
  ];

  systemd.user.services.sunshine.serviceConfig = {
    ExecStartPre = "${display} init";
    ExecStopPost = "${display} stop";
  };
}
