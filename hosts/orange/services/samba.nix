let
  inherit (import ../settings.nix) lanInterface storageMountUnit storageRoot;
  storageDependencies = [ storageMountUnit ];
in
{
  networking.firewall.interfaces = {
    ${lanInterface} = {
      allowedTCPPorts = [
        139
        445
      ];
      allowedUDPPorts = [
        137
        138
      ];
    };
    tailscale0.allowedTCPPorts = [ 445 ];
  };

  services.samba = {
    enable = true;
    winbindd.enable = false;
    settings = {
      global = {
        "map to guest" = "Bad User";
      };

      storage = {
        path = storageRoot;
        comment = "Orange HDD storage";
        "guest ok" = "yes";
        "guest only" = "yes";
        "read only" = "no";
        "force user" = "keewai";
        "force group" = "immich-media";
        "create mask" = "0664";
        "directory mask" = "0775";
        "veto files" = "/server/lost+found/";
      };
    };
  };

  systemd.services = {
    samba-smbd = {
      requires = storageDependencies;
      after = storageDependencies;
    };
  };
}
