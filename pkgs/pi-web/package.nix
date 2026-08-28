{
  autoPatchelfHook,
  buildNpmPackage,
  fetchFromGitHub,
  git,
  lib,
  makeWrapper,
  nodejs_24,
  noto-fonts,
  ripgrep,
  stdenv,
  withPiSubpath ? false,
}:

buildNpmPackage {
  pname = "pi-web" + lib.optionalString withPiSubpath "-pi-subpath";
  version = "0.8.11";

  src = fetchFromGitHub {
    owner = "agegr";
    repo = "pi-web";
    rev = "28bab3c25f5f6770c9b0b745ebbfec1c27f7b948";
    hash = "sha256-QVvYv6iaxrLXJv8Yw5E48Uof9cbSEf5TPRL4Z6H/0MQ=";
  };

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-AR+ia8SqnT3V4zcy5c3MTrMJe06o2T+kLeDGpdJ/AQ8=";
  npmBuildScript = "build";
  npmTestScript = "test";
  doCheck = true;

  postPatch = ''
    # Upstream's lock omits integrity data from six nested Pi packages and
    # marks another six optional wasm dependencies as bundled without registry
    # metadata. fetchNpmDeps validates every entry, so fill in the exact npm
    # registry metadata for this pinned lock.
    substituteInPlace package-lock.json \
      --replace-fail \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core": {' \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core": { "integrity": "sha512-VURr+xBRl3RxYcw3kT9Pn3yfi6LbRoCJgHF7h1mAblMjtLNV/MfG/RyF0uJizBAM886AEakSiw3j9c/aSngppg==",' \
      --replace-fail \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai": {' \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai": { "integrity": "sha512-M0YUV8vNO3y2WwWSyY8ijKJV5W4gkSUixuvk+Z00ZBjsyMfsdXfITsHEwP1UIf09YRWXT6oGn0GlCamt+P32XQ==",' \
      --replace-fail \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-client": {' \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-client": { "integrity": "sha512-zfErYane+390W0xpBJ/FWCp6aktPpkpcIcXUeZiAziWLoxE80ZNQALRyOSa/gGS5V+1OkNnMYxRxbzN0zUvnOA==",' \
      --replace-fail \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-protocol": {' \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-protocol": { "integrity": "sha512-9a4g6WhLOvRqvsIOFaWxg/2gdrbY4Thclwj5ipLUPAWChfsDJ/8XdPc2sRhSOkD6EsxpEFJz3xppcfwI6EcZDg==",' \
      --replace-fail \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry": {' \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry": { "integrity": "sha512-sgEkWoKrvSGaKn+YfLLFZmn+/A7B/w62eLwTD57nI+C9to8ITlFFVbgC2OtwvPnT3NFGHdCd53qhBEMIlptD1g==",' \
      --replace-fail \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui": {' \
        '"node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui": { "integrity": "sha512-fS6OEQKEEALnKa6Uw8LcgZZ+9CWck7f3MQSCETQp6leUgIFwMEDtKmOUnL9nsYm+RIPmy7OmplVxYRbV6hiaFg==",' \
      --replace-fail \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@emnapi/core": {' \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@emnapi/core": { "resolved": "https://registry.npmjs.org/@emnapi/core/-/core-1.8.1.tgz", "integrity": "sha512-AvT9QFpxK0Zd8J0jopedNm+w/2fIzvtPKPjqyw9jwvBaReTTqPBk9Hixaz7KbjimP+QNz605/XnjFcDAL2pqBg==",' \
      --replace-fail \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@emnapi/runtime": {' \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@emnapi/runtime": { "resolved": "https://registry.npmjs.org/@emnapi/runtime/-/runtime-1.8.1.tgz", "integrity": "sha512-mehfKSMWjjNol8659Z8KxEMrdSJDDot5SXMq00dM8BN4o+CLNXQ0xH2V7EchNHV4RmbZLmmPdEaXZc5H2FXmDg==",' \
      --replace-fail \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@emnapi/wasi-threads": {' \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@emnapi/wasi-threads": { "resolved": "https://registry.npmjs.org/@emnapi/wasi-threads/-/wasi-threads-1.1.0.tgz", "integrity": "sha512-WI0DdZ8xFSbgMjR1sFsKABJ/C5OnRrjT06JXbZKexJGrDuPTzZdDYfFlsgcCXCyf+suG5QU2e/y1Wo2V/OapLQ==",' \
      --replace-fail \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@napi-rs/wasm-runtime": {' \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@napi-rs/wasm-runtime": { "resolved": "https://registry.npmjs.org/@napi-rs/wasm-runtime/-/wasm-runtime-1.1.1.tgz", "integrity": "sha512-p64ah1M1ld8xjWv3qbvFwHiFVWrq1yFvV4f7w+mzaqiR4IlSgkqhcRdHwsGgomwzBH51sRY4NEowLxnaBjcW/A==",' \
      --replace-fail \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@tybys/wasm-util": {' \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/@tybys/wasm-util": { "resolved": "https://registry.npmjs.org/@tybys/wasm-util/-/wasm-util-0.10.1.tgz", "integrity": "sha512-9tTaPJLSiejZKx+Bmog4uSubteqTvFrVrURwkmHixBo0G4seD0zUxp98E1DzUBJxLQ3NPwXrGKDiVjwx/DpPsg==",' \
      --replace-fail \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/tslib": {' \
        '"node_modules/@tailwindcss/oxide-wasm32-wasi/node_modules/tslib": { "resolved": "https://registry.npmjs.org/tslib/-/tslib-2.8.1.tgz", "integrity": "sha512-oJFu94HQb+KVduSUQL7wnpmqnfmLsOA/nAh6b6EH0wCEoK0/mPeXU6c3wKDV83MkOuHPRHtSXKKU99IBazS/2w==",'

    # next/font/google performs a network fetch during the sandboxed build.
    # Use the identical local Noto Sans Mono family from nixpkgs instead.
    cp ${noto-fonts}/share/fonts/noto/NotoSansMono.ttf app/NotoSansMono.ttf
    substituteInPlace app/layout.tsx \
      --replace-fail 'import { Noto_Sans_Mono } from "next/font/google";' 'import localFont from "next/font/local";' \
      --replace-fail 'const notoSansMono = Noto_Sans_Mono({' 'const notoSansMono = localFont({' \
      --replace-fail '  subsets: ["latin", "cyrillic"],' '  src: "./NotoSansMono.ttf",'
  ''
  + lib.optionalString withPiSubpath ''
    substituteInPlace next.config.ts \
      --replace-fail \
        'const nextConfig: NextConfig = {' \
        'const nextConfig: NextConfig = { basePath: "/pi", trailingSlash: true, skipTrailingSlashRedirect: true,' \
      --replace-fail \
        '{ key: "Service-Worker-Allowed", value: "/" }' \
        '{ key: "Service-Worker-Allowed", value: "/pi/" }'

    # Pi Web uses absolute browser API URLs. Prefix all of its client/shared
    # URLs, including their matching unit-test fixtures, so they do not escape
    # the Next.js base path and collide with the root-mounted Immich API.
    while IFS= read -r sourceFile; do
      substituteInPlace "$sourceFile" \
        --replace-warn '"/api' '"/pi/api' \
        --replace-warn '`/api' '`/pi/api'
    done < <(${lib.getExe ripgrep} --files components hooks lib public \
      --glob '*.ts' --glob '*.tsx' --glob '*.js' --glob '*.mjs')

    substituteInPlace app/manifest.ts \
      --replace-fail 'id: "/",' 'id: "/pi/",' \
      --replace-fail 'start_url: "/",' 'start_url: "/pi/",' \
      --replace-fail 'scope: "/",' 'scope: "/pi/",' \
      --replace-warn 'src: "/icons/' 'src: "/pi/icons/'

    substituteInPlace app/layout.tsx \
      --replace-fail 'manifest: "/manifest.webmanifest"' 'manifest: "/pi/manifest.webmanifest"' \
      --replace-warn 'url: "/icons/' 'url: "/pi/icons/'

    substituteInPlace components/PwaRegistration.tsx \
      --replace-fail '`/sw.js?v=' '`/pi/sw.js?v=' \
      --replace-fail 'scope: "/",' 'scope: "/pi/",'

    substituteInPlace components/ProviderIcon.tsx \
      --replace-fail '`/provider-icons.svg#' '`/pi/provider-icons.svg#'

    substituteInPlace components/FileIcons.tsx \
      --replace-fail '"/icons/catppuccin"' '"/pi/icons/catppuccin"'

    substituteInPlace lib/web-push.ts \
      --replace-fail '`/?session=' '`/pi/?session='

    substituteInPlace public/offline.html \
      --replace-fail 'src="/icons/' 'src="/pi/icons/'

    substituteInPlace public/sw.js \
      --replace-fail 'const OFFLINE_URL = "/offline.html";' 'const OFFLINE_URL = "/pi/offline.html";' \
      --replace-fail '  "/manifest.webmanifest",' '  "/pi/manifest.webmanifest",' \
      --replace-warn '  "/icons/' '  "/pi/icons/' \
      --replace-fail 'url.pathname === "/sw.js"' 'url.pathname === "/pi/sw.js"' \
      --replace-fail 'url.pathname.startsWith("/_next/static/")' 'url.pathname.startsWith("/pi/_next/static/")' \
      --replace-fail 'data: { url: typeof url === "string" && url ? url : "/" }' 'data: { url: typeof url === "string" && url ? url : "/pi/" }' \
      --replace-fail '    : "/";' '    : "/pi/";' \
      --replace-fail 'let targetUrl = new URL("/", self.location.origin);' 'let targetUrl = new URL("/pi/", self.location.origin);'

    if ${lib.getExe ripgrep} --glob '*.{ts,tsx,js,mjs}' '["`]/api(?:[/"`?])' components hooks lib public; then
      echo 'Pi Web still contains a browser API URL outside /pi' >&2
      exit 1
    fi
    if ${lib.getExe ripgrep} --glob '*.{ts,tsx,js,html}' \
      '["`](/sw\.js|/manifest\.webmanifest|/icons/|/provider-icons\.svg|/offline\.html)' \
      app components hooks lib public; then
      echo 'Pi Web still contains a browser asset URL outside /pi' >&2
      exit 1
    fi
  '';

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    ripgrep
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/pi-web"
    cp -r .next bin next.config.ts node_modules package.json public "$out/lib/pi-web/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pi-web" \
      --add-flags "$out/lib/pi-web/bin/pi-web.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          nodejs_24
          ripgrep
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Local web UI for the Pi coding agent";
    homepage = "https://github.com/agegr/pi-web";
    license = lib.licenses.mit;
    mainProgram = "pi-web";
    platforms = lib.platforms.linux;
  };
}
