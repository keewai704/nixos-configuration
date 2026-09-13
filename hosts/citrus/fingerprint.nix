{ pkgs, ... }:
{
  services.fprintd = {
    enable = true;
    package = pkgs.callPackage ../../pkgs/fprintd-cs9711 { };
  };

  security.pam.services.sshd.fprintAuth = false;
  security.pam.services.hyprlock.fprintAuth = false;
}
