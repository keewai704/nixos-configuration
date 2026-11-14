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
  lanBroadcast = "192.168.11.255";
  nginxPort = 8000;
  t3codePort = 3773;
  searxngPort = 8888;
  smartDevices = [
    "/dev/sda"
    "/dev/sdb"
  ];
  storageMountUnit = "srv-storage.mount";
  tailnetOrigin = "https://${tailnetHostname}";

  immichPort = 2283;
  immichBackupRoot = "${immichMediaRoot}/backups";

  citrusWakePort = 3003;

  vaultwardenPort = 8222;
  vaultwardenBackupRoot = "${storageRoot}/server/backups/vaultwarden-nixos";
}
