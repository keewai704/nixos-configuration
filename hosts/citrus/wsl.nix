{ inputs, lib, ... }:
{
  imports = [ inputs.nixos-wsl.nixosModules.default ];

  wsl = {
    enable = true;
    defaultUser = "keewai";
    useWindowsDriver = true;
    startMenuLaunchers = false;
    wslConf = {
      automount.enabled = true;
      interop = {
        enabled = true;
        appendWindowsPath = true;
      };
      network = {
        generateHosts = true;
        generateResolvConf = true;
      };
    };
  };

  networking.networkmanager.enable = lib.mkForce false;
  services.openssh.enable = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  users.users.keewai.extraGroups = lib.mkForce [ "wheel" ];

  programs.nix-ld.enable = true;

  nix.settings = {
    max-jobs = 2;
    cores = 4;
    extra-substituters = lib.mkForce [ ];
    extra-trusted-public-keys = lib.mkForce [ ];
  };
}
