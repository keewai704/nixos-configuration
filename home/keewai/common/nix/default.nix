{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "nix";
      runtimeInputs = [
        config.programs.gh.package
        pkgs.coreutils
      ];
      text = ''
        nix_command=${lib.getExe' osConfig.nix.package "nix"}
        ${builtins.readFile ./nix.bash}
      '';
    })
  ];
}
