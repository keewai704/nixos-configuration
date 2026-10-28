let
  inherit (import ../../settings.nix) storageRoot storageMountUnit;
  televisionRoot = "${storageRoot}/KonomiTV";
  tuners = import ./tuners.nix;
in
{
  inherit
    storageRoot
    storageMountUnit
    televisionRoot
    tuners
    ;
  recordings = "${televisionRoot}/Recordings";
  captures = "${televisionRoot}/Captures";
  queueRoot = "/var/lib/tv-recording/queue";
  keepAliveSeconds = 120;
  edcbPort = 4510;
  konomitvPort = 7000;
  mirakcPort = 40772;
  receiverUnits = map (tuner: "torne-receiver-${tuner.id}.service") tuners;
  tvEnvironment = {
    PCSCLITE_CSOCK_NAME = "/run/pcscd/pcscd.comm";
  };
  serviceDefaults = {
    User = "tv";
    Group = "tv";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    Restart = "on-failure";
    RestartSec = "5s";
    UMask = "0007";
  };
}
