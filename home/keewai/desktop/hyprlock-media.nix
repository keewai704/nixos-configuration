{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.stylix) colors;
  python = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);
  media = pkgs.writeShellApplication {
    name = "hyprlock-media";
    text = ''
      exec ${lib.getExe python} -B ${./hyprlock-media.py} ${colors.base0D} ${colors.base04}
    '';
  };
in
{
  programs.hyprlock.settings.label = lib.mkIf config.programs.dynamic-island.lock.enable [
    {
      monitor = "";
      text = "cmd[update:1000] ${lib.getExe media}";
      color = "rgb(${colors.base05})";
      font_family = config.stylix.fonts.sansSerif.name;
      font_size = 16;
      text_align = "center";
      position = "0, 40";
      halign = "center";
      valign = "bottom";
      shadow_passes = 2;
      shadow_size = 3;
      shadow_color = "rgba(000000cc)";
    }
  ];
}
