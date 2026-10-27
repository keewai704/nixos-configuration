{
  lib,
  stdenv,
  upstream,
}:
stdenv.mkDerivation {
  pname = "bondriver-linuxmirakc";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  postPatch = ''
    substituteInPlace include/type_compat.h \
      --replace-fail 'typedef bool BOOL;' 'typedef int BOOL;'
    substituteInPlace src/GrabTsData.hpp \
      --replace-fail 'pthread_mutexattr_t attr;' 'pthread_mutexattr_t attr;
        ::pthread_mutexattr_init(&attr);' \
      --replace-fail '::pthread_mutex_init( &m_pRingMutex, &attr );' '::pthread_mutex_init( &m_pRingMutex, &attr );
        ::pthread_mutexattr_destroy(&attr);'
  '';
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
