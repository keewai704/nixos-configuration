{ lib, pkgs, ... }:
let
  channels = import ./channels.nix;
  inherit (import ./settings.nix)
    mirakcPort
    receiverUnits
    serviceDefaults
    tuners
    tvEnvironment
    ;
  configuration = (pkgs.formats.yaml { }).generate "mirakc.yaml" {
    inherit channels;
    epg.cache-dir = "/var/lib/mirakc/epg";
    server.addrs = [ { http = "127.0.0.1:${toString mirakcPort}"; } ];
    tuners = map (tuner: {
      name = "Sony CECH-ZD1 J ${tuner.id}";
      types = [ "GR" ];
      command = "${pkgs.local.torne-receiver}/bin/torne-receiver tune --socket /run/torne-${tuner.id}/control.sock --ch {{{channel}}} {{{extra_args}}}";
    }) tuners;
    filters.decode-filter.command = "${lib.getExe pkgs.aribb25} - -";
    jobs = {
      scan-services.schedule = "0 30 6 * * * *";
      sync-clocks.disabled = true;
      update-schedules.disabled = true;
    };
    resource.strings-yaml = "${pkgs.local.mirakc}/share/mirakc/strings.yml";
  };
  expectedChannels = pkgs.writeText "mirakc-channels.json" (builtins.toJSON channels);
in
{
  orange.healthMonitor = {
    units = [ "mirakc.service" ];
    loopbackPorts = [ mirakcPort ];
  };

  systemd.services.mirakc = {
    description = "Shared broadcast receiver for KonomiTV and native EDCB";
    wantedBy = [
      "multi-user.target"
      "pcscd.service"
    ];
    requires = receiverUnits ++ [ "pcscd.service" ];
    after = receiverUnits ++ [ "pcscd.service" ];
    path = [ pkgs.local.mirakc-arib ];
    environment = tvEnvironment // {
      RUST_LOG = "info";
    };
    preStart = ''
      install -d -m 0750 /var/lib/mirakc/epg
    '';
    postStart = ''
      ${pkgs.python3}/bin/python ${./wait-mirakc.py} ${expectedChannels} http://127.0.0.1:${toString mirakcPort}
    '';
    serviceConfig = serviceDefaults // {
      StateDirectory = "mirakc";
      StateDirectoryMode = "0750";
      ExecStart = "${lib.getExe pkgs.local.mirakc} --config ${configuration}";
      TimeoutStartSec = "6min";
      TimeoutStopSec = "30s";
    };
  };
}
