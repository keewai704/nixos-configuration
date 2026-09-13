{ lib, pkgs, ... }:
let
  inherit (import ../settings.nix) smartDevices;

  smartSelfTest =
    testType:
    pkgs.writeShellApplication {
      name = "orange-smart-${testType}";
      runtimeInputs = with pkgs; [ smartmontools ];
      text = ''
        for device in ${lib.escapeShellArgs smartDevices}; do
          [[ -b "$device" ]] || {
            echo "Missing block device: $device" >&2
            exit 1
          }
          smartctl --test=${testType} "$device"
        done
      '';
    };

in
{
  systemd.services = {
    orange-smart-short = {
      description = "Start weekly SMART short self-tests";
      startAt = "Sun *-*-* 06:50:00";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (smartSelfTest "short");
      };
    };

    orange-smart-long = {
      description = "Start monthly SMART long self-tests";
      startAt = "*-*-01 07:30:00";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (smartSelfTest "long");
      };
    };
  };
}
