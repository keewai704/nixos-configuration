{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  zen-browser = inputs.zen-browser;
  sineModule = import (
    builtins.toFile "sine.nix" (
      builtins.replaceStrings
        [ ''listed(.fork; "zen")'' ''listed(.notFork; "zen")'' ]
        [ ''listed(.fork; "firefox")'' ''listed(.notFork; "firefox")'' ]
        (builtins.readFile "${zen-browser}/hm-module/sine.nix")
    )
  );
  sineSources = (lib.importJSON "${zen-browser}/sources.json").addons.sine;
  mkSinePack =
    { }:
    {
      manager = pkgs.fetchFromGitHub {
        inherit (sineSources.manager)
          owner
          repo
          rev
          hash
          ;
      };
      bootloader = pkgs.fetchFromGitHub {
        inherit (sineSources.bootloader)
          owner
          repo
          rev
          hash
          ;
      };
    };
  sinePack = mkSinePack { };

  defaultPrefs = {
    "sidebar.revamp" = true;
    "sidebar.verticalTabs" = true;
    "layout.css.backdrop-filter.enabled" = true;
    "layout.css.backdrop-filter.force-enabled" = true;
    "userChromeJS.persistent_domcontent_callback" = true;
    "natsumi.theme.icons" = "lucide";
    "natsumi.theme.single-toolbar" = true;
    "natsumi.tabs.new-tab-on-top" = true;
  };

  firefox =
    (pkgs.firefox.override {
      nativeMessagingHosts = [
        (pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/pywalfox.json" (
          builtins.toJSON {
            name = "pywalfox";
            description = "Noctalia Firefox theme native messaging host";
            path = lib.getExe config.programs.noctalia.package;
            type = "stdio";
            allowed_extensions = [ "pywalfox@frewacom.org" ];
          }
        ))
      ];
      extraPolicies.ExtensionSettings =
        lib.mapAttrs
          (_: slug: {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
          })
          {
            "pywalfox@frewacom.org" = "pywalfox";
            "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
          };
      extraPrefs = lib.concatStrings (
        lib.mapAttrsToList (
          name: value: "defaultPref(${builtins.toJSON name}, ${builtins.toJSON value});\n"
        ) defaultPrefs
      );
    }).overrideAttrs
      (old: {
        buildCommand = old.buildCommand + ''
          libDir=$out/lib/firefox
          chmod u+w $libDir/mozilla.cfg $libDir/defaults/pref/autoconfig.js
          echo 'pref("general.config.sandbox_enabled", false);' >> $libDir/defaults/pref/autoconfig.js
          cat ${zen-browser}/hm-module/sine-default-prefs.js ${sinePack.bootloader}/program/config.js >> $libDir/mozilla.cfg
        '';
      });

  profile = "default";
in
{
  home-manager.users.keewai =
    { config, ... }:
    let
      sine = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          (sineModule { inherit mkSinePack; })
          {
            options = {
              home.file = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
              programs.zen-browser = {
                enable = lib.mkEnableOption "";
                profilesPath = lib.mkOption { type = lib.types.str; };
                activationFragments = lib.mkOption {
                  type = lib.types.attrsOf (lib.types.listOf lib.types.anything);
                  default = { };
                };
                profiles = lib.mkOption {
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options = {
                        path = lib.mkOption { type = lib.types.str; };
                        settings = lib.mkOption {
                          type = lib.types.attrsOf lib.types.anything;
                          default = { };
                        };
                        presets.managedPrefNames = lib.mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [ ];
                        };
                      };
                    }
                  );
                };
              };
            };
            config.programs.zen-browser = {
              enable = true;
              profilesPath = "${config.home.homeDirectory}/${config.programs.firefox.profilesPath}";
              profiles.${profile} = {
                path = profile;
                sine = {
                  enable = true;
                  mods = [
                    "context-menu-icons"
                    "ff-better-findbar"
                    "natsumi-browser"
                  ];
                };
              };
            };
          }
        ];
      };
    in
    {
      programs.firefox = {
        enable = true;
        package = null;
        profiles.${profile} = {
          id = 0;
          isDefault = true;
          inherit (sine.config.programs.zen-browser.profiles.${profile}) settings;
        };
      };

      home.packages = [ firefox ];
      home.file = sine.config.home.file;
      home.activation.firefoxSineMods = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStrings (
          fragment: fragment.text
        ) sine.config.programs.zen-browser.activationFragments.${profile}
      );
    };
}
