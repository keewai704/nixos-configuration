{ port, publicUrl }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.callPackage ../../../pkgs/icloud-keychain { };
in
{
  home.packages = [ package ];
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };
  systemd.user.services.gnome-keyring = {
    Unit.PartOf = lib.mkForce [ ];
    Service.ExecStart = lib.mkForce "/run/wrappers/bin/gnome-keyring-daemon --start --foreground --components=secrets";
    Install.WantedBy = lib.mkForce [ "default.target" ];
  };
  systemd.user.services.icloud-keychain = {
    Unit = {
      Description = "iCloud Keychain backend for authenticated KeePassXC-Browser relays";
      Requires = [ "gnome-keyring.service" ];
      After = [ "gnome-keyring.service" ];
    };
    Service = {
      Type = "exec";
      ExecStart = "${lib.getExe package} serve --port ${toString port} --public-url ${lib.escapeShellArg publicUrl}";
      WorkingDirectory = config.home.homeDirectory;
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      LimitCORE = 0;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
