let
  inherit (import ../settings.nix) lanInterface lanMac;
in
{
  systemd.network.links."40-${lanInterface}" = {
    matchConfig.MACAddress = lanMac;
    linkConfig = {
      Name = lanInterface;
      WakeOnLan = "magic";
    };
  };
}
