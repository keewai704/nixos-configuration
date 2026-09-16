{
  autoPatchelfHook,
  fetchurl,
  libuv,
  nodejs_22,
  paseo,
  stdenv,
  stdenvNoCC,
}:
let
  nodePtyVersion = "1.2.0-beta.15";
in
stdenvNoCC.mkDerivation {
  pname = "paseo";
  inherit (paseo) version;

  src = fetchurl {
    url = "https://registry.npmjs.org/node-pty/-/node-pty-${nodePtyVersion}.tgz";
    hash = "sha512-vORSzHXi4Ofl7HemVWpuudLqCPdaQb4LfpRCUpE5HPxhp4JYscl8zZwxh11p26v2wvW24WMwnMfLjhRLixrfxA==";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libuv
    stdenv.cc.cc.lib
  ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -a ${paseo} "$out"
    chmod -R u+w "$out"
    patch -d "$out" -p1 < ${./web-ui-default-port.patch}
    node_pty="$out/lib/paseo/packages/server/node_modules/node-pty"
    ${nodejs_22}/bin/node -e \
      'if (require(process.argv[1]).version !== process.argv[2]) throw new Error("Update the pinned node-pty version");' \
      "$node_pty/package.json" ${nodePtyVersion}
    mkdir -p "$node_pty/prebuilds"
    cp -a prebuilds/linux-x64 "$node_pty/prebuilds/"
    substituteInPlace "$out/bin/paseo" "$out/bin/paseo-server" \
      --replace-fail ${paseo} "$out"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${nodejs_22}/bin/node -e 'require(process.argv[1])' \
      "$out/lib/paseo/packages/server/node_modules/node-pty"
    runHook postInstallCheck
  '';

  meta = paseo.meta // {
    platforms = [ "x86_64-linux" ];
  };
}
