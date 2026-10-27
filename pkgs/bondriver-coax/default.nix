{
  lib,
  rustPlatform,
  upstream,
  coaxRs,
}:
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
  '';
  cargoHash = "sha256-wMFmquOgSCIQZI+jQRDXCmV/2O1oj444V3mYAoe+cjA=";
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
  installPhase = ''
    runHook preInstall
    install -Dm755 target/release/libBonDriver_coax.so $out/lib/BonDriver_coax.so
    install -Dm755 target/release/bondriver-probe $out/bin/bondriver-probe
    runHook postInstall
  '';
  meta = {
    description = "BonDriver for the coax tuner daemon";
    homepage = "https://github.com/Till0196/BonDriver_coax";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
