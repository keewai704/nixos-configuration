{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
  git,
  libuv,
  stdenv,
  pi-coding-agent,
  runtimePackages ? [ ],
}:
let
  crewRoles = fetchzip {
    url = "https://registry.npmjs.org/@melihmucuk/pi-crew/-/pi-crew-1.0.34.tgz";
    hash = "sha256-VICdpdnYu+JdtT2t+4DEARiPkY9kGBVkKBpX17qLU9U=";
  };
  fontRevision = "92345ac0dbb28d27dbd32f3a782e84c55eaac214";
  notoSansMono = fetchurl {
    name = "noto-sans-mono.ttf";
    url = "https://raw.githubusercontent.com/google/fonts/${fontRevision}/ofl/notosansmono/NotoSansMono%5Bwdth,wght%5D.ttf";
    hash = "sha256-LLKts3io9XQhPiPfaXBQuDxUwn30ZaIBVVJ0CydpoIE=";
  };
  fontLicense = fetchurl {
    name = "noto-sans-mono-OFL.txt";
    url = "https://raw.githubusercontent.com/google/fonts/${fontRevision}/ofl/notosansmono/OFL.txt";
    hash = "sha256-zumJL58MyP6ILJ6VN+5qiWIdhu586vcLAuKyscJcBho=";
  };
  piRoot = "${pi-coding-agent}/lib/node_modules/pi-monorepo";
in
buildNpmPackage {
  pname = "pi-web";
  version = "0.9.1-unstable-2026-09-19";

  src = fetchFromGitHub {
    owner = "agegr";
    repo = "pi-web";
    rev = "1eb5e66a37c468aca7f0d338edb23de4fd84433e";
    hash = "sha256-pXXrD4DTzyk+i/xDW9F26X+qXicbr8nAUA3vzTS0Lz4=";
  };
  patches = [
    ./local-font.patch
    ./subpath.patch
    ./interrupted-subagents.patch
    ./transcript-context.patch
    ./unified-subagents.patch
    ./nested-subagents.patch
  ];
  npmDepsHash = "sha256-lGsMOYY2rCQSw+hMLXv+aWq4991NnkhLJUipL1F843k=";
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmPackFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    libuv
    stdenv.cc.cc.lib
  ];
  env.NEXT_TELEMETRY_DISABLED = "1";

  postPatch = ''
    ${lib.getExe nodejs} ${./use-packaged-pi-sdk.mjs}
    cp ${notoSansMono} app/noto-sans-mono.ttf
  '';

  postConfigure = ''
    cp -r ${piRoot} node_modules/@earendil-works/pi-coding-agent
    chmod -R u+w node_modules/@earendil-works/pi-coding-agent
    for package in pi-ai pi-agent-core pi-tui; do
      rm -r "node_modules/@earendil-works/$package"
      ln -s "pi-coding-agent/node_modules/@earendil-works/$package" \
        "node_modules/@earendil-works/$package"
    done
    ${lib.getExe nodejs} ${./build-subagent-roles.mjs} ${crewRoles}
  '';

  doCheck = true;
  nativeCheckInputs = [ git ];
  postBuild = ''
    ${lib.getExe nodejs} ${./build-subagent-extension.mjs} ${piRoot}/node_modules/esbuild
  '';
  checkPhase = ''
    runHook preCheck
    PI_WEB_NATIVE_SUBAGENT_EXTENSION="$PWD/pi-web-native-subagents/subagent-cli-extension.js" npm test
    runHook postCheck
  '';

  preInstall = ''
    rm -r node_modules/@earendil-works/pi-coding-agent
  '';

  postInstall = ''
    app_dir="$out/lib/node_modules/@agegr/pi-web"
    if [[ -e "$app_dir/node_modules/@earendil-works/pi-coding-agent" ]]; then
      rm -r "$app_dir/node_modules/@earendil-works/pi-coding-agent"
    fi
    ln -s ${piRoot} "$app_dir/node_modules/@earendil-works/pi-coding-agent"
    for package in pi-ai pi-agent-core pi-tui; do
      rm -r "$app_dir/node_modules/@earendil-works/$package"
      ln -s "${piRoot}/node_modules/@earendil-works/$package" \
        "$app_dir/node_modules/@earendil-works/$package"
    done
    for package in sharp-linuxmusl-x64 sharp-libvips-linuxmusl-x64; do
      rm -r "$app_dir/node_modules/@img/$package"
    done
    mkdir -p "$out/share/licenses/pi-web"
    cp ${fontLicense} "$out/share/licenses/pi-web/NotoSansMono-OFL.txt"
    cp ${crewRoles}/LICENSE "$out/share/licenses/pi-web/Crew-MIT.txt"
  '';

  postFixup = ''
    wrapProgram "$out/bin/pi-web" \
      --set PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT ${piRoot} \
      --prefix PATH : ${lib.makeBinPath (lib.unique ([ nodejs ] ++ runtimePackages))}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/pi-web" --help >/dev/null
    ${lib.getExe nodejs} -e 'require(process.argv[1])' \
      "$out/lib/node_modules/@agegr/pi-web/node_modules/node-pty"
    test_home=$(mktemp -d)
    HOME="$test_home" PI_CODING_AGENT_DIR="$test_home" ${lib.getExe nodejs} --input-type=module -e '
      const { default: extension } = await import(process.argv[1]);
      if (typeof extension !== "function") throw new Error("Missing native delegation extension");
    ' "$out/lib/node_modules/@agegr/pi-web/pi-web-native-subagents/subagent-cli-extension.js"
    rm -r "$test_home"
    runHook postInstallCheck
  '';

  meta = {
    description = "Web interface for the Pi coding agent";
    homepage = "https://github.com/agegr/pi-web";
    license = [
      lib.licenses.mit
      lib.licenses.ofl
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "pi-web";
  };
}
