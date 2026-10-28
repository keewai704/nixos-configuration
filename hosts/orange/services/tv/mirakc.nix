{ lib, pkgs, ... }:
let
  channels = import ./channels.nix;
  tuners = import ./tuners.nix;
  receiverUnits = map (tuner: "torne-receiver-${tuner.id}.service") tuners;
  configuration = (pkgs.formats.yaml { }).generate "mirakc.yaml" {
    inherit channels;
    epg.cache-dir = "/var/lib/mirakc/epg";
    server.addrs = [ { http = "127.0.0.1:40772"; } ];
    tuners = map (tuner: {
      name = "Sony CECH-ZD1 J ${tuner.id}";
      types = [ "GR" ];
      command = "${pkgs.local.torne-receiver}/bin/torne-receiver tune --socket /run/torne-${tuner.id}/control.sock --ch {{{channel}}} {{{extra_args}}}";
    }) tuners;
    filters.decode-filter.command = "${lib.getExe pkgs.aribb25} - -";
    jobs = {
      scan-services.schedule = "0 0 3 * * * *";
      sync-clocks.disabled = true;
      update-schedules.disabled = true;
    };
    resource.strings-yaml = "${pkgs.local.mirakc}/share/mirakc/strings.yml";
  };
  expectedChannels = pkgs.writeText "mirakc-channels.json" (builtins.toJSON channels);
in
{
  systemd.services.mirakc = {
    description = "Shared broadcast receiver for KonomiTV and native EDCB";
    wantedBy = [ "multi-user.target" ];
    requires = receiverUnits ++ [ "pcscd.service" ];
    after = receiverUnits ++ [ "pcscd.service" ];
    path = [ pkgs.local.mirakc-arib ];
    environment = {
      PCSCLITE_CSOCK_NAME = "/run/pcscd/pcscd.comm";
      RUST_LOG = "info";
    };
    preStart = ''
      install -d -m 0750 /var/lib/mirakc/epg
    '';
    postStart = ''
      ${pkgs.python3}/bin/python ${./wait-mirakc.py} ${expectedChannels}
    '';
    serviceConfig = {
      User = "tv";
      Group = "tv";
      StateDirectory = "mirakc";
      StateDirectoryMode = "0750";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      UMask = "0007";
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = "${lib.getExe pkgs.local.mirakc} --config ${configuration}";
      TimeoutStartSec = "6min";
      TimeoutStopSec = "30s";
    };
  };
}
