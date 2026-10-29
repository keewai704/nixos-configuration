{
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../settings.nix)
    lanInterface
    minecraftDataDir
    minecraftLiveBackupRoot
    minecraftPort
    storageMountUnit
    ;
  dataDir = minecraftDataDir;
  minecraftVersion = "26.3";
  fabricLoaderVersion = "0.19.5";
  fabricInstallerVersion = "1.1.2";

  fabricServerLauncher = pkgs.fetchurl {
    pname = "fabric-server-launcher";
    version = "mc.${minecraftVersion}-loader.${fabricLoaderVersion}-installer.${fabricInstallerVersion}";
    url = "https://meta.fabricmc.net/v2/versions/loader/${minecraftVersion}/${fabricLoaderVersion}/${fabricInstallerVersion}/server/jar";
    hash = "sha256-C1atVNdiFy6Lh0jkZ/WE8HHk3t7Nk9wzbPLGiDfnkL4=";
  };

  minecraftServer = pkgs.fetchurl {
    pname = "minecraft-server";
    version = minecraftVersion;
    url = "https://piston-data.mojang.com/v1/objects/33680f5f2ac32864d6d7cf5e56a705fdb3e05f4c/server.jar";
    hash = "sha1-M2gPXyrDKGTW189eVqcF/bPgX0w=";
  };

  mods = {
    fabric-api = pkgs.fetchurl {
      pname = "fabric-api";
      version = "0.161.0+26.3";
      url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/bNnaTiuM/fabric-api-0.161.0%2B26.3.jar";
      hash = "sha512-7Wslhtb94R/ehHL1pSfFHpm2cCbkb5TUv9hefijOXuKZFz7hatV2zrUfOfmNMKgRCGpt6xqGpSSFnMFuEtoQnQ==";
    };

    justenoughbackups = pkgs.fetchurl {
      pname = "justenoughbackups";
      version = "1.2.0.9+26.3";
      url = "https://cdn.modrinth.com/data/ctV8T1ZK/versions/F1HJvFXY/justenoughbackups-1.2.0.9%2B26.3.jar";
      hash = "sha512-8osxzMMqIN0E1QcHpvqSfgLszdsEr6VBl/enrVTxklAEe9l6Iore9rw/7V477RjGhrbK/X9ViU4pgG5K33ct4g==";
    };

    lithium = pkgs.fetchurl {
      pname = "lithium-fabric";
      version = "0.26.0+mc26.3";
      url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/UnOXzpHc/lithium-fabric-0.26.0%2Bmc26.3.jar";
      hash = "sha512-uXYJup/f8qF/XR3yNgBCCkKKtlsrSz/gxWEKpxzFNazhGeRkd2mPfC7AoW/nRg0X1vS8i5oaosIWoo6pt4W48g==";
    };

    krypton = pkgs.fetchurl {
      pname = "krypton";
      version = "0.3.1";
      url = "https://cdn.modrinth.com/data/fQEb0iXm/versions/5WeL0Nkz/krypton-0.3.1.jar";
      hash = "sha512-uNmvNM0AUEk6+4piMsuPeF2qnYiHtwRfbmpTxrubX/xDGP2bA0epQOrP66R3PxDLgK4L4eec5MGIj5btoh5WTg==";
    };

    scalablelux = pkgs.fetchurl {
      pname = "scalablelux-fabric";
      version = "0.2.1+fabric.2b08348";
      url = "https://cdn.modrinth.com/data/Ps1zyz6x/versions/FuGn0NlI/ScalableLux-0.2.1%2Bfabric.2b08348-all.jar";
      hash = "sha512-Rsw99YrScj+3+SXaDjgOIkgeFc6w5h+9eUf0jSkC56Z65NLSLfT6q04xQMz3mqn1nZHsmVm9bir78PuQlwoC/A==";
    };
  };

  fabricLauncherProperties = pkgs.writeText "fabric-server-launcher.properties" ''
    serverJar=${minecraftServer}
  '';

  backupConfig = pkgs.writeText "justenoughbackups.json" (
    builtins.toJSON {
      backupMode = "FULL";
      backupOnServerStart = false;
      backupOnServerStop = false;
      automaticSchedule = {
        full.enabled = false;
        partial.enabled = false;
        differential.enabled = false;
      };
      integrityMode = "STRICT";
      threadCount = 2;
      backupDirectory = minecraftLiveBackupRoot;
      retention.full = 14;
      remoteStorage.enabled = false;
    }
  );

  jvmArgs = [
    "-Xms2G"
    "-Xmx4G"
    "-XX:+UnlockExperimentalVMOptions"
    "-XX:+DisableExplicitGC"
    "-XX:G1NewSizePercent=30"
    "-XX:G1MaxNewSizePercent=40"
    "-XX:G1HeapRegionSize=8M"
    "-XX:G1ReservePercent=20"
    "-XX:G1MixedGCCountTarget=4"
    "-XX:InitiatingHeapOccupancyPercent=15"
    "-XX:G1MixedGCLiveThresholdPercent=90"
    "-XX:G1RSetUpdatingPauseTimePercent=5"
    "-XX:SurvivorRatio=32"
    "-XX:+PerfDisableSharedMem"
    "-XX:MaxTenuringThreshold=1"
    "-XX:+ExitOnOutOfMemoryError"
    "-Djava.awt.headless=true"
    "-Xlog:gc*:logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M"
  ];
