{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.callPackage ../../../pkgs/impasto { inherit (inputs) impasto; };
  state = "${config.xdg.stateHome}/quickshell";
  wallpaper = "${config.xdg.dataHome}/wallpapers/surface-laptop-ultra-dark.png";
  settings = pkgs.writeText "impasto-settings.json" (
    builtins.toJSON {
      barStyle = "grouped";
      barHeight = 32;
      barHidden = false;
      barLeft = [
        "workspaces"
        "overview"
        "split"
        "launcher"
      ];
      barRight = [
        "notifications"
        "network"
        "bluetooth"
        "volume"
        {
          id = "battery";
          figure = "on";
        }
        "split"
        {
          id = "claude";
          shape = "ring";
          figure = "off";
        }
        {
          id = "codex";
          shape = "ring";
          figure = "off";
        }
      ];
      chipShape = "icon";
      chipFigure = "off";
      workspaceStyle = "dots";
      workspaceCount = 5;
      clockFormat = "HH:mm";
      clockShowsDate = false;
      clockShowsSeconds = false;
      desktopHidden = true;
      barMargin = 6;
      barSides = "capsule";
      barFullWidth = false;
      barShadow = false;
      islandAttached = true;
      surfaceStyle = "classic";
      desktopWidgets = [ ];
      idleLock = 0;
      idleScreen = 0;
      idleSuspend = 0;
    }
  );
  afterStart = pkgs.writeShellScript "impasto-after-start" ''
    for _ in $(seq 60); do
      if wallpapers=$(${package}/bin/impastoctl wallpaper list 2>/dev/null) &&
          ${lib.getExe pkgs.jq} -e 'type == "object" and has("current")' <<<"$wallpapers" >/dev/null; then
        current=$(${lib.getExe pkgs.jq} -r '.current // ""' <<<"$wallpapers")
        case "$current" in
          ""|${lib.escapeShellArg "${config.xdg.dataHome}/wallpapers/surface-laptop-ultra-dark.jpeg"})
            ${package}/bin/impastoctl wallpaper set ${lib.escapeShellArg wallpaper}
            ;;
        esac
        ${pkgs.hyprland}/bin/hyprctl reload
        exit 0
      fi
      sleep 0.5
    done
    echo "impasto: timed out waiting to initialize the wallpaper" >&2
    exit 1
  '';
in
{
  imports = [ ./impasto-theme.nix ];

  programs.quickshell = {
    enable = true;
    inherit package;
    systemd.enable = true;
  };
  services.awww.enable = true;

  home.packages = [
    pkgs.inter
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.papirus-icon-theme
  ];
  fonts.fontconfig.enable = true;
  xdg.dataFile = {
    "wallpapers" = {
      source = "${package}/share/impasto/wallpapers";
      recursive = true;
    };
    "wallpapers/surface-laptop-ultra-dark.png".source = config.stylix.image;
  };

  systemd.user.services.quickshell = {
    Unit = {
      Description = lib.mkForce "Impasto desktop shell";
      After = [ "awww.service" ];
      Wants = [ "awww.service" ];
      PartOf = [ config.programs.quickshell.systemd.target ];
    };
    Service = {
      ExecStartPre = "${package}/libexec/impasto-apply-settings ${settings} ${lib.escapeShellArg state}";
      ExecStartPost = "-${afterStart}";
      RestartSec = 2;
    };
  };
}
