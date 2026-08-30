let
  storageRoot = "/srv/storage";
  immichMediaRoot = "${storageRoot}/Pictures";
  localBackupRoot = "${storageRoot}/server/backups/orange-local";
  tailnetHostname = "orange.tail1e65cd.ts.net";
in
{
  inherit
    immichMediaRoot
    localBackupRoot
    storageRoot
    tailnetHostname
    ;

  hostName = "orange";
  lanInterface = "enp2s0";
  nginxPort = 8000;
  smartDevices = [
    "/dev/sda"
    "/dev/sdb"
  ];
  storageMountUnit = "srv-storage.mount";
  tailnetOrigin = "https://${tailnetHostname}";

  immichPort = 2283;
  immichBackupRoot = "${immichMediaRoot}/backups";

  vaultwardenPort = 8222;
  vaultwardenBackupRoot = "${storageRoot}/server/backups/vaultwarden-nixos";

  minecraftPort = 25565;
  minecraftDataDir = "/var/lib/minecraft";

  camofoxApiPort = 9377;
  camofoxNoVncPort = 6080;
  camofoxVncBackendPort = 5900;
  camofoxVncActivationPort = 5901;
}
