{
  lib,
  rustPlatform,
  upstream,
}:
rustPlatform.buildRustPackage {
  pname = "rustxng";
  version = (builtins.fromTOML (builtins.readFile (upstream + "/Cargo.toml"))).package.version;
  src = upstream;
  cargoLock.lockFile = upstream + "/Cargo.lock";
  meta = {
    description = "SearXNG-compatible metasearch engine written in Rust";
    homepage = "https://github.com/sahenjp/RustXNG";
    license = lib.licenses.agpl3Plus;
    mainProgram = "rustxng";
    platforms = lib.platforms.linux;
  };
}
