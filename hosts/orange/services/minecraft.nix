{
  lib,
  pkgs,
  ...
}:

let
  inherit (import ../settings.nix)
    lanInterface
    minecraftDataDir
    minecraftPort
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

  systemd.services.minecraft = {
    description = "Minecraft ${minecraftVersion} Fabric server";
    documentation = [ "https://fabricmc.net/use/server/" ];
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    preStart = ''
      install -d -m 0755 ${dataDir}/mods ${dataDir}/logs
      ln -sfn ${fabricLauncherProperties} ${dataDir}/fabric-server-launcher.properties
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
