{ ... }:

let
  camofoxStateDir = "/home/keewai/.local/share/camofox";
in
{
  # Run the browser as an unprivileged, lingering user so the service remains
  # available to Hermes without granting the container root on the host.
  users.users.keewai = {
    uid = 1000;
    linger = true;
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${camofoxStateDir} 0700 keewai users -"
  ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers.camofox = {
      # Camofox v1.14.0, linux/amd64. The digest prevents a mutable registry
      # tag from changing the executable code on a later rebuild.
      image = "ghcr.io/jo-inc/camofox-browser@sha256:86c79eed8a6b3a78859f73bc70d6003c5566b85e969354ec454524b28197ffce";
      pull = "missing";

      podman = {
        user = "keewai";
        sdnotify = "healthy";
      };

      ports = [
        # Both the control API and the optional live browser view remain local.
        # Use an SSH tunnel when noVNC access is needed remotely.
        "127.0.0.1:9377:9377"
        "127.0.0.1:6080:6080"
      ];

      volumes = [ "${camofoxStateDir}:/data" ];

      environment = {
        CAMOFOX_PORT = "9377";
        # The container must listen on its own network interface; the host-side
        # port publication above still restricts access to loopback.
        CAMOFOX_BIND_HOST = "0.0.0.0";

        CAMOFOX_COOKIES_DIR = "/data/cookies";
        CAMOFOX_PROFILE_DIR = "/data/profiles";
        CAMOFOX_TRACES_DIR = "/data/traces";
        CAMOFOX_UPLOADS_DIR = "/data/uploads";

        CAMOFOX_CRASH_REPORT_ENABLED = "false";
        MAX_OLD_SPACE_SIZE = "512";

        ENABLE_VNC = "1";
        NOVNC_PORT = "6080";
        VNC_BIND = "0.0.0.0";
        VNC_RESOLUTION = "1920x1080";
      };

      extraOptions = [
        "--shm-size=2g"
        "--health-cmd=curl --fail --silent http://127.0.0.1:9377/health"
        "--health-interval=10s"
        "--health-start-period=60s"
        "--health-timeout=5s"
        "--health-retries=12"
      ];
    };
  };
}
