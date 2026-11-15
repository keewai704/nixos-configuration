{
  impastoPaletteHook,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system24 = "https://refact0r.github.io/system24/build/system24.css";

  quickCss = pkgs.writers.writePython3Bin "equicord-quick-css" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    c = json.load(sys.stdin)


    def mix(color, other, percent):
        return f"color-mix(in oklch, {color}, {other} {percent}%)"


    def fade(color, percent):
        return f"color-mix(in srgb, {color} {percent}%, transparent)"


    background = c["background"]
    surface = c["surface"]
    raised = c["surfaceHover"]
    border = c["border"]
    text = c["text"]
    muted = c["textMuted"]
    subtle = mix(muted, background, 35)
    accent = c["accent"]
    accent_hover = c["accentHover"]
    accent_text = c["accentText"]
    link = mix(accent_hover, text, 35)

    tokens = {
        "background-base-lowest": background,
        "background-base-lower": background,
        "background-base-low": surface,
        "background-surface-high": surface,
        "background-surface-higher": raised,
        "background-surface-highest": raised,
        "background-primary": background,
        "background-secondary": background,
        "background-secondary-alt": surface,
        "background-tertiary": background,
        "background-floating": surface,
        "background-accent": raised,
        "background-brand": accent,
        "background-code": surface,
        "background-mod-subtle": fade(muted, 8),
        "background-mod-muted": fade(muted, 10),
        "background-mod-normal": fade(muted, 16),
        "background-mod-strong": fade(muted, 24),
        "background-feedback-critical": fade(c["red"], 20),
        "background-feedback-info": fade(c["blue"], 20),
        "background-feedback-positive": fade(c["green"], 20),
        "background-feedback-warning": fade(c["yellow"], 20),
        "background-feedback-notification": accent,
        "app-frame-background": background,
        "chat-background-default": background,
        "channeltextarea-background": surface,
        "modal-background": surface,
        "modal-footer-background": background,
        "card-background-default": surface,
        "input-background-default": surface,
        "input-border-default": border,
        "input-border-hover": muted,
        "input-text-default": text,
        "input-placeholder-text-default": subtle,
        "border-subtle": border,
        "border-muted": border,
        "border-normal": border,
        "border-strong": muted,
        "border-focus": accent_hover,
        "text-default": text,
        "text-strong": text,
        "text-normal": text,
        "text-muted": muted,
        "text-subtle": subtle,
        "text-link": link,
        "text-brand": accent_hover,
        "text-feedback-critical": c["red"],
        "text-feedback-info": c["blue"],
        "text-feedback-positive": c["green"],
        "text-feedback-warning": c["yellow"],
        "header-primary": text,
        "header-secondary": muted,
        "channels-default": muted,
        "channel-icon": muted,
        "interactive-text-default": muted,
        "interactive-text-hover": text,
        "interactive-text-active": text,
        "interactive-icon-default": muted,
        "interactive-icon-hover": text,
        "interactive-icon-active": text,
        "interactive-muted": subtle,
        "interactive-normal": muted,
        "interactive-hover": text,
        "interactive-active": text,
        "icon-default": text,
        "icon-strong": text,
        "icon-muted": muted,
        "icon-subtle": subtle,
        "icon-link": link,
        "brand-500": accent,
        "brand-560": accent_hover,
        "brand-360": accent_hover,
        "control-brand-foreground": accent_hover,
        "control-brand-foreground-new": accent_hover,
        "control-primary-background-default": accent,
        "control-primary-background-hover": accent_hover,
        "control-primary-background-active": accent_hover,
        "control-primary-border-default": accent,
        "control-primary-border-hover": accent_hover,
        "control-primary-border-active": accent_hover,
        "control-primary-text-default": accent_text,
        "control-primary-text-hover": accent_text,
        "control-primary-text-active": accent_text,
        "control-primary-icon-default": accent_text,
        "control-primary-icon-hover": accent_text,
        "control-primary-icon-active": accent_text,
        "mention-foreground": accent_hover,
        "mention-background": fade(accent, 25),
        "message-mentioned-background-default": fade(accent, 12),
        "message-mentioned-background-hover": fade(accent, 18),
        "message-highlight-background-default": fade(accent, 12),
        "message-highlight-background-hover": fade(accent, 18),
        "message-background-hover": fade(muted, 6),
        "status-danger": c["red"],
        "status-positive": c["green"],
        "status-warning": c["yellow"],
        "scrollbar-thin-thumb": raised,
        "scrollbar-thin-track": "transparent",
        "scrollbar-auto-thumb": raised,
        "scrollbar-auto-track": "transparent",
    }

    body = "".join(f"    --{name}: {value};\n" for name, value in tokens.items())
    css = f".theme-midnight:not(.custom-user-profile-theme) {{\n{body}}}\n"

    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "Equicord", "settings", "quickCss.css")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(css)
  '';
in
{
  home-manager.users.keewai = {
    imports = [ (impastoPaletteHook "discord" "Equicord/settings/quickCss.css" quickCss) ];

    home.activation.equicordDropSystem24 =
      inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ]
        ''
          settings="''${XDG_CONFIG_HOME:-$HOME/.config}/Equicord/settings/settings.json"
          if [ -s "$settings" ]; then
            merged="$(mktemp "$settings.XXXXXX")"
            ${lib.getExe pkgs.jq} --arg link ${lib.escapeShellArg system24} '.themeLinks |= ((. // []) - [$link])' "$settings" > "$merged"
            run mv "$merged" "$settings"
          fi
        '';

    home.packages = [
      (pkgs.discord.override {
        withEquicord = true;
        inherit (inputs.nixcord.packages.${pkgs.stdenv.hostPlatform.system}) equicord;
      })
    ];
  };
}
