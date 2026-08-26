{
  buildNpmPackage,
  fetchurl,
  lib,
  nodejs_24,
}:

buildNpmPackage rec {
  pname = "yepanywhere";
  version = "0.7.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha256-FKAHC+w4s7XtCBVKH/Sk4RrL5/wtlsZRLXxplYNHZm0=";
  };

  sourceRoot = "package";
  nodejs = nodejs_24;
  npmDepsHash = "sha256-y+kK6er2qy4NKu7lCqt1Ms1f6XgZyJVZ10+5UcqXm6I=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # The npm release already contains the compiled server and web client.
  dontNpmBuild = true;

  # Build bcrypt against NixOS instead of relying on a generic prebuilt addon.
  npmRebuildFlags = [ "--build-from-source" ];

  meta = {
    description = "Self-hosted browser interface for supervising coding agents";
    homepage = "https://yepanywhere.com";
    license = lib.licenses.mit;
    mainProgram = "yepanywhere";
    platforms = lib.platforms.linux;
  };
}
