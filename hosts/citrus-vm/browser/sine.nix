{ lib, pkgs, ... }:

let
  sineVersion = "2.3.3";
  sineBootloaderVersion = "0.1.4";
  sineStoreRevision = "7df9388eb064254ee6f26733404b9b604c9a485f";

  sineEngine = pkgs.fetchurl {
    url = "https://github.com/CosmoCreeper/Sine/releases/download/v${sineVersion}/engine.zip";
    hash = "sha256-yYvo4CNOjE1bQdwne9IBo2Wi3MQY3LqC1HSdJ6ZKPWU=";
  };
  sineBootloaderProfile = pkgs.fetchurl {
    url = "https://github.com/sineorg/bootloader/releases/download/v${sineBootloaderVersion}/profile.zip";
    hash = "sha256-KFs9WJzJefEfAcnHdBC3F2lMzE8yzBywi9bYkJ+5jgA=";
  };
  sineMarketplace = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/sineorg/store/${sineStoreRevision}/marketplace.json";
    hash = "sha256-kclBRgvKr2t32OtarJ5FJTSha1Z7yfvtPirHNagRvPg=";
  };

  sineMods = {
    "3c8ebf69-1042-49b1-8f08-9178f9490659" = {
      version = "1.0.4";
      hash = "sha256-lpH3nR20U0aD2D3GdOERQB7zdXpWYlcsbpT4FkgcoxM=";
    };
    "42b8c4ac-76d5-4521-9917-2e478931ee53" = {
      version = "2.0.0";
      hash = "sha256-QXHEQ1n935pV2j52tbvBUC7oo7thuqlDXvaOqWO3Pos=";
    };
    "context-menu-icons" = {
      version = "2.7.4.3";
      hash = "sha256-5FHecb5mxeMjUdrbXc7KXGtb7wyGkx7oqd4fLLMJCaQ=";
    };
    "e9dae25b-2ddd-4245-8581-a6dcf6d35b82" = {
      version = "2.0.3";
      hash = "sha256-WjtdaYB3pwoR6ipRU9qiFRmz4NsE6OGKsqtV7mggkm4=";
    };
    "f966100a-4fed-4df5-a082-f001c5bd654e" = {
      version = "2.9.1";
      hash = "sha256-kFOahZFlqHwzKkN78eKfIruiQAxWdS7DIDtCkoYqFnM=";
    };
    "natsumi-browser" = {
      version = "6.12.1";
      hash = "sha256-XEFSlYl9mN7PnHxWU1ATxN6whQFJMBmhPVHE1zOPgb0=";
    };
  };
  sineModSources = lib.mapAttrs (
    id: metadata:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/sineorg/store/${sineStoreRevision}/mods/${id}/mod.zip";
      inherit (metadata) hash;
    }
  ) sineMods;
  sineModIds = lib.attrNames sineMods;
  sineModVersions = lib.mapAttrs (_: metadata: metadata.version) sineMods;
  # Sine 2.3.3 creates these defaults only after its settings pane opens.
  # Seed them as unlocked defaults so every requested mod is active on the
  # first restart while remaining customizable in Sine's UI.
  sineModDefaultPreferences = {
    "cmi-Switch-Gecko-Branch" = 0;
    "mod.compacttpr.customblur" = "5px";
    "mod.compacttpr.customcolor" = "rgba(23, 23, 26, 1)";
    "mod.compacttpr.leftsidebarheight" = "80%";
    "mod.compacttpr.leftsidebaronlycollapsed" = true;
    "mod.compacttpr.transparentvalue" = "15%";
    "mod.compacttpr.usecompacttransparent" = true;
    "mod.compacttpr.usefromzen" = true;
    "mod.forkedtidypopup.hovercolor.dark" = "rgba(87,65,50,255)";
    "mod.forkedtidypopup.hovercolor.light" = "rgba(243,202,176,255)";
    "mod.forkedtidypopup.keepdividers" = true;
    "mod.forkedtidypopup.usecenterbookmarkbar" = true;
    "mod.forkedtidypopup.usecustomhovercolor" = true;
    "mod.forkedtidypopup.usetidyextension" = true;
    "mod.forkedtidypopup.usetidypopup" = true;
    "mod.forkedtidypopup.usezenprimarycolor" = true;
    "mod.zenbettermusicbar.alwaysshow" = true;
    "mod.zenbettermusicbar.custombackground" = "var(--zen-media-control-bg)";
    "mod.zenbettermusicbar.enabled" = true;
    "mod.zenbettermusicbar.hidecontrol" = false;
    "mod.zenbettermusicbar.hidemusicinfo" = false;
    "mod.zenbettermusicbar.hideparticles" = false;
    "mod.zenbettermusicbar.hideprogress" = false;
    "mod.zencustomurlbar.blur" = "5px";
    "mod.zencustomurlbar.borderradius" = "12px";
    "mod.zencustomurlbar.brightness" = "0.7";
    "mod.zencustomurlbar.customcolor" = "rgba(23, 23, 26, 1)";
    "mod.zencustomurlbar.scale" = "1";
    "mod.zencustomurlbar.transparentvalue" = "15%";
    "mod.zencustomurlbar.useanimation" = true;
    "mod.zencustomurlbar.usefromzen" = true;
    "svg.context-properties.content.enabled" = true;
  };
  sineModDefaultPrefs = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value: "defaultPref(${builtins.toJSON name}, ${builtins.toJSON value});"
    ) sineModDefaultPreferences
  );
  fluentValidator = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.fluent-syntax
  ]);

  sineProfile = pkgs.runCommand "firefox-sine-profile-${sineVersion}" { } ''
    mkdir -p "$out/sine-mods"
    ${pkgs.unzip}/bin/unzip -q ${sineEngine} -d "$out"
    ${pkgs.unzip}/bin/unzip -q ${sineBootloaderProfile} -d "$out"

    # Sine 2.3.3 otherwise falls back to en-US for a Japanese Firefox.
    substituteInPlace "$out/JS/utils/dom.mjs" \
      --replace-fail \
        'const supportedLocales = ["en-US", "en", "pl", "ru"];' \
        'const supportedLocales = ["en-US", "en", "ja", "pl", "ru"];'

    # Firefox resolves one Fluent meta-source per bundle. Register Sine's
    # resources inside each active language pack's meta-source so native and
    # Sine strings can remain Japanese in the same browser document.
    ${lib.getExe pkgs.gnupatch} \
      --directory "$out/JS" \
      --strip 1 \
      --fuzz 0 \
      --input ${../assets/sine-langpack-shadow.patch}
    ${pkgs.coreutils}/bin/install -d "$out/JS/locales/ja"
    ${pkgs.coreutils}/bin/install -m 0444 \
      ${../assets/sine-ja/sine-preferences.ftl} \
      "$out/JS/locales/ja/sine-preferences.ftl"
    ${pkgs.coreutils}/bin/install -m 0444 \
      ${../assets/sine-ja/sine-toasts.ftl} \
      "$out/JS/locales/ja/sine-toasts.ftl"
    ${pkgs.coreutils}/bin/install -m 0444 \
      ${../assets/sine-ja/sine-cmdpalette.ftl} \
      "$out/JS/locales/ja/sine-cmdpalette.ftl"

    ${lib.getExe fluentValidator} \
      ${../assets/validate-sine-locales.py} \
      "$out/JS/locales/en-US" \
      "$out/JS/locales/ja"

    # Natsumi has no locale resources. Keep its features intact and load a
    # reviewed Japanese-only DOM translation layer before its UI scripts.
    ${lib.getExe pkgs.nodejs} --check "$out/JS/sine.sys.mjs"
    ${lib.getExe pkgs.nodejs} --check ${../assets/natsumi-ja.uc.mjs}

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (id: source: ''
        unpack_dir="$TMPDIR/${id}"
        mkdir -p "$unpack_dir" "$out/sine-mods/${id}"
        ${pkgs.unzip}/bin/unzip -q ${source} -d "$unpack_dir"

        root_count="$(${pkgs.findutils}/bin/find "$unpack_dir" -mindepth 1 -maxdepth 1 -type d | ${pkgs.coreutils}/bin/wc -l)"
        if [[ "$root_count" -ne 1 ]]; then
          echo "Sine mod ${id} has an unexpected archive layout" >&2
          exit 1
        fi

        root_dir="$(${pkgs.findutils}/bin/find "$unpack_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)"
        ${pkgs.coreutils}/bin/cp -R "$root_dir/." "$out/sine-mods/${id}/"
      '') sineModSources
    )}

    ${pkgs.coreutils}/bin/install -m 0444 \
      ${../assets/natsumi-ja.uc.mjs} \
      "$out/sine-mods/natsumi-browser/natsumi/scripts/localization-ja.uc.mjs"

    ${lib.getExe pkgs.jq} --argjson ids '${builtins.toJSON sineModIds}' '
      def basename_if_string:
        if type == "string" then split("/")[-1] else . end;

      map(select(.id as $id | $ids | index($id)))
      | map(
          .origin = "store"
          | .["no-updates"] = true
          | .enabled = true
          | if .id == "natsumi-browser" then
              .scripts["natsumi/scripts/"]["localization-ja.uc.mjs"] = {
                "loadOrder": 9,
                "include": [
                  "chrome://browser/content/browser.xhtml",
                  "chrome://global/content/pictureinpicture/player.xhtml*",
                  "about:preferences*",
                  "about:settings*"
                ]
              }
            else . end
          | if has("style") then
              if (.style | type) == "string" then
                .style = { "chrome": (.style | basename_if_string) }
              elif (.style | type) == "object" then
                .style |= with_entries(.value |= basename_if_string)
              else . end
            else . end
          | if has("preferences") then
              .preferences |= basename_if_string
            else . end
        )
      | map({ key: .id, value: . })
      | from_entries
    ' ${sineMarketplace} > "$out/managed-mods.json"

    ${lib.getExe pkgs.jq} --argjson expectedVersions '${builtins.toJSON sineModVersions}' -e '
      . as $mods
      | ($mods | length) == ($expectedVersions | length)
        and all(
          $expectedVersions | to_entries[];
          $mods[.key].version == .value
        )
        and $mods["natsumi-browser"].scripts["natsumi/scripts/"]["localization-ja.uc.mjs"].loadOrder == 9
        and $mods["natsumi-browser"].scripts["natsumi/scripts/"]["localization-ja.uc.mjs"].include == [
          "chrome://browser/content/browser.xhtml",
          "chrome://global/content/pictureinpicture/player.xhtml*",
          "about:preferences*",
          "about:settings*"
        ]
    ' "$out/managed-mods.json" >/dev/null

    test -f "$out/JS/engine.json"
    test -f "$out/JS/locales/ja/sine-preferences.ftl"
    test -f "$out/sine-mods/natsumi-browser/natsumi/scripts/localization-ja.uc.mjs"
    test -f "$out/utils/chrome.manifest"
  '';

  firefoxWithSine = pkgs.firefox.override {
    # Sine's privileged profile bootloader requires the release AutoConfig
    # sandbox to be disabled before mozilla.cfg is evaluated.
    extraAutoConfig = ''
      pref("general.config.sandbox_enabled", false);
    '';
  };

