{
  lib,
  rustPlatform,
  upstream,
  coaxRs,
}:
let
  sharedPackages = (builtins.fromTOML (builtins.readFile (coaxRs + "/Cargo.lock"))).package;
  sharedNames = map (package: package.name) sharedPackages;
  driverPackages = (builtins.fromTOML (builtins.readFile (upstream + "/Cargo.lock"))).package;
  packages =
    sharedPackages
    ++ builtins.filter (package: !(builtins.elem package.name sharedNames)) driverPackages;
  lockFile = builtins.toFile "bondriver-coax-Cargo.lock" (
    "version = 4\n"
    + lib.concatMapStringsSep "\n" (
      package:
      "[[package]]\n"
      + lib.concatMapStringsSep "\n" (name: "${name} = ${builtins.toJSON package.${name}}") (
        builtins.attrNames package
      )
      + "\n"
    ) packages
  );
in
rustPlatform.buildRustPackage {
  pname = "bondriver-coax";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'git = "https://github.com/Till0196/coax-rs"' 'path = "${coaxRs}/coax"'
    substituteInPlace Cargo.toml \
      --replace-fail 'isdb = { path = "${coaxRs}/coax" }' 'isdb = { path = "${coaxRs}/isdb" }' \
      --replace-fail 'mmttlv = { path = "${coaxRs}/coax" }' 'mmttlv = { path = "${coaxRs}/mmttlv" }' \
      --replace-fail 'mpegts = { path = "${coaxRs}/coax" }' 'mpegts = { path = "${coaxRs}/mpegts" }'
    cp ${lockFile} Cargo.lock
  '';
  cargoLock = { inherit lockFile; };
  cargoBuildFlags = [
    "-p"
    "bondriver_coax"
    "-p"
    "bondriver_probe"
  ];
  cargoTestFlags = [
    "-p"
    "bondriver_coax"
    "-p"
    "coax_settings"
    "-p"
    "bondriver_probe"
  ];
  postInstall = ''
    mv "$out/lib/libBonDriver_coax.so" "$out/lib/BonDriver_coax.so"
  '';
  meta = {
    description = "BonDriver for the coax tuner daemon";
    homepage = "https://github.com/Till0196/BonDriver_coax";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
