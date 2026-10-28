{ lib, pkgs, ... }:
let
  inherit (import ./settings.nix) recordings queueRoot serviceDefaults;
  recordingEncoder =
    pkgs.runCommand "recording-encode.py" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        export PYTHONDONTWRITEBYTECODE=1
        python ${./test-recording-encode.py} ${./recording-encode.py}
        install -m444 ${./recording-encode.py} "$out"
      '';
in
{
  orange.healthMonitor.units = [ "tv-recording-encode.service" ];

  systemd.services = {
    tv-recording-encode = {
      description = "Verify and replace completed recording video with HEVC while preserving TS data";
      wantedBy = [ "multi-user.target" ];
      requires = [ "tv-storage-prepare.service" ];
      after = [ "tv-storage-prepare.service" ];
      environment = {
        LIBVA_DRIVER_NAME = "iHD";
        XDG_CACHE_HOME = "/var/cache/tv-recording";
      };
      preStart = ''
        install -d -m 0770 /var/lib/tv-recording/{queue,failed,completed}
      '';
      serviceConfig = serviceDefaults // {
        StateDirectory = "tv-recording";
        StateDirectoryMode = "0750";
        LogsDirectory = "tv-recording";
        CacheDirectory = "tv-recording";
        ReadWritePaths = [ recordings ];
        Nice = 10;
        IOSchedulingClass = "idle";
        CPUQuota = "200%";
        MemoryMax = "2G";
        ExecStart = lib.escapeShellArgs [
          "${pkgs.python3}/bin/python"
          "${recordingEncoder}"
          "--queue"
          queueRoot
          "--recordings"
          recordings
          "--logs"
          "/var/log/tv-recording"
          "--tsreplace"
          "${pkgs.local.tsreplace}/bin/tsreplace"
          "--encoder"
          "${pkgs.local.konomitv.binaries}/QSVEncC/QSVEncC.elf"
          "--ffmpeg"
          "${pkgs.local.konomitv.binaries}/FFmpeg/ffmpeg.elf"
          "--ffprobe"
          "${pkgs.local.konomitv.binaries}/FFmpeg/ffprobe.elf"
        ];
        TimeoutStopSec = "30s";
      };
    };
  };
}
