{
  camofoxSharedUserId,
  lib,
  pkgs,
  ...
}:

let
  camofoxStateDir = "/home/keewai/.local/share/camofox";
  camoufoxCacheDir = "${camofoxStateDir}/cache/camoufox";
  vncBackendPort = 5900;
  vncActivationPort = 5901;

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

  sharedSessionBody = builtins.toJSON {
    userId = camofoxSharedUserId;
    sessionKey = "default";
    # Camofox only permits HTTP(S) for new tabs. Its local status endpoint is
    # deterministic, avoids an external dependency, and gives noVNC a page.
    url = "http://127.0.0.1:9377/";
  };

  ensureSharedSession = pkgs.writeShellApplication {
    name = "camofox-ensure-shared-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.netcat-openbsd
    ];
    text = ''
      api_url=http://127.0.0.1:9377
      shared_user_id=${lib.escapeShellArg camofoxSharedUserId}

      tabs_json="$(
        curl \
          --fail \
          --silent \
          --show-error \
          --max-time 10 \
          --get \
          --data-urlencode "userId=$shared_user_id" \
          "$api_url/tabs"
      )"

      if ! jq --exit-status '(.tabs // []) | length > 0' <<<"$tabs_json" >/dev/null; then
        curl \
          --fail \
          --silent \
          --show-error \
          --max-time 90 \
          --header 'Content-Type: application/json' \
          --data ${lib.escapeShellArg sharedSessionBody} \
          "$api_url/tabs" \
          >/dev/null
      fi

      for _ in $(seq 1 120); do
        if nc -z -w 1 127.0.0.1 ${toString vncBackendPort}; then
          exit 0
        fi
        sleep 0.25
      done

      echo "Camofox did not expose VNC port ${toString vncBackendPort} within 30 seconds" >&2
      exit 1
    '';
  };
in
{
  systemd = {
    tmpfiles.rules = [
      "d ${camofoxStateDir} 0700 keewai users -"
      "d ${camofoxStateDir}/cache 0700 keewai users -"
      "d ${camoufoxCacheDir} 0700 keewai users -"
      "d ${camofoxStateDir}/cookies 0700 keewai users -"
      "d ${camofoxStateDir}/profiles 0700 keewai users -"
      "d ${camofoxStateDir}/traces 0700 keewai users -"
      "d ${camofoxStateDir}/uploads 0700 keewai users -"
    ];

    services.camofox = {
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
        CAMOFOX_BROWSER_PREWARM = "false";

        # Keep Camoufox and x11vnc available for on-demand noVNC connections.
        # The packaged v1.14.0 fix makes 0 honor upstream's documented "never".
        BROWSER_IDLE_TIMEOUT_MS = "0";

        ENABLE_VNC = "1";
        VNC_PORT = toString vncBackendPort;
        NOVNC_PORT = "6080";
        NOVNC_TARGET_PORT = toString vncActivationPort;
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
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    # websockify connects here only after a noVNC client upgrades to WebSocket.
    # Socket activation holds that connection while ExecStartPre creates the
    # shared Camofox tab and waits for x11vnc, then proxies the same RFB stream.
    sockets.camofox-vnc-activation = {
      description = "Lazy Camofox VNC activation socket";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "127.0.0.1:${toString vncActivationPort}";
        NoDelay = true;
      };
    };

    services.camofox-vnc-activation = {
      description = "Start the shared Camofox session for noVNC";
      requires = [
        "camofox.service"
        "camofox-vnc-activation.socket"
      ];
      after = [
        "camofox.service"
        "camofox-vnc-activation.socket"
      ];
      serviceConfig = {
        Type = "notify";
        User = "keewai";
        Group = "users";
        ExecStartPre = lib.getExe ensureSharedSession;
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=30s 127.0.0.1:${toString vncBackendPort}";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
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
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
