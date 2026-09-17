{
  lib,
  procps,
  python3Packages,
}:
let
  cdpUse = python3Packages.buildPythonPackage rec {
    pname = "cdp-use";
    version = "1.4.5";
    pyproject = true;

    src = python3Packages.fetchPypi {
      pname = "cdp_use";
      inherit version;
      hash = "sha256-DaOjLfRjNqA/9aIrxrxELNfS8tUKEY/UhW8p039tJqA=";
    };

    build-system = [ python3Packages.hatchling ];
    dependencies = with python3Packages; [
      httpx
      typing-extensions
      websockets
    ];
    pythonImportsCheck = [ "cdp_use.client" ];
  };

  fetchUse = python3Packages.buildPythonPackage rec {
    pname = "fetch-use";
    version = "0.4.0";
    pyproject = true;

    src = python3Packages.fetchPypi {
      pname = "fetch_use";
      inherit version;
      hash = "sha256-lRGYfUkH7G2sUB4h1mlG0QCY9mtdIbwqukGJzYG6GJo=";
    };

    build-system = [ python3Packages.hatchling ];
    pythonImportsCheck = [ "fetch_use" ];
  };
in
python3Packages.buildPythonPackage rec {
  pname = "browser-harness";
  version = "0.1.13";
  pyproject = true;

  src = python3Packages.fetchPypi {
    pname = "browser_harness";
    inherit version;
    hash = "sha256-KE3FR6BCwwn+r9mp9KdLKoZRt5Y+o6xssvLWSIn2qPM=";
  };

  build-system = [ python3Packages.setuptools ];
  dependencies = [
    cdpUse
    fetchUse
    python3Packages.pillow
    python3Packages.websockets
  ];
  pythonRelaxDeps = [ "websockets" ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'setuptools==84.0.0' 'setuptools'
    substituteInPlace src/browser_harness/daemon.py \
      --replace-fail '    ".config/google-chrome",' '    ".config/google-chrome",
        ".config/BraveSoftware/Brave-Origin",
        ".config/BraveSoftware/Brave-Browser",'
    substituteInPlace src/browser_harness/admin.py \
      --replace-fail '("brave-origin", "Brave Origin", (), None)' \
        '("brave-origin", "Brave Origin", ("brave-origin",), None)'
  '';

  postInstall = ''
    rm "$out/bin/browser-harness-mcp"
  '';

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ procps ]}"
    "--set BH_TELEMETRY 0"
    "--set BH_UPDATE_CHECK 0"
  ];

  preBuild = ''
    export HOME=$(mktemp -d)
  '';
  pythonImportsCheck = [
    "browser_harness.admin"
    "browser_harness.daemon"
    "browser_harness.helpers"
  ];

  meta = {
    description = "Local browser control through the Chrome DevTools Protocol";
    homepage = "https://github.com/browser-use/browser-harness";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "browser-harness";
  };
}
