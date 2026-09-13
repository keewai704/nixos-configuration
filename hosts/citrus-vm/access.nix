{ lib, ... }:
{
  services.openssh = {
    openFirewall = lib.mkForce true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  users.users.keewai.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICvw3CEB+UhtnL8iMffx4nIp2PfsYLfidndDDqfZNdYP citrus-vm@CITRUS"
  ];
}
