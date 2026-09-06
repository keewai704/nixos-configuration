{ inputs, ... }:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.keewai = {
      imports = [ ../home/keewai/common.nix ];
      home.stateVersion = "26.05";
    };
  };
}
