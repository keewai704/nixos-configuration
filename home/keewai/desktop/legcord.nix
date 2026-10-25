{
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  programs.nixcord = {
    enable = true;
    discord.enable = false;
    legcord = {
      enable = true;
      package = pkgs.local.legcord;
      settings = {
        mods = [ "equicord" ];
        quickCss = true;
        windowStyle = "default";
      };
    };
  };
}
