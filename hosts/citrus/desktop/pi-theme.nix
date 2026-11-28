{
  impastoPaletteHook,
  inputs,
  pkgs,
  updateJson,
  ...
}:
let
  theme = "impasto";

  statePath = "impasto/palette-hooks-state/pi";

  writeTheme = pkgs.writers.writePython3Bin "pi-theme" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    c = json.load(sys.stdin)

    colors = {
        "accent": c["accent"],
        "border": c["border"],
        "borderAccent": c["accent"],
        "borderMuted": c["surfaceHover"],
        "success": c["green"],
        "error": c["red"],
        "warning": c["yellow"],
        "muted": c["textMuted"],
        "dim": c["border"],
        "text": "",
        "thinkingText": c["textMuted"],
        "selectedBg": c["surfaceHover"],
        "userMessageBg": c["surface"],
        "userMessageText": c["text"],
        "customMessageBg": c["surface"],
        "customMessageText": c["text"],
        "customMessageLabel": c["accent"],
        "toolPendingBg": c["background"],
        "toolSuccessBg": c["surface"],
        "toolErrorBg": c["surfaceHover"],
        "toolTitle": c["accent"],
        "toolOutput": "",
        "mdHeading": c["accent"],
        "mdLink": c["accentHover"],
        "mdLinkUrl": c["textMuted"],
        "mdCode": c["green"],
        "mdCodeBlock": "",
        "mdCodeBlockBorder": c["surfaceHover"],
        "mdQuote": c["textMuted"],
        "mdQuoteBorder": c["surfaceHover"],
        "mdHr": c["surfaceHover"],
        "mdListBullet": c["accentHover"],
        "toolDiffAdded": c["green"],
        "toolDiffRemoved": c["red"],
        "toolDiffContext": c["textMuted"],
        "syntaxComment": c["border"],
        "syntaxKeyword": c["blue"],
        "syntaxFunction": c["accent"],
        "syntaxVariable": c["text"],
        "syntaxString": c["green"],
        "syntaxNumber": c["accentHover"],
        "syntaxType": c["yellow"],
        "syntaxOperator": c["accentHover"],
        "syntaxPunctuation": c["textMuted"],
        "thinkingOff": c["surfaceHover"],
        "thinkingMinimal": c["border"],
        "thinkingLow": c["accent"],
        "thinkingMedium": c["accentHover"],
        "thinkingHigh": c["accentHover"],
        "thinkingXhigh": c["red"],
        "bashMode": c["green"],
    }

    home = os.path.expanduser("~")
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    document = {
        "$schema": "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
        "name": "${theme}",
        "colors": colors,
    }

    path = os.path.join(home, ".pi", "agent", "themes", "${theme}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
    os.replace(path + ".tmp", path)

    state = os.path.join(config, "${statePath}")
    os.makedirs(os.path.dirname(state), exist_ok=True)
    with open(state, "w", encoding="utf-8") as handle:
        json.dump(c, handle, indent=2)
        handle.write("\n")
  '';
in
{
  home-manager.users.keewai = {
    imports = [ (impastoPaletteHook "pi" "${statePath}" writeTheme) ];

    home.activation.piTheme = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings="$HOME/.pi/agent/settings.json"
      run mkdir -p "$(dirname "$settings")"
      [ -s "$settings" ] || echo '{}' > "$settings"
      run ${updateJson} "$settings" --arg theme "${theme}" '.theme = $theme'
    '';
  };
}
