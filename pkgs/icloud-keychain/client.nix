{
  lib,
  python3,
  symlinkJoin,
  writeShellApplication,
  writeShellScriptBin,
  serverUrl ? "wss://orange.tail1e65cd.ts.net/icloud-keychain/",
}:
let
  python = python3.withPackages (packages: [ packages.websockets ]);
  source = builtins.toFile "icloud-keychain-client.py" (
    builtins.replaceStrings [ "@serverUrl@" ] [ serverUrl ] (builtins.readFile ./client.py)
  );
  client = writeShellApplication {
    name = "icloud-keychain-client";
    runtimeInputs = [ python ];
    text = ''
      exec ${python}/bin/python ${source} "$@"
    '';
  };
  native = writeShellScriptBin "icloud-keychain-native" ''
    exec ${client}/bin/icloud-keychain-client native-host "$@"
  '';
in
symlinkJoin {
  name = "icloud-keychain-client";
  paths = [
    client
    native
  ];
  meta = {
    description = "Native-messaging relay for the Orange iCloud Keychain backend";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "icloud-keychain-client";
  };
}
