{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../settings.nix) recordings queueRoot serviceDefaults;
  recordingEncoder =
    pkgs.runCommand "recording-encode.py" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        export PYTHONDONTWRITEBYTECODE=1
        python ${./test-worker.py} ${./worker.py}
        install -m444 ${./worker.py} "$out"
      '';
  preservingMuxer = pkgs.writeShellScript "recording-tsreplace" ''
    exec ${pkgs.python3}/bin/python ${recordingEncoder} mux \
      --tsreplace ${pkgs.local.tsreplace}/bin/tsreplace \
      --ffprobe ${pkgs.local.konomitv.binaries}/FFmpeg/ffprobe.elf "$@"
  '';
in
{
  system.extraDependencies = [ inputs.amatsukaze-releases.outPath ];
  orange.healthMonitor.units = [ "tv-recording-encode.service" ];

  systemd.services = {
    tv-recording-encode = {
      description = "Analyze recordings, remove station logos, and verify adaptive HEVC replacement";
      wantedBy = [ "multi-user.target" ];
      requires = [ "tv-storage-prepare.service" ];
      after = [ "tv-storage-prepare.service" ];
      environment = {
        LIBVA_DRIVER_NAME = "iHD";
        XDG_CACHE_HOME = "/var/cache/tv-recording";
      };
      preStart = ''
        install -d -m 0770 /var/lib/tv-recording/{queue,failed,completed,logos} /var/cache/tv-recording/work
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
        MemoryMax = "4G";
        ExecStart = lib.escapeShellArgs [
          "${pkgs.python3}/bin/python"
          "${recordingEncoder}"
          "--queue"
          queueRoot
          "--recordings"
          recordings
          "--logs"
          "/var/log/tv-recording"
          "--amatsukaze"
          "${pkgs.local.amatsukaze}/bin/AmatsukazeCLI"
          "--logo-generator"
          "${pkgs.local.amatsukaze}/bin/AmatsukazeGenLogo"
          "--muxer"
          "${preservingMuxer}"
          "--filter"
          "${./adaptive.avs}"
          "--work"
          "/var/cache/tv-recording/work"
          "--logos"
          "/var/lib/tv-recording/logos"
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
