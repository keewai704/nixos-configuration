{ lib, pkgs, ... }:
let
  bootvine = lib.getExe pkgs.bootvine;
  units = pkgs.runCommand "bootvine-units" { } ''
    systemd=${pkgs.bootvine.src}/bootvine/system-files/systemd
    resume=systemd-hibernate-resume.service.d/bootvine.conf
    for unit in bootvine.service bootvine-shutdown.service $resume; do
      install -Dm644 $systemd/$unit $out/lib/systemd/system/$unit
      substituteInPlace $out/lib/systemd/system/$unit --replace-fail /usr/bin/bootvine ${bootvine}
    done
  '';
in
{
  environment.systemPackages = [ pkgs.bootvine ];

  systemd = {
    packages = [ units ];
    services.bootvine.wantedBy = [ "sysinit.target" ];
    services.bootvine-shutdown.wantedBy = [ "shutdown.target" ];
  };

  boot.initrd.systemd = {
    packages = [ units ];
    storePaths = [ bootvine ];
    services.bootvine.wantedBy = [ "sysinit.target" ];
  };
}
