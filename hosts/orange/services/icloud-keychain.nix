let
  inherit (import ../settings.nix) icloudKeychainPort tailnetOrigin;
in
{
  services.gnome.gnome-keyring.enable = true;
  home-manager.users.keewai.imports = [
    (import ../../../home/keewai/server/icloud-keychain.nix {
      port = icloudKeychainPort;
      publicUrl = "${tailnetOrigin}/icloud-keychain/";
    })
  ];
}
