{
  lib,
  fetchFromGitHub,
  fetchurl,
  runCommand,
  cacert,
  openssl,
  python3Packages,
}:
let
  appleRoot = fetchurl {
    url = "https://www.apple.com/appleca/AppleIncRootCertificate.cer";
    hash = "sha256-sLFzDsvH/0UFFCxJ8Slebtpryu1+LGjFvpG1oRAB8CQ=";
  };
  appleCaBundle = runCommand "icloud-apple-ca-bundle.pem" { nativeBuildInputs = [ openssl ]; } ''
    cat ${cacert}/etc/ssl/certs/ca-bundle.crt > "$out"
    openssl x509 -inform DER -in ${appleRoot} -outform PEM >> "$out"
  '';
in
python3Packages.buildPythonApplication {
  pname = "icloud-keychain";
  version = "0.0.1-62de50a";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Sank6";
    repo = "iCloud-Keychain-for-Linux";
    rev = "62de50adb39c791d00955394e7e03c7ccceb1c00";
    hash = "sha256-TXgZ49xM7KQryTU75i+dktJETBjTa09Lhi7kkjqNmNw=";
  };

  build-system = [ python3Packages.setuptools ];
  dependencies = with python3Packages; [
    requests
    srp
    cryptography
    pynacl
    secretstorage
    websockets
  ];

  postPatch = ''
    cp ${./keepassxc.py} icp/keepassxc.py
    cp ${./anisette.py} icp/auth/anisette.py
    cp ${./keyring.py} icp/keyring.py
    cp ${./server.py} icp/server.py
    cp ${./client.py} tests/icloud_keychain_client.py
    cp ${./test_keepassxc.py} tests/test_keepassxc.py
    cp ${./test_anisette.py} tests/test_anisette.py
    cp ${./test_client.py} tests/test_client.py
    cp ${./test_server.py} tests/test_server.py
    cp ${./test_keyring.py} tests/test_keyring.py
    substituteInPlace icp/auth/anisette.py --replace-fail '@appleCa@' '${appleCaBundle}'
    substituteInPlace icp/auth/gsa.py icp/auth/icloud.py \
      --replace-fail 'verify=False' 'verify="${appleCaBundle}", allow_redirects=False'
    substituteInPlace icp/auth/webauth.py \
      --replace-fail 'self.http.verify = False' 'self.http.verify = "${appleCaBundle}"'
    substituteInPlace icp/auth/webauth.py icp/hme/client.py \
      --replace-fail 'timeout=20' 'timeout=20, allow_redirects=False'
    substituteInPlace icp/escrow/srp.py \
      --replace-fail 'verify=True,' 'verify=True, allow_redirects=False,' \
      --replace-fail 'HTTP {resp.status_code}: {data}' 'HTTP {resp.status_code}'
    substituteInPlace icp/transport/cloudkit.py \
      --replace-fail 'verify=VERIFY_TLS,' 'verify=VERIFY_TLS, allow_redirects=False,'
    substituteInPlace pyproject.toml \
      --replace-fail 'icp = "icp.cli.app:main"' 'icloud-keychain = "icp.keepassxc:main"'
    substituteInPlace icp/cli/app.py \
      --replace-fail '    password = ui.secret("Password: ")' '    if saved_user and username.casefold() != saved_user.casefold():
            ui.err("Sign out with icloud-keychain logout before changing Apple accounts")
            return 1
        password = ui.secret("Password: ")'
  '';

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  pythonImportsCheck = [ "icp.keepassxc" ];

  meta = {
    description = "Experimental read-only iCloud Keychain CLI with KeePassXC-Browser native messaging";
    homepage = "https://github.com/Sank6/iCloud-Keychain-for-Linux";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "icloud-keychain";
  };
}
