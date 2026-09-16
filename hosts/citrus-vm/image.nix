{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/virtualisation/hyperv-image.nix") ];

  image.baseName = "citrus-vm";
  virtualisation.diskSize = 128 * 1024;

  nixpkgs.overlays = [
    (_final: previousPackages: {
      lkl = previousPackages.callPackage ../../pkgs/lkl-image {
        inherit (previousPackages) lkl;
      };
    })
  ];
}
