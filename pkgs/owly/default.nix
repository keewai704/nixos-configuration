{ callPackage, upstream }:
(callPackage "${upstream}/nix/package.nix" { }).overrideAttrs (previous: {
  patches = (previous.patches or [ ]) ++ [ ./confirm-command.patch ];
  doCheck = true;
  cargoTestFlags = [
    "-p"
    "owly-cli"
  ];
})
