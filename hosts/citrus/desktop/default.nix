{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  zen-browser-unwrapped =
    (inputs.zen-browser.packages.x86_64-linux.beta-unwrapped.override {
      extraPolicies = {
        RequestedLocales = [
          "ja"
          "en-US"
        ];
        TranslateEnabled = false;
        SearchSuggestEnabled = true;
        Preferences =
          lib.mapAttrs
            (_: Value: {
              inherit Value;
              Status = "default";
            })
            {
              "intl.accept_languages" = "ja,en-US,en";
              "layout.spellcheckDefault" = 0;
              "signon.firefoxRelay.feature" = "disabled";
              "dom.security.https_only_mode" = false;
              "browser.urlbar.suggest.searches" = true;
            };
      };
    }).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          lib_dir=$(echo $out/lib/zen-bin-*)
          chmod u+w $lib_dir $lib_dir/defaults/pref
          cat > $lib_dir/defaults/pref/local-settings.js <<'PREF'
          pref("general.config.filename", "local-settings.cfg");
          pref("general.config.obscure_value", 0);
          PREF
          cat > $lib_dir/local-settings.cfg <<'CFG'
          //
          defaultPref("zen.glance.enabled", false);
          defaultPref("font.default.ja", "sans-serif");
          defaultPref("font.default.x-western", "sans-serif");
          defaultPref("font.name.sans-serif.ja", "Noto Sans CJK JP");
          defaultPref("font.name.sans-serif.x-western", "Noto Sans CJK JP");
          CFG
        '';
      });
  zen-browser = import "${inputs.zen-browser}/wrap-zen.nix" pkgs.wrapFirefox zen-browser-unwrapped {
    icon = "zen-browser";
  };
in
{
  imports = [
    ./modrinth.nix
    ./noctalia.nix
    ./spotifast.nix
    ./steam.nix
    ./sunshine
    ./theme.nix
  ];

  nixpkgs.overlays = [ inputs.nix-meltype.overlays.default ];

  programs.umbriel.enable = true;

  services.greetd.settings.initial_session = {
    command = "${config.programs.umbriel.package}/bin/start-umbriel";
    user = "keewai";
  };

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

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
    pkgs.udev-gothic
  ];
  fonts.fontconfig.defaultFonts.sansSerif = [ "Noto Sans CJK JP" ];

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

  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings.general.renice = 10;
  };

  programs.dconf.enable = true;

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  xdg.mime.defaultApplications = {
    "inode/directory" = "thunar.desktop";
    "text/html" = "zen-beta.desktop";
    "x-scheme-handler/http" = "zen-beta.desktop";
    "x-scheme-handler/https" = "zen-beta.desktop";
  };

  home-manager.users.keewai = {
    imports = [ inputs.nixcord.homeModules.nixcord ];

    xdg.configFile."umbriel/config.toml".source =
      (pkgs.formats.toml { }).generate "umbriel-config.toml"
        {
          include = {
            files = [ "${config.programs.umbriel.package}/share/umbriel/config.toml" ];
            optional.files = [ "noctalia.toml" ];
          };
          output."Dell Inc. AW3926QW CMYQ7K4" = {
            mode = "5120x2160@165";
            vrr = "fullscreen";
            hdr = "auto";
          };
          layout.scrolling.default_extent_fraction = 0.333;
          input.cursor = {
            inherit (config.home-manager.users.keewai.home.pointerCursor) size;
            theme = config.home-manager.users.keewai.home.pointerCursor.name;
          };
          input.focus = {
            follows_mouse = true;
            hover_raises = false;
          };
          effects.preset.glass = {
            kind = "window";
            shader = "${./glass.glsl}";
          };
          window_rule = [
            {
              match.is_focused = false;
              opacity = 0.9;
              window_effect = "glass";
            }
          ];
          keybinds = {
            "Alt+bracketleft" = "spawn noctalia msg brightness-down";
            "Alt+bracketright" = "spawn noctalia msg brightness-up";
            "Mod+V" = {
              action = "spawn noctalia msg panel-toggle clipboard";
              repeat = false;
            };
            "Print" = {
              action = "spawn noctalia msg screenshot-fullscreen all";
              repeat = false;
            };
            "Alt+Print" = {
              action = "spawn noctalia msg screenshot-window";
              repeat = false;
            };
            "Alt+Sys_Req" = {
              action = "spawn noctalia msg screenshot-window";
              repeat = false;
            };
            "Mod+Shift+S" = {
              action = "spawn noctalia msg screenshot-region";
              repeat = false;
            };
          };
        };

    xdg.configFile."kitty/font.conf".text = ''
      font_family UDEV Gothic
    '';

    home.activation.kittyFontInclude = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      kitty_conf="$HOME/.config/kitty/kitty.conf"
      grep -qxsF 'include font.conf' "$kitty_conf" \
        || echo 'include font.conf' | run tee -a "$kitty_conf" > /dev/null
    '';

    programs.gh.settings.browser = lib.mkForce "${lib.getExe' pkgs.systemd "systemd-run"} --user --collect --quiet ${lib.getExe zen-browser}";

    programs.nixcord = {
      enable = true;
      discord.equicord.enable = true;
    };

    programs.mangohud = {
      enable = true;
      settings.toggle_hud = "Home";
    };

    home.packages = [
      pkgs.bitwarden-desktop
      pkgs.ddcutil
      pkgs.kitty
      pkgs.wl-clipboard
      zen-browser
    ];
  };
}
