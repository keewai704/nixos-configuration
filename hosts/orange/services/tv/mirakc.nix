{ lib, pkgs, ... }:
let
  channels = [
    {
      name = "NHK Eテレ大阪";
      type = "GR";
      channel = "13";
      services = [
        2056
        2057
        2058
      ];
    }
    {
      name = "読売テレビ";
      type = "GR";
      channel = "14";
      services = [
        2088
        2089
        2090
      ];
    }
    {
      name = "ABCテレビ";
      type = "GR";
      channel = "15";
      services = [
        2072
        2073
        2074
      ];
    }
    {
      name = "MBS";
      type = "GR";
      channel = "16";
      services = [
        2064
        2065
        2066
      ];
    }
    {
      name = "関西テレビ";
      type = "GR";
      channel = "17";
      services = [
        2080
        2081
        2082
      ];
    }
    {
      name = "テレビ大阪";
      type = "GR";
      channel = "18";
      services = [
        41008
        41009
        41010
      ];
    }
    {
      name = "NHK総合大阪";
      type = "GR";
      channel = "24";
      services = [
        40960
        40961
      ];
    }
    {
      name = "サンテレビ";
      type = "GR";
      channel = "26";
      services = [ 43056 ];
    }
  ];
  configuration = (pkgs.formats.yaml { }).generate "mirakc.yaml" {
    inherit channels;
    epg.cache-dir = "/var/lib/mirakc/epg";
    server.addrs = [ { http = "127.0.0.1:40772"; } ];
    tuners = [
      {
        name = "Sony CECH-ZD1 J";
        types = [ "GR" ];
        command = "${pkgs.local.coax}/bin/coax tune --no-start --system ISDBT --ch {{{channel}}}";
      }
    ];
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
    requires = [
      "coaxd.service"
      "coax-pcsc.service"
    ];
    after = [
      "coaxd.service"
      "coax-pcsc.service"
    ];
    path = [ pkgs.local.mirakc-arib ];
    environment = {
      COAXD_SOCKET = "/run/coax/http.sock";
      PCSCLITE_CSOCK_NAME = "/run/coax/pcscd.comm";
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
