{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/virtualisation/hyperv-image.nix") ];

  image.baseName = "citrus-vm";
  virtualisation.diskSize = 128 * 1024;

  nixpkgs.overlays = [
    (_final: prev: {
      lkl = prev.lkl.overrideAttrs (old: {
        postPatch = old.postPatch + ''
          substituteInPlace tools/lkl/cptofs.c \
            --replace-fail 'lkl_start_kernel("mem=100M")' 'lkl_start_kernel("mem=1024M")'
        '';
      });
    })
  ];
}
