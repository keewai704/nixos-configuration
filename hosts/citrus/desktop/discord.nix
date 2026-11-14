{
  impastoPalette,
  inputs,
  lib,
  ...
}:
let
  shades =
    name: color:
    lib.concatImapStrings (index: mix: "    --${name}-${toString index}: ${mix};\n") [
      "color-mix(in oklch, ${color}, white 20%)"
      "color-mix(in oklch, ${color}, white 10%)"
      color
      "color-mix(in oklch, ${color}, black 10%)"
      "color-mix(in oklch, ${color}, black 20%)"
    ];

  colors = with impastoPalette; ''
    :root:root {
        --text-0: ${accentText};
        --text-1: ${text};
        --text-2: color-mix(in oklch, ${text}, ${textMuted} 33%);
        --text-3: color-mix(in oklch, ${text}, ${textMuted} 66%);
        --text-4: ${textMuted};
        --text-5: color-mix(in oklch, ${textMuted}, ${background} 40%);

        --bg-1: ${border};
        --bg-2: ${surfaceHover};
        --bg-3: ${surface};
        --bg-4: ${background};
        --hover: color-mix(in srgb, ${textMuted} 10%, transparent);
        --active: color-mix(in srgb, ${textMuted} 20%, transparent);
        --active-2: color-mix(in srgb, ${textMuted} 30%, transparent);

    ${shades "purple" accent}${shades "red" red}${shades "green" green}${shades "blue" blue}${shades "yellow" yellow}}
  '';
in
{
  home-manager.users.keewai = {
    imports = [ inputs.nixcord.homeModules.nixcord ];

    stylix.targets = {
      nixcord.enable = false;
      vencord.enable = false;
    };

    programs.nixcord = {
      enable = true;
      discord.equicord.enable = true;
    };

    home.activation.equicord-settings = lib.mkForce (inputs.home-manager.lib.hm.dag.entryAnywhere "");

    xdg.configFile."Equicord/settings/quickCss.css".text = colors;
  };
}
