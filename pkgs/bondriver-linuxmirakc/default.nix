{
  lib,
  stdenv,
  upstream,
}:
stdenv.mkDerivation {
  pname = "bondriver-linuxmirakc";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  patches = [ ./receiver.patch ];
  enableParallelBuilding = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 BonDriver_LinuxMirakc.so $out/lib/BonDriver_LinuxMirakc.so
    runHook postInstall
  '';
  meta = {
    description = "Native Linux BonDriver for mirakc";
    homepage = "https://github.com/matching/BonDriver_LinuxMirakc";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
