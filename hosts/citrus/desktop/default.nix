{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./airplay.nix
    ./anime-game-launcher
    ./discord-phoenix.nix
    ./discord.nix
    ./fcitx5-theme.nix
    ./heroic.nix
    ./impasto
    ./mangohud.nix
    ./modrinth.nix
    ./pi-theme.nix
    ./steam.nix
    ./sunshine
    ./theme.nix
    ./zen-browser
  ];

  nixpkgs.overlays = [ inputs.nix-meltype.overlays.default ];

  _module.args.updateJson = lib.getExe (
    pkgs.writeShellApplication {
      name = "update-json";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ];
      text = ''
        file=$1
        shift
        merged=$(mktemp "$file.XXXXXX")
        trap 'rm -f "$merged"' EXIT
        jq "$@" "$file" >"$merged"
        mv "$merged" "$file"
      '';
    }
  );

  hardware.i2c.enable = true;
  users.users.keewai.extraGroups = [
    "gamemode"
    "i2c"
  ];

  services.keyd = {
    enable = true;
    keyboards.su75-ultra = {
      ids = [ "k:1ca6:3007" ];
      settings.global.disable_modifier_guard = 1;
    };
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = [ (pkgs.fcitx5-meltype.override { meltype = pkgs.meltype-bin; }) ];
    fcitx5.waylandFrontend = true;
    fcitx5.settings = {
      globalOptions."Hotkey/TriggerKeys"."0" = "Alt+grave";
      inputMethod = {
        "Groups/0".Name = "Default";
        "Groups/0"."Default Layout" = "us";
        "Groups/0".DefaultIM = "keyboard-us";
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "meltype";
      };
    };
  };

  environment.variables.QT_IM_MODULES = "wayland;fcitx";
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  boot.kernelModules = [ "ntsync" ];

  powerManagement.cpuFreqGovernor = "powersave";

  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings.general = {
      renice = 10;
      defaultgov = "powersave";
      desiredgov = "performance";
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";

  home-manager.users.keewai = {
    programs.kitty.enable = true;

    home.packages = [
      pkgs.bitwarden-desktop
      pkgs.ddcutil
      pkgs.jq
      pkgs.wl-clipboard
    ];
  };
}
