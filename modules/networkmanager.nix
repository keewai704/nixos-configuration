{
  networking.networkmanager.enable = true;

  users.users.keewai.extraGroups = [ "networkmanager" ];
}
