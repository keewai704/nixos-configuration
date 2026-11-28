{
  cudaPkgs,
  lib,
  mkClientAllowlist,
  pkgs,
  ...
}:
let
  inherit (import ../settings.nix)
    immichMachineLearningBackendPort
    immichMachineLearningClients
    immichMachineLearningPort
    tailnetHostname
    ;

  cacheDirectory = "/var/cache/immich-machine-learning";
  backendAddress = "127.0.0.1:${toString immichMachineLearningBackendPort}";
  suspendSocket = "/run/citrus-suspend.sock";

  orangeOnly = mkClientAllowlist "$immich_machine_learning_allowed" immichMachineLearningClients;

  suspend = pkgs.writeShellScript "citrus-suspend" ''
    while IFS= read -r line; do
      [[ $line == $'\r' ]] && break
    done
    printf 'HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
    exec ${lib.getExe' pkgs.systemd "systemctl"} --no-block suspend
  '';
in
{
  systemd.services = {
    immich-machine-learning = {
      description = "Immich machine learning inference";
      after = [ "network.target" ];
      unitConfig.StopWhenUnneeded = true;
      environment = {
        IMMICH_HOST = "127.0.0.1";
        IMMICH_PORT = toString immichMachineLearningBackendPort;
        MACHINE_LEARNING_CACHE_FOLDER = cacheDirectory;
        XDG_CACHE_HOME = cacheDirectory;
        HOME = cacheDirectory;
        HF_HUB_DISABLE_XET = "1";
        MACHINE_LEARNING_MODEL_REVISION = "v2";
        MACHINE_LEARNING_REQUEST_THREADS = "3";
      };
      serviceConfig = {
        ExecStart = lib.getExe cudaPkgs.immich-machine-learning;
        ExecStartPost = "${lib.getExe pkgs.curl} --silent --fail --output /dev/null --retry 170 --retry-all-errors --retry-delay 1 --retry-max-time 170 http://${backendAddress}/ping";
        TimeoutStartSec = "180s";
        DynamicUser = true;
        CacheDirectory = "immich-machine-learning";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    immich-machine-learning-proxy = {
      description = "Start Immich machine learning on demand";
      requires = [ "immich-machine-learning.service" ];
      after = [ "immich-machine-learning.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=10min ${backendAddress}";
        DynamicUser = true;
      };
    };

    "citrus-suspend@".serviceConfig = {
      ExecStart = suspend;
      StandardInput = "socket";
      StandardOutput = "socket";
    };
  };

  systemd.sockets = {
    immich-machine-learning-proxy.socketConfig.ListenStream = "127.0.0.1:${toString immichMachineLearningPort}";

    citrus-suspend = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = suspendSocket;
        Accept = true;
        SocketUser = "nginx";
        SocketMode = "0600";
      };
    };
  };

  services.nginx = {
    appendHttpConfig = orangeOnly.map;

    virtualHosts.${tailnetHostname}.locations = {
      "^~ /immich-machine-learning/" = {
        proxyPass = "http://127.0.0.1:${toString immichMachineLearningPort}/";
        extraConfig = orangeOnly.deny;
      };

      "= /immich-machine-learning-control/alive".extraConfig = orangeOnly.deny + ''
        return 204;
      '';

      "= /immich-machine-learning-control/suspend" = {
        proxyPass = "http://unix:${suspendSocket}:/";
        extraConfig = orangeOnly.deny + ''
          if ($request_method != POST) {
            return 405;
          }
        '';
      };
    };
  };
}
