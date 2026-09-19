{
  lib,
  fetchFromGitHub,
  nodejs,
  procps,
  python3Packages,
  browser-harness,
}:
python3Packages.buildPythonApplication rec {
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

  postInstall = ''
    install -Dm444 docs/demo.mp4 "$out/${python3Packages.python.sitePackages}/docs/demo.mp4"
    install -Dm444 .env.example "$out/share/jev-ultrafast/env.example"
  '';

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ procps ]}"
    "--prefix PYTHONPATH : $out/${python3Packages.python.sitePackages}:${python3Packages.makePythonPath dependencies}"
    "--set BH_TELEMETRY 0"
    "--set BH_UPDATE_CHECK 0"
    "--run ${lib.escapeShellArg ''
      if [[ -z "''${TYPESAFE_API_KEY:-}" ]]; then
        typesafe_key_file="''${TYPESAFE_API_KEY_FILE:-''${XDG_CONFIG_HOME:-$HOME/.config}/typesafe/api-key}"
        if [[ -f "$typesafe_key_file" ]]; then
          TYPESAFE_API_KEY="$(< "$typesafe_key_file")"
          export TYPESAFE_API_KEY
        fi
        unset typesafe_key_file
      fi
    ''}"
  ];

  nativeCheckInputs = [
    nodejs
    python3Packages.pytestCheckHook
  ];
  preBuild = ''
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