in
{
  programs.firefox = {
    enable = true;
    package = firefoxWithSine;
    languagePacks = [ "ja" ];
    autoConfig = ''
      // Defaults required by the requested Sine mods. Users can override them.
      ${sineModDefaultPrefs}

      // Load the pinned Sine bootloader from the active Firefox profile.
      if (!Services.appinfo.inSafeMode) {
        try {
          const cmanifest = Services.dirsvc.get("UChrm", Ci.nsIFile);
          cmanifest.append("utils");
          cmanifest.append("chrome.manifest");

          if (cmanifest.exists()) {
            Components.manager.QueryInterface(Ci.nsIComponentRegistrar).autoRegister(cmanifest);
            ChromeUtils.importESModule("chrome://userscripts/content/sine.sys.mjs");
          }
        } catch (error) {
          Components.utils.reportError(`[Sine] Bootloader failed: ''${error}`);
        }
      }
    '';
    preferences = {
      "intl.accept_languages" = "ja-JP,ja,en-US,en";
      "intl.locale.requested" = "ja";
      "intl.regional_prefs.use_os_locales" = false;
      "sine.allow-unsafe-js" = false;
      "sine.auto-updates" = false;
      "sine.engine.auto-update" = false;
    };
  };

  home-manager.users.keewai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      firefoxProfilesRoot = "${config.xdg.configHome}/mozilla/firefox";
    in
    {
      home.activation.installSine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        profiles_root=${lib.escapeShellArg firefoxProfilesRoot}
        profiles_ini="$profiles_root/profiles.ini"

        if [[ ! -f "$profiles_ini" ]]; then
          echo "Sine activation: Firefox profiles.ini is missing at $profiles_ini" >&2
          exit 1
        fi

        profile_info="$(${lib.getExe pkgs.gawk} '
          BEGIN { FS = "=" }

          function emit_default() {
            if (in_profile && is_default && profile_path != "") {
              print is_relative "\t" profile_path
              found = 1
              exit
            }
          }

          /^\[Profile[0-9]+\]$/ {
            emit_default()
            in_profile = 1
            is_default = 0
            is_relative = 1
            profile_path = ""
            next
          }

          /^\[/ {
            emit_default()
            in_profile = 0
            next
          }

          in_profile && $1 == "Path" {
            sub(/^[^=]*=/, "")
            profile_path = $0
            next
          }

          in_profile && $1 == "Default" && $2 == "1" {
            is_default = 1
            next
          }

          in_profile && $1 == "IsRelative" {
            is_relative = $2
          }

          END {
            if (!found) emit_default()
          }
        ' "$profiles_ini")"

        if [[ -z "$profile_info" ]]; then
          echo "Sine activation: Firefox has no default profile" >&2
          exit 1
        fi

        IFS=$'\t' read -r is_relative profile_path <<< "$profile_info"
        if [[ "$is_relative" == "1" ]]; then
          profile_dir="$profiles_root/$profile_path"
        else
          profile_dir="$profile_path"
        fi

        if [[ -z "$profile_dir" || "$profile_dir" == "/" || ! -d "$profile_dir" || ! -f "$profile_dir/prefs.js" ]]; then
          echo "Sine activation: refusing unexpected Firefox profile $profile_dir" >&2
          exit 1
        fi

        chrome_dir="$profile_dir/chrome"
        mods_dir="$chrome_dir/sine-mods"
        ${pkgs.coreutils}/bin/install -d -m 0700 "$chrome_dir" "$mods_dir"

        copy_sine_tree() {
          source_dir="$1"
          target_dir="$2"
          if [[ -L "$target_dir" ]]; then
            echo "Sine activation: refusing symlink target $target_dir" >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/install -d -m 0700 "$target_dir"
          ${pkgs.coreutils}/bin/cp -R --no-preserve=mode,ownership "$source_dir/." "$target_dir/"
          ${pkgs.coreutils}/bin/chmod -R u+rwX "$target_dir"
        }

        copy_sine_tree ${sineProfile}/JS "$chrome_dir/JS"
        copy_sine_tree ${sineProfile}/utils "$chrome_dir/utils"

        for mod_id in ${lib.escapeShellArgs sineModIds}; do
          copy_sine_tree "${sineProfile}/sine-mods/$mod_id" "$mods_dir/$mod_id"
        done

        mods_json="$mods_dir/mods.json"
        mods_tmp="$mods_dir/.mods.json.nix-managed"
        if [[ -f "$mods_json" ]] && ${lib.getExe pkgs.jq} -e 'type == "object"' "$mods_json" >/dev/null 2>&1; then
          ${lib.getExe pkgs.jq} -s '
            .[0] * .[1]
          ' "$mods_json" ${sineProfile}/managed-mods.json > "$mods_tmp"
        else
          ${pkgs.coreutils}/bin/cp ${sineProfile}/managed-mods.json "$mods_tmp"
        fi
        ${pkgs.coreutils}/bin/chmod 0600 "$mods_tmp"
        ${pkgs.coreutils}/bin/mv -f "$mods_tmp" "$mods_json"
      '';
    };
}
