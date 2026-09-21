{
  config,
  lib,
  pkgs,
  ...
}:
let
  vaultwardenUrl = "https://orange.tail1e65cd.ts.net/vault";
  rbwConfigPath = "${config.xdg.configHome}/rbw/config.json";
  initialRbwConfig = pkgs.writeText "rbw-initial-config.json" (
    builtins.toJSON {
      base_url = vaultwardenUrl;
      pinentry = "pinentry-gnome3";
      lock_timeout = 300;
    }
  );
  autostartPath = "${config.xdg.configHome}/autostart/bitwarden.desktop";
  autostartEntry = pkgs.makeDesktopItem {
    name = "bitwarden";
    desktopName = "Bitwarden";
    exec = "${lib.getExe pkgs.bitwarden-desktop} --autostart";
  };
  sshAgentSocket = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
in
{
  home.packages = [
    pkgs.bitwarden-desktop
    pkgs.pinentry-gnome3
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
    activation.initializeRbw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ ! -e ${lib.escapeShellArg rbwConfigPath} ]]; then
        install -Dm600 ${initialRbwConfig} ${lib.escapeShellArg rbwConfigPath}
      fi
    '';
    activation.initializeBitwardenAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ ! -e ${lib.escapeShellArg autostartPath} ]]; then
        install -Dm644 ${autostartEntry}/share/applications/bitwarden.desktop ${lib.escapeShellArg autostartPath}
      fi
    '';
  };
}
