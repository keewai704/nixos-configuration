{ pkgs, ... }:
let
  package = pkgs.callPackage ../../../pkgs/icloud-keychain { };
  manifest = {
    name = "org.keepassxc.keepassxc_browser";
    description = "Read-only iCloud Keychain bridge for KeePassXC-Browser";
    path = "${package}/bin/icloud-keychain-native";
    type = "stdio";
  };
  chromiumManifest = builtins.toJSON (
    manifest
    // {
      allowed_origins = [ "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" ];
    }
  );
in
{
  home.packages = [ package ];
  home.file.".mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".text =
    builtins.toJSON
      (
        manifest
        // {
          allowed_extensions = [ "keepassxc-browser@keepassxc.org" ];
        }
      );
  xdg.configFile."BraveSoftware/Brave-Browser/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json".text =
    chromiumManifest;
}
