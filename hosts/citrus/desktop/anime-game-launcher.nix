{ inputs, ... }:
{
  imports = [ inputs.aagl.nixosModules.default ];

  nix.settings = inputs.aagl.nixConfig;

  programs.anime-game-launcher.enable = true;

  home-manager.users.keewai =
    { config, ... }:
    {
      xdg.dataFile.anime-game-launcher.source = config.lib.file.mkOutOfStoreSymlink "/mnt/data/Games/anime-game-launcher";
    };
}
