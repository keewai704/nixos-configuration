{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.stylix) colors;
  python = pkgs.python3.withPackages (ps: [
    ps.dbus-next
    ps.pillow
  ]);
  emptyArtwork = pkgs.runCommand "hyprlock-media-empty.png" { } ''
    ${lib.getExe python} - <<'PY'
    import os
    from PIL import Image
    Image.new("RGBA", (256, 256)).save(os.environ["out"], format="PNG")
    PY
  '';
  media = pkgs.writeShellApplication {
    name = "hyprlock-media";
    text = ''
      exec ${lib.getExe python} -B ${./hyprlock-media.py} ${colors.base0D} ${colors.base04} ${emptyArtwork}
    '';
  };
in
{
  programs.hyprlock.settings = lib.mkIf config.programs.dynamic-island.lock.enable {
    image = [
      {
        monitor = "";
        path = "${emptyArtwork}";
        size = 128;
        rounding = 16;
        border_size = 0;
        position = "-285, 62";
        halign = "center";
        valign = "bottom";
        reload_time = 1;
        reload_cmd = ''${pkgs.coreutils}/bin/cat -- "$XDG_RUNTIME_DIR/hyprlock-media/artwork-path" 2>/dev/null || ${pkgs.coreutils}/bin/printf '%s' ${emptyArtwork}'';
      }
    ];
    label = [
      {
        monitor = "";
        text = "cmd[update:1000] ${lib.getExe media}";
        color = "rgb(${colors.base05})";
        font_family = config.stylix.fonts.sansSerif.name;
        font_size = 16;
        text_align = "center";
        position = "80, 40";
        halign = "center";
        valign = "bottom";
        shadow_passes = 2;
        shadow_size = 3;
        shadow_color = "rgba(000000cc)";
      }
    ];
  };
}
