{ pkgs, ... }:
{
  home-manager.users.keewai =
    { config, ... }:
    {
      home.packages = [ pkgs.modrinth-app ];
      xdg.dataFile.ModrinthApp.source = config.lib.file.mkOutOfStoreSymlink "/mnt/data/Games/ModrinthApp";
    };
}
