{
  inputs,
  ...
}:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  programs.nixcord = {
    enable = true;
    discord.enable = false;
    legcord = {
      enable = true;
      settings = {
        mods = [ "equicord" ];
        quickCss = true;
        windowStyle = "default";
      };
    };
  };
}
