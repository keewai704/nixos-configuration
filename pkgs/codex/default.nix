{
  codex,
  stdenv,
  writeText,
  ripgrep,
  bubblewrap,
}:
codex.overrideAttrs (previousAttrs: {
  installPhase = ''
    runHook preInstall
    package="$out/libexec/codex"
    install -Dm755 build/codex "$package/bin/codex"
    install -Dm755 build/codex-code-mode-host "$package/bin/codex-code-mode-host"
    install -Dm755 ${ripgrep}/bin/rg "$package/codex-path/rg"
    install -Dm755 ${bubblewrap}/bin/bwrap "$package/codex-resources/bwrap"
    install -Dm644 ${
      writeText "codex-package.json" (
        builtins.toJSON {
          layoutVersion = 1;
          version = previousAttrs.version;
          target = "${stdenv.hostPlatform.parsed.cpu.name}-unknown-linux-musl";
          variant = "codex";
          entrypoint = "bin/codex";
          resourcesDir = "codex-resources";
          pathDir = "codex-path";
        }
      )
    } "$package/codex-package.json"
    mkdir -p "$out/bin"
    makeWrapper "$package/bin/codex" "$out/bin/codex" \
      --set CODEX_EXECUTABLE_PATH "$out/bin/codex" \
      --set DISABLE_AUTOUPDATER 1
    ln -s ../libexec/codex/bin/codex-code-mode-host "$out/bin/codex-code-mode-host"
    runHook postInstall
  '';
})
