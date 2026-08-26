{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  makeWrapper,
  nodejs_24,
}:

buildNpmPackage (finalAttrs: {
  pname = "ponytail-mcp";
  version = "4.9.0";

  src = fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "2ed6c52c9d7e5e56942508591085fd45dea277d3";
    hash = "sha256-bGdXvzhWPwGdz3T2Yh2h6lf+3PBRFAfdBxP5pESmCHI=";
  };

  sourceRoot = "${finalAttrs.src.name}/ponytail-mcp";
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  nodejs = nodejs_24;
  npmDepsHash = "sha256-idGyBAJ4Pnj7b5Sr6XEHu/24nHOuCMjemE6xfShES6g=";
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  dontNpmBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/ponytail/ponytail-mcp"
    cp -r index.js instructions.js node_modules package.json \
      "$out/lib/ponytail/ponytail-mcp/"
    cp ../package.json "$out/lib/ponytail/package.json"
    cp -r ../hooks ../skills "$out/lib/ponytail/"

    makeWrapper ${lib.getExe nodejs_24} "$out/bin/ponytail-mcp" \
      --add-flags "$out/lib/ponytail/ponytail-mcp/index.js"

    runHook postInstall
  '';

  meta = {
    description = "MCP server for Ponytail's minimal-engineering instructions";
    homepage = "https://github.com/DietrichGebert/ponytail";
    license = lib.licenses.mit;
    mainProgram = "ponytail-mcp";
  };
})
