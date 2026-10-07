{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.t3code-server;
  system = pkgs.stdenv.hostPlatform.system;
  package = pkgs.callPackage ../../../pkgs/t3code/server.nix {
    release = inputs.t3code-release;
    claude-code = inputs.claude-code.packages.${system}.default;
    codex = inputs.codex-cli.packages.${system}.default;
  };
  pair = pkgs.writeShellApplication {
    name = "t3code-pair";
    runtimeInputs = [ package ];
    text = ''
      exec t3 auth pairing create --base-url ${lib.escapeShellArg cfg.publicUrl} "$@"
    '';
  };
in
{
  options.services.t3code-server = {
    enable = lib.mkEnableOption "T3 Code nightly server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      package
      pair
    ];

    systemd.user.services.t3code = {
      Unit = {
        Description = "T3 Code nightly server";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${package}/bin/t3 serve --host 127.0.0.1 --port ${toString cfg.port}";
        WorkingDirectory = config.home.homeDirectory;
        Environment = [
          "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
          "T3CODE_HOME=${config.home.homeDirectory}/.t3"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 60;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
