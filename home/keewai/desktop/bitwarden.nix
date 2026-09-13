{
  config,
  lib,
  pkgs,
  ...
}:
let
  vaultwardenUrl = "https://orange.tail1e65cd.ts.net/vault";
  initialRbwConfig = pkgs.writeText "rbw-initial-config.json" (
    builtins.toJSON {
      base_url = vaultwardenUrl;
      pinentry = "pinentry-gnome3";
      lock_timeout = 300;
    }
  );
  setupLauncher = pkgs.writeShellApplication {
    name = "island-bitwarden-setup";
    runtimeInputs = [
      pkgs.kitty
      pkgs.rbw
      pkgs.jq
    ];
    text = ''
      if [[ "''${1:-}" != --inside ]]; then
        exec kitty --class bitwarden-setup --title "Bitwarden setup" "$0" --inside
      fi
      printf 'Bitwarden launcher setup\nServer: %s\n\n' ${lib.escapeShellArg vaultwardenUrl}
      printf 'Passwords and verification codes are entered in the separate authentication dialog.\n\n'
      email=$(rbw config show | jq -r '.email // ""')
      printf 'Email [%s]: ' "$email"
      read -r entered_email
      email=''${entered_email:-$email}
      if [[ "$email" != *@* || "$email" == *[[:space:]]* ]]; then
        printf 'Enter a valid email address.\n'
        read -r -p 'Press Enter to close.'
        exit 1
      fi
      rbw config set email "$email"
      if rbw unlock && rbw sync; then
        printf '\nReady. Open the launcher and search with bw <item>.\n'
      else
        printf '\nSign-in did not complete. Run setup again to retry.\n'
      fi
      read -r -p 'Press Enter to close.'
    '';
  };
  sshAgentSocket = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
in
{
  home.packages = [
    pkgs.bitwarden-desktop
    pkgs.pinentry-gnome3
    setupLauncher
  ];

  systemd.user.sessionVariables.SSH_AUTH_SOCK = sshAgentSocket;
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*".IdentityAgent = sshAgentSocket;
  };
  programs.rbw.enable = true;

  home = {
    sessionVariables.SSH_AUTH_SOCK = sshAgentSocket;
    activation.initializeBitwardenLauncher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ ! -e ${lib.escapeShellArg "${config.xdg.configHome}/rbw/config.json"} ]]; then
        install -Dm600 ${initialRbwConfig} ${lib.escapeShellArg "${config.xdg.configHome}/rbw/config.json"}
      fi
    '';

    activation.initializeBitwardenAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ ! -e ${lib.escapeShellArg "${config.xdg.configHome}/autostart/bitwarden.desktop"} ]]; then
        install -Dm644 ${
          pkgs.makeDesktopItem {
            name = "bitwarden";
            desktopName = "Bitwarden";
            exec = "${lib.getExe pkgs.bitwarden-desktop} --autostart";
          }
        }/share/applications/bitwarden.desktop ${lib.escapeShellArg "${config.xdg.configHome}/autostart/bitwarden.desktop"}
      fi
    '';
  };
}
