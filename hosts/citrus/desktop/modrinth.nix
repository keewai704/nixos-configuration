{ lib, pkgs, ... }:
let
  modrinth-app =
    (pkgs.modrinth-app.override {
      modrinth-app-unwrapped = pkgs.modrinth-app-unwrapped.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ pkgs.sqlite ];
      });
    }).overrideAttrs
      (old: {
        runtimeDependencies = old.runtimeDependencies + ":" + lib.makeLibraryPath [ pkgs.vulkan-loader ];
      });
in
{
  home-manager.users.keewai =
    { config, ... }:
    {
      home.packages = [ modrinth-app ];
      xdg.dataFile.ModrinthApp.source = config.lib.file.mkOutOfStoreSymlink "/mnt/data/Games/ModrinthApp";
    };
}
