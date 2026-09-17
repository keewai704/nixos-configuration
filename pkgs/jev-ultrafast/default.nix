{
  lib,
  fetchFromGitHub,
  nodejs,
  procps,
  python3Packages,
  browser-harness,
}:
python3Packages.buildPythonApplication {
  pname = "jev-ultrafast";
  version = "0.1.0-unstable-2026-09-17";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "browser-use";
    repo = "jev-ultrafast";
    rev = "452c1ad2dd628008f1d5608f28158d76e49e6cc0";
    hash = "sha256-D2BQZG3gMIG/goeJBikYxb5PMDibzttWnlZ2ccg3Exk=";
  };

  build-system = [ python3Packages.hatchling ];
  dependencies = [
    browser-harness
    python3Packages.httpx
  ]
  ++ python3Packages.httpx.optional-dependencies.http2;

  postPatch = ''
    substituteInPlace jev_ultrafast/demo.py \
      --replace-fail 'ROOT.parent / "docs" / "demo.mp4"' \
        "Path(\"$out/share/jev-ultrafast/demo.mp4\")"
  '';

  postInstall = ''
    install -Dm444 docs/demo.mp4 "$out/share/jev-ultrafast/demo.mp4"
    install -Dm444 .env.example "$out/share/jev-ultrafast/env.example"
  '';

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ procps ]}"
    "--set BH_TELEMETRY 0"
    "--set BH_UPDATE_CHECK 0"
  ];

  nativeCheckInputs = [
    nodejs
    python3Packages.pytestCheckHook
  ];
  preCheck = ''
    export HOME=$(mktemp -d)
  '';
  postCheck = ''
    node --check jev_ultrafast/static/app.js
    node --check jev_ultrafast/snapshot.js
  '';
  pythonImportsCheck = [ "jev_ultrafast.demo" ];

  meta = {
    description = "Browser agent with a dynamic indexed action space";
    homepage = "https://github.com/browser-use/jev-ultrafast";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "jev";
  };
}
