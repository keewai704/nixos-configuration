{
  config,
  lib,
  pkgs,
  ...
}:
let
  autostartPath = "${config.xdg.configHome}/autostart/bitwarden.desktop";
  autostartEntry = pkgs.makeDesktopItem {
    name = "bitwarden";
    desktopName = "Bitwarden";
    exec = "${lib.getExe pkgs.bitwarden-desktop} --autostart";
  };
  sshAgentSocket = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
in
{
  home.packages = [ pkgs.bitwarden-desktop ];

  systemd.user.sessionVariables.SSH_AUTH_SOCK = sshAgentSocket;
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*".IdentityAgent = sshAgentSocket;
  };

  home = {
    sessionVariables.SSH_AUTH_SOCK = sshAgentSocket;
    activation.initializeBitwardenAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ ! -e ${lib.escapeShellArg autostartPath} ]]; then
        install -Dm644 ${autostartEntry}/share/applications/bitwarden.desktop ${lib.escapeShellArg autostartPath}
      fi
    '';
  };
}
