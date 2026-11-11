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
      config.programs.umbriel.package
      pkgs.jq
      pkgs.wlr-randr
    ];
    text = builtins.readFile ./display.sh;
  };

  app = name: mode: {
    inherit name;
    prep-cmd = [
      {
        do = "${lib.getExe display} ${mode}";
        undo = "${lib.getExe display} restore";
      }
    ];
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
      (app "拡張ディスプレイ" "extend")
      (app "このディスプレイのみ" "only")
      (app "ミラー" "mirror")
    ];
  };

  systemd.user.services.sunshine.serviceConfig.ExecStopPost = "-${lib.getExe display} restore";
}
