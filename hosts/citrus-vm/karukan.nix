{
  cmake,
  fetchFromGitHub,
  fcitx5,
  kdePackages,
  lib,
  libxkbcommon,
  openssl,
  pkg-config,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "karukan";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "togatoga";
    repo = "karukan";
    tag = "v0.1.0";
    hash = "sha256-nC50n93BrfNOQSrWm/z9jbFG9iCgC+6wT6fustd/YWo=";
  };

  cargoHash = "sha256-fn9TjaIuYy4z65iUZxPntLacj7vIEpVgr2HrGkyTGag=";

  nativeBuildInputs = [
    cmake
    fcitx5
    kdePackages.extra-cmake-modules
    libxkbcommon
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    fcitx5
    kdePackages.extra-cmake-modules
    libxkbcommon
    openssl
  ];

  doCheck = false;

  configurePhase = ''
    runHook preConfigure
    cmake -S karukan-im/fcitx5-addon -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build --parallel "$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build
    runHook postInstall
  '';

  meta = {
    description = "Neural Japanese input method for Fcitx5";
    homepage = "https://github.com/togatoga/karukan";
    license = with lib.licenses; [
      asl20
      mit
    ];
    platforms = lib.platforms.linux;
  };
}
