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
  ponytailVersion = "4.10.0";
  ponytailSource = fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "e3ba2aa6f1e6f0bc4d69eb09c9f0d0a93af56156";
    hash = "sha256-PES5XrSYx0VBXWVHEDRykGy0SAmJfV/luzy8Gfg0aAQ=";
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
