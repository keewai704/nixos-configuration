{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  discordPresence = pkgs.writers.writePython3Bin "genshin-discord-presence" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./discord-presence.py);
in
{
  imports = [ inputs.aagl.nixosModules.default ];

  nix.settings = inputs.aagl.nixConfig;

  programs.anime-game-launcher.enable = true;

  home-manager.users.keewai =
    { config, ... }:
    {
      xdg.dataFile.anime-game-launcher.source = config.lib.file.mkOutOfStoreSymlink "/mnt/data/Games/anime-game-launcher";

      systemd.user.services.genshin-discord-presence = {
        Unit = {
          Description = "Discord Rich Presence for Genshin Impact";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = lib.getExe discordPresence;
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
