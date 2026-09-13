{
  lib,
  coreutils,
  fetchFromGitHub,
  nodejs,
  runCommand,
  symlinkJoin,
  writeShellApplication,
  writeText,
}:
let
  ponytailVersion = "4.9.0";
  ponytailSource = fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "2ed6c52c9d7e5e56942508591085fd45dea277d3";
    hash = "sha256-bGdXvzhWPwGdz3T2Yh2h6lf+3PBRFAfdBxP5pESmCHI=";
  };
  ponytailHookContext = writeText "ponytail-hook-context.md" ''
    Ponytail applies to coding work only. When coding or explicitly asked to
    use Ponytail, read /etc/codex/skills/ponytail/SKILL.md if it is not already
    available in the current context, and use the active level above. For other
    work, do not load it. Mode changes and off commands remain available.
  '';
  ponytailHookRoot =
    runCommand "ponytail-hooks-${ponytailVersion}"
      {
        nativeBuildInputs = [ nodejs ];
      }
      ''
        mkdir -p "$out/hooks" "$out/skills/ponytail"

        for script in \
          ponytail-activate.js \
          ponytail-config.js \
          ponytail-instructions.js \
          ponytail-mode-tracker.js \
          ponytail-runtime.js; do
          install -Dm644 "${ponytailSource}/hooks/$script" "$out/hooks/$script"
          node --check "$out/hooks/$script"
        done

        install -Dm644 \
          "${ponytailHookContext}" \
          "$out/skills/ponytail/SKILL.md"
        install -Dm644 "${ponytailSource}/LICENSE" "$out/LICENSE"

        node --test "${ponytailSource}/tests/hooks.test.js"
      '';

  mkPonytailHook =
    name:
    writeShellApplication {
      name = "ponytail-${name}";
      runtimeInputs = [ coreutils ];
      text = ''
        pluginData="''${XDG_STATE_HOME:-$HOME/.local/state}/codex/plugins/ponytail"
        mkdir -p "$pluginData"

        export PLUGIN_ROOT=${lib.escapeShellArg "${ponytailHookRoot}"}
        export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
        export PLUGIN_DATA="$pluginData"
        export CLAUDE_PLUGIN_DATA="$pluginData"

        exec ${lib.getExe nodejs} ${lib.escapeShellArg "${ponytailHookRoot}/hooks/ponytail-${name}.js"}
      '';
    };

in
symlinkJoin {
  name = "ponytail-managed-hooks-${ponytailVersion}";
  paths = map mkPonytailHook [
    "activate"
    "mode-tracker"
  ];
}
