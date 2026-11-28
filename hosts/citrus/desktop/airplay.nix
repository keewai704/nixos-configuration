{ pkgs, ... }:
let
  inherit (import ../settings.nix) lanInterface;
in
{
  services.avahi.publish = {
    enable = true;
    userServices = true;
  };

  systemd.packages = [ pkgs.nqptp ];
  systemd.services.nqptp.wantedBy = [ "multi-user.target" ];

  networking.firewall.interfaces.${lanInterface} = {
    allowedTCPPorts = [
      5000
      7000
    ];
    allowedTCPPortRanges = [
      {
        from = 32768;
        to = 60999;
      }
    ];
    allowedUDPPorts = [
      319
      320
    ];
    allowedUDPPortRanges = [
      {
        from = 6001;
        to = 6011;
      }
      {
        from = 32768;
        to = 60999;
      }
    ];
  };

  services.pipewire.extraConfig.pipewire."10-airplay-rates"."context.properties"."default.clock.allowed-rates" =
    [
      44100
      48000
    ];

  home-manager.users.keewai =
    { config, lib, ... }:
    let
      package = pkgs.shairport-sync-airplay2;
      waitForNqptp = pkgs.writeShellScript "wait-for-nqptp" ''
        until ${pkgs.iproute2}/bin/ss -Hlun 'sport = :9000' | ${pkgs.gnugrep}/bin/grep -q .; do
          sleep 1
        done
      '';
      settings = (pkgs.formats.libconfig { }).generate "shairport-sync.conf" {
        general = {
          output_backend = "pipewire";
          mdns_backend = "avahi";
          dbus_service_bus = "session";
          mpris_service_bus = "session";
        };
        pipewire.mixer_type = "stream";
        metadata = {
          enabled = "yes";
          include_cover_art = "yes";
          cover_art_cache_directory = "${config.xdg.cacheHome}/shairport-sync/coverart";
        };
      };
    in
    {
      systemd.user.services.shairport-sync = {
        Unit = {
          Description = "Shairport Sync AirPlay 2 receiver";
          Wants = [ "pipewire.service" ];
          After = [
            "pipewire.service"
            "wireplumber.service"
          ];
        };
        Service = {
          ExecStartPre = waitForNqptp;
          TimeoutStartSec = 120;
          ExecStart = "${lib.getExe package} -c ${settings}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
