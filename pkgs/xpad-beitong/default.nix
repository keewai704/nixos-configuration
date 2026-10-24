{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "xpad-beitong";
  version = "0-unstable-2026-07-24";

  src = fetchFromGitHub {
    owner = "675076143";
    repo = "xpad-beitong-dkms";
    rev = "f4ce639f8f2e88ff3f8fbca75c3e5ce9b6857169";
    hash = "sha256-3jh/rp/cPOS2sA6tu9qhBEPXbluL0AqrDhq7OfrhaNc=";
  };

  postUnpack = ''
    cp ${kernel.src}/drivers/input/joystick/xpad.c "$sourceRoot/xpad.c"
  '';

  patches = [ "${finalAttrs.src}/beitong-gip-init.patch" ];
  patchFlags = [ "-p0" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  enableParallelBuilding = true;

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
  ];
  buildTargets = [ "modules" ];

  installPhase = ''
    runHook preInstall
    install -Dm444 xpad.ko "$out/lib/modules/${kernel.modDirVersion}/updates/xpad.ko"
    runHook postInstall
  '';

  meta = {
    description = "Linux xpad with BEITONG GIP initialization fixes";
    homepage = "https://github.com/675076143/xpad-beitong-dkms";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
})
