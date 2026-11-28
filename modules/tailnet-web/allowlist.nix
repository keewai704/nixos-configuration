variable: clients: {
  map = ''
    map $tailscale_client_ip ${variable} {
      default 0;
      ${builtins.concatStringsSep "" (
        map (client: ''
          "${client}" 1;
        '') clients
      )}
    }
  '';

  deny = ''
    if (${variable} = 0) {
      return 403;
    }
  '';
}
