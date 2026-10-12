{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  unzip,
  cmake,
  pkg-config,
  autoPatchelfHook,
  fcitx5,
  icu,
  openssl,
  zlib,
}:
let
  source = lib.importJSON ./source.json;
  inherit (source) version;
  release = fetchurl {
    url = "https://github.com/yksr-melt/Meltype/releases/download/v${version}/Meltype-${version}-linux.zip";
    hash = source.releaseHash;
  };
in
stdenv.mkDerivation {
  pname = "fcitx5-meltype";
  inherit version;

  src = fetchFromGitHub {
    owner = "yksr-melt";
    repo = "Meltype";
    tag = "v${version}";
    hash = source.srcHash;
  };

  sourceRoot = "source/linux/fcitx5";

  nativeBuildInputs = [
    unzip
    cmake
    pkg-config
    autoPatchelfHook
  ];

  buildInputs = [
    fcitx5
    stdenv.cc.cc.lib
  ];

  cmakeFlags = [ (lib.cmakeFeature "MELTYPE_DIR" "${placeholder "out"}/lib/meltype") ];

  installPhase = ''
    runHook preInstall
    unzip -q ${release} -d release
    dir=$out/lib/meltype
    install -Dm755 meltype.so $out/lib/fcitx5/meltype.so
    install -Dm644 ../meltype-addon.conf $out/share/fcitx5/addon/meltype.conf
    install -Dm755 release/Meltype-linux/libMeltypeNative.so $dir/libMeltypeNative.so
    install -Dm755 release/Meltype-linux/mozc/meltype_mozc_helper $dir/mozc/meltype_mozc_helper
    install -Dm644 release/Meltype-linux/icon.png $dir/icon.png
    install -Dm644 -t $out/share/licenses/meltype release/Meltype-linux/{LICENSE,THIRD-PARTY-NOTICES.md} release/Meltype-linux/mozc/MOZC-{LICENSE.txt,CREDITS.html}
    mkdir -p $out/share/fcitx5/inputmethod
    substitute ../meltype.conf $out/share/fcitx5/inputmethod/meltype.conf --replace-fail @DIR@ $dir
    runHook postInstall
  '';

  postFixup = ''
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        icu
        openssl
        zlib
      ]
    } $out/lib/meltype/libMeltypeNative.so
  '';

  meta = {
    description = "Japanese input method that switches between Japanese and English automatically";
    homepage = "https://github.com/yksr-melt/Meltype";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    platforms = [ "x86_64-linux" ];
  };
}
