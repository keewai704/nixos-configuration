{ inputs, pkgs, ... }:
{
  imports = [ inputs.owly.nixosModules.default ];

  services.owly = {
    enable = true;
    package = pkgs.local.owly;
    settings = {
      station = "wlp9s0";
      country = "JP";
      channels = [
        44
        6
      ];
      allow_untested = true;
    };
  };

  environment.etc."owly/drivers.toml".source = (pkgs.formats.toml { }).generate "drivers.toml" {
    devices."14c3:7925" = {
      status = "untested";
      mode = "exclusive";
      mt76_pm_off = true;
      reconnect_after_monitor = true;
    };
  };

  services.avahi = {
    enable = true;
    openFirewall = false;
    settings = {
      server.allow-interfaces = [
        "eno1"
        "wlp9s0"
      ];
      publish = {
        disable-publishing = false;
        disable-user-service-publishing = false;
        publish-addresses = true;
      };
    };
  };

  networking.firewall.interfaces = {
    awdl0.allowedUDPPorts = [ 5353 ];
  }
  // builtins.listToAttrs (
    map
      (name: {
        inherit name;
        value = {
          allowedTCPPorts = [
            7000
            7001
            7002
          ];
          allowedUDPPorts = [
            5353
            7000
            7001
            7002
          ];
        };
      })
      [
        "eno1"
        "wlp9s0"
      ]
  );
}
