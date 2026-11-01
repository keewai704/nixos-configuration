{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../settings.nix)
    jellyfinPort
    storageMountUnit
    storageRoot
    tailnetHostname
    ;
  mkProxyLocation = import ../web/proxy.nix;
  inherit (config.services.jellyfin) configDir;

  networkXml = pkgs.writeText "network.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <BaseUrl>/jellyfin</BaseUrl>
      <EnableHttps>false</EnableHttps>
      <RequireHttps>false</RequireHttps>
      <InternalHttpPort>${toString jellyfinPort}</InternalHttpPort>
      <PublicHttpPort>${toString jellyfinPort}</PublicHttpPort>
      <AutoDiscovery>false</AutoDiscovery>
      <EnableUPnP>false</EnableUPnP>
      <EnableIPv4>true</EnableIPv4>
      <EnableIPv6>false</EnableIPv6>
      <EnableRemoteAccess>true</EnableRemoteAccess>
      <LocalNetworkSubnets>
        <string>127.0.0.1/32</string>
        <string>100.64.0.0/10</string>
      </LocalNetworkSubnets>
      <LocalNetworkAddresses>
        <string>127.0.0.1</string>
      </LocalNetworkAddresses>
      <KnownProxies>
        <string>127.0.0.1</string>
      </KnownProxies>
      <IgnoreVirtualInterfaces>true</IgnoreVirtualInterfaces>
      <EnablePublishedServerUriByRequest>true</EnablePublishedServerUriByRequest>
    </NetworkConfiguration>
  '';

  installNetworkConfig = pkgs.writeShellScript "jellyfin-network-config" ''
    ${pkgs.coreutils}/bin/install -D --mode 0600 ${networkXml} ${lib.escapeShellArg "${configDir}/network.xml"}
  '';
in
{
  orange.healthMonitor = {
    units = [ "jellyfin.service" ];
    loopbackPorts = [ jellyfinPort ];
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];

  services.jellyfin = {
    enable = true;
    forceEncodingConfig = true;
    hardwareAcceleration = {
      enable = true;
      type = "qsv";
      device = "/dev/dri/renderD128";
    };
    transcoding = {
      enableHardwareEncoding = true;
      enableIntelLowPowerEncoding = true;
      throttleTranscoding = true;
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        hevc10bit = true;
        mpeg2 = true;
        vc1 = true;
        vp8 = true;
        vp9 = true;
        av1 = true;
      };
      hardwareEncodingCodecs.hevc = true;
    };
  };

  systemd.services.jellyfin = {
    requires = [ storageMountUnit ];
    after = [ storageMountUnit ];
    unitConfig.RequiresMountsFor = [ storageRoot ];
    serviceConfig.ExecStartPre = [ installNetworkConfig ];
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations."/jellyfin" =
    mkProxyLocation jellyfinPort "";
}
