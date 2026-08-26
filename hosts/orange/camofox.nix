{ lib, pkgs, ... }:

let
  camofoxStateDir = "/home/keewai/.local/share/camofox";
  camoufoxCacheDir = "${camofoxStateDir}/cache/camoufox";

  camofoxPackage = pkgs.callPackage ./camofox-package.nix {
    websockify = pkgs.python3Packages.websockify;
  };

  healthCheck = pkgs.writeShellScript "camofox-health-check" ''
    for attempt in $(seq 1 60); do
      if ${lib.getExe pkgs.curl} --fail --silent --show-error \
        http://127.0.0.1:9377/health >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    echo "Camofox did not become healthy within 60 seconds" >&2
    exit 1
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${camofoxStateDir} 0700 keewai users -"
    "d ${camofoxStateDir}/cache 0700 keewai users -"
    "d ${camoufoxCacheDir} 0700 keewai users -"
    "d ${camofoxStateDir}/cookies 0700 keewai users -"
    "d ${camofoxStateDir}/profiles 0700 keewai users -"
    "d ${camofoxStateDir}/traces 0700 keewai users -"
    "d ${camofoxStateDir}/uploads 0700 keewai users -"
  ];

  systemd.services.camofox = {
    description = "Camofox Browser (native Nix package)";
    documentation = [ "https://github.com/jo-inc/camofox-browser" ];
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
    ];

    environment = {
      HOME = camofoxStateDir;
      XDG_CACHE_HOME = "${camofoxStateDir}/cache";
      CAMOUFOX_CACHE_DIR = camoufoxCacheDir;
      CAMOUFOX_INSTALL_DIR = camoufoxCacheDir;

      CAMOFOX_PORT = "9377";
      CAMOFOX_BIND_HOST = "127.0.0.1";
      CAMOFOX_COOKIES_DIR = "${camofoxStateDir}/cookies";
      CAMOFOX_PROFILE_DIR = "${camofoxStateDir}/profiles";
      CAMOFOX_TRACES_DIR = "${camofoxStateDir}/traces";
      CAMOFOX_UPLOADS_DIR = "${camofoxStateDir}/uploads";
      CAMOFOX_CRASH_REPORT_ENABLED = "false";

      # Keep startup reproducible: do not fetch the mutable default UBO addon.
      CAMOFOX_DISABLE_DEFAULT_ADDONS = "true";

      # Keep Camoufox and x11vnc available for on-demand noVNC connections.
      # The packaged v1.14.0 fix makes 0 honor upstream's documented "never".
      BROWSER_IDLE_TIMEOUT_MS = "0";

      ENABLE_VNC = "1";
      NOVNC_PORT = "6080";
      VNC_BIND = "127.0.0.1";
      VNC_RESOLUTION = "1920x1080";
    };

    serviceConfig = {
      Type = "exec";
      User = "keewai";
      Group = "users";
      ExecStart = lib.getExe camofoxPackage;
      ExecStartPost = healthCheck;
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "90s";
      TimeoutStopSec = "30s";
      KillMode = "mixed";
      UMask = "0077";
      LimitNOFILE = 65536;

      RuntimeDirectory = "camofox";
      RuntimeDirectoryMode = "0700";

      NoNewPrivileges = true;
      # Xvfb and x11vnc must share the host's /tmp/.X11-unix socket directory.
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [
        camofoxStateDir
        # Camoufox creates launch shims and Xvfb creates X11 sockets here.
        "/tmp"
      ];
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };
  };
}
