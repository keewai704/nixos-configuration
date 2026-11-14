{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "stylix.json";

  palette = with config.lib.stylix.colors.withHashtag; {
    base = config.stylix.polarity;
    colors = {
      window = base00;
      panel = base01;
      surface = base01;
      surface_hover = base02;
      surface_active = base03;
      outline = base02;
      text = base05;
      secondary = base04;
      dim = base03;
      accent = base0D;
      accent_hover = base0C;
      on_accent = base00;
      danger = base08;
      warning = base0A;
    };
  };
in
{
  networking.firewall.allowedUDPPorts = [ 5353 ];

  home-manager.users.keewai = {
    home.packages = [ pkgs.spotifast ];

    xdg.configFile."spotifast/themes/${theme}".text = builtins.toJSON palette;

    home.activation.spotifastTheme = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings="''${XDG_CONFIG_HOME:-$HOME/.config}/spotifast/settings.json"
      run mkdir -p "$(dirname "$settings")"
      [ -s "$settings" ] || echo '{}' > "$settings"
      merged="$(mktemp "$settings.XXXXXX")"
      ${lib.getExe pkgs.jq} --arg theme ${theme} '.custom_theme = $theme' "$settings" > "$merged"
      run mv "$merged" "$settings"
    '';
  };
}