in
{
  orange.healthMonitor.units = [ "minecraft.service" ];

  users = {
    groups.minecraft = { };
    users.minecraft = {
      isSystemUser = true;
      group = "minecraft";
      home = dataDir;
    };
  };

  networking.firewall.interfaces = {
    ${lanInterface}.allowedTCPPorts = [ minecraftPort ];
    tailscale0.allowedTCPPorts = [ minecraftPort ];
  };

  systemd.sockets.minecraft = {
    bindsTo = [ "minecraft.service" ];
    socketConfig = {
      ListenFIFO = "/run/minecraft.stdin";
      SocketMode = "0600";
      SocketUser = "minecraft";
      SocketGroup = "minecraft";
      RemoveOnStop = true;
      FlushPending = true;
    };
  };

  systemd.services.minecraft-backup-prepare = {
    description = "Prepare Minecraft live backup storage";
    requires = [ storageMountUnit ];
    after = [ storageMountUnit ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 0700 -o minecraft -g minecraft ${minecraftLiveBackupRoot}
    '';
  };

  systemd.services.minecraft = {
    description = "Minecraft ${minecraftVersion} Fabric server";
    documentation = [ "https://fabricmc.net/use/server/" ];
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [
      "minecraft.socket"
      "minecraft-backup-prepare.service"
    ];
    after = [
      "network-online.target"
      "minecraft.socket"
      "minecraft-backup-prepare.service"
    ];

    preStart = ''
      install -d -m 0755 ${dataDir}/mods ${dataDir}/logs ${dataDir}/config
      install -m 0600 ${backupConfig} ${dataDir}/config/justenoughbackups.json
      ln -sfn ${fabricLauncherProperties} ${dataDir}/fabric-server-launcher.properties
      ln -sfn ${mods.fabric-api} ${dataDir}/mods/fabric-api.jar
      ln -sfn ${mods.justenoughbackups} ${dataDir}/mods/justenoughbackups.jar
      ln -sfn ${mods.lithium} ${dataDir}/mods/lithium.jar
      ln -sfn ${mods.krypton} ${dataDir}/mods/krypton.jar
      ln -sfn ${mods.scalablelux} ${dataDir}/mods/scalablelux.jar
      printf 'eula=true\n' > ${dataDir}/eula.txt

      if [ ! -e ${dataDir}/server.properties ]; then
        printf 'motd=Minecraft ${minecraftVersion} Fabric server\nserver-port=${toString minecraftPort}\n' \
          > ${dataDir}/server.properties
      else
        sed -i -E 's/^motd=Minecraft [0-9]+(\.[0-9]+)* Fabric server$/motd=Minecraft ${minecraftVersion} Fabric server/' \
          ${dataDir}/server.properties
      fi
    '';

    serviceConfig = {
      User = "minecraft";
      Group = "minecraft";
      WorkingDirectory = dataDir;
      StateDirectory = "minecraft";
      StandardInput = "socket";
      StandardOutput = "journal";
      StandardError = "journal";
      UMask = "0077";
      ReadWritePaths = [ minecraftLiveBackupRoot ];
      ExecStart = lib.escapeShellArgs (
        [
          "${pkgs.jdk25_headless}/bin/java"
        ]
        ++ jvmArgs
        ++ [
          "-jar"
          fabricServerLauncher
          "nogui"
        ]
      );
      Restart = "on-failure";
      RestartSec = 10;
      KillSignal = "SIGINT";
      TimeoutStopSec = 120;
      SuccessExitStatus = [
        "130"
        "143"
      ];
      LimitNOFILE = 1048576;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };
}
