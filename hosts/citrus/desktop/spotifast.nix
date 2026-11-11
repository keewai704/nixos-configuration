{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "noctalia.json";

  color = name: "{{ colors.${name}.default.hex }}";

  palette = pkgs.writeText "spotifast-noctalia.json" (
    builtins.toJSON {
      base = "{{ mode }}";
      colors = {
        window = color "surface";
        panel = color "surface_container_low";
        surface = color "surface_container";
        surface_hover = "{{ colors.surface_container.default.hex | auto_lightness 4 }}";
        surface_active = "{{ colors.surface_container.default.hex | auto_lightness 8 }}";
        outline = color "outline_variant";
        text = color "on_surface";
        secondary = color "on_surface_variant";
        dim = color "outline";
        accent = color "primary";
        accent_hover = "{{ colors.primary.default.hex | auto_lightness 8 }}";
        on_accent = color "on_primary";
        danger = color "error";
        warning = color "terminal_normal_yellow";
      };
    }
  );
in
{
  networking.firewall.allowedUDPPorts = [ 5353 ];

  home-manager.users.keewai = {
    home.packages = [ pkgs.spotifast ];

    programs.noctalia.settings.theme.templates.user.spotifast = {
      input_path = "${palette}";
      output_path = "$XDG_CONFIG_HOME/spotifast/themes/${theme}";
    };

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
