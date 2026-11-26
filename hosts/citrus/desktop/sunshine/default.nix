{
  config,
  cudaPkgs,
  lib,
  pkgs,
  ...
}:
let
  display = pkgs.writeShellApplication {
    name = "sunshine-display";
    runtimeInputs = [
      config.programs.hyprland.package
      pkgs.jq
    ];
    text = builtins.readFile ./display.sh;
  };

  bigPicture = pkgs.writeShellApplication {
    name = "sunshine-big-picture";
    runtimeInputs = [
      config.programs.steam.package
      pkgs.procps
      pkgs.util-linux
    ];
    text = builtins.readFile ./big-picture.sh;
  };

  app = name: mode: extraPrep: {
    inherit name;
    prep-cmd = [
      {
        do = "${lib.getExe display} ${mode}";
        undo = "${lib.getExe display} restore";
      }
    ]
    ++ extraPrep;
  };
in
{
  services.sunshine = {
    enable = true;
    package = cudaPkgs.sunshine;
    openFirewall = true;
    settings = {
      capture = "wlr";
      output_name = "sunshine";
    };
    applications.apps = [
      (app "拡張ディスプレイ" "extend" [ ])
      (app "このディスプレイのみ" "only" [
        {
          do = "${lib.getExe bigPicture} open";
          undo = "${lib.getExe bigPicture} close";
        }
      ])
      (app "ミラー" "mirror" [ ])
    ];
  };

  systemd.user.services.sunshine.serviceConfig.ExecStopPost = "-${lib.getExe display} restore";
}
