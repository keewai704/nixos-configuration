{ lib, pkgs, ... }:
let
  inherit (import ./settings.nix)
    edcbPort
    konomitvPort
    mirakcPort
    recordings
    captures
    keepAliveSeconds
    storageMountUnit
    serviceDefaults
    ;
  inherit (import ../../settings.nix) tailnetHostname tailnetOrigin;
  mkProxyLocation = import ../web/proxy.nix;
  konomitvConfig = (pkgs.formats.yaml { }).generate "konomitv.yaml" {
    general = {
      backend = "EDCB";
      edcb_url = "tcp://127.0.0.1:${toString edcbPort}/";
      always_receive_tv_from_mirakurun = true;
      mirakurun_url = "http://127.0.0.1:${toString mirakcPort}/";
      encoder = "QSVEncC";
    };
    server.port = konomitvPort;
    tv.max_alive_time = keepAliveSeconds;
    video.recorded_folders = [ recordings ];
    capture.upload_folders = [ captures ];
  };
in
{
  orange.healthMonitor = {
    units = [ "konomitv.service" ];
    loopbackPorts = [ konomitvPort ];
  };

  systemd.services = {
    konomitv = {
      description = "KonomiTV television and recording frontend";
      wantedBy = [
        "multi-user.target"
        "edcb.service"
      ];
      requires = [
        "edcb.service"
        "mirakc.service"
        storageMountUnit
      ];
      after = [
        "edcb.service"
        "mirakc.service"
        storageMountUnit
      ];
      environment = {
        LIBVA_DRIVER_NAME = "iHD";
      };
      serviceConfig = serviceDefaults // {
        StateDirectory = "konomitv";
        LogsDirectory = "konomitv";
        ReadWritePaths = [
          recordings
          captures
        ];
        ExecStart = lib.getExe pkgs.local.konomitv;
        TimeoutStopSec = "60s";
      };
      preStart = ''
        install -d -m 0770 /var/lib/konomitv/data/{account-icons,thumbnails,twitter-debug-screenshots}
        test -e /var/lib/konomitv/config.yaml || install -m 0660 ${konomitvConfig} /var/lib/konomitv/config.yaml
        ${pkgs.local.konomitv.pythonEnv}/bin/python ${./configure-konomitv.py} ${konomitvConfig} /var/lib/konomitv/config.yaml
      '';
    };
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /tv".return = "308 ${tailnetOrigin}/tv/";
    "= /tv/sw.js" =
      (mkProxyLocation konomitvPort ''
        proxy_set_header If-Modified-Since "";
        proxy_set_header If-None-Match "";
        proxy_hide_header ETag;
        proxy_hide_header Last-Modified;
        add_header Cache-Control "no-cache" always;
      '')
      // {
        proxyPass = "http://127.0.0.1:${toString konomitvPort}/sw.js";
      };
    "^~ /tv/" = (mkProxyLocation konomitvPort "proxy_read_timeout 86400s;") // {
      proxyPass = "http://127.0.0.1:${toString konomitvPort}/";
    };
  };
}
