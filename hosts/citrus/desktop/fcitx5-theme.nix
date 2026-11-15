{
  impastoPaletteHook,
  lib,
  pkgs,
  ...
}:
let
  theme = "impasto";

  statePath = "impasto/palette-hooks-state/fcitx5";

  reload = lib.getExe' pkgs.dbus "dbus-send";

  writeTheme = pkgs.writers.writePython3Bin "fcitx5-theme" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import subprocess
    import sys

    c = json.load(sys.stdin)

    conf = f"""[Metadata]
    Name=${theme}
    Version=1
    Author=impasto
    Description=impasto palette theme
    ScaleWithDPI=True

    [InputPanel]
    NormalColor={c["text"]}
    HighlightCandidateColor={c["accentText"]}
    HighlightColor={c["accentText"]}
    HighlightBackgroundColor={c["accent"]}
    FullWidthHighlight=True
    PageButtonAlignment=Last Candidate

    [InputPanel/TextMargin]
    Left=9
    Right=9
    Top=6
    Bottom=7

    [InputPanel/ContentMargin]
    Left=9
    Right=9
    Top=7
    Bottom=7

    [InputPanel/Background]
    Color={c["background"]}
    BorderColor={c["border"]}
    BorderWidth=0
    Image=panel.svg

    [InputPanel/Background/Margin]
    Left=15
    Right=15
    Top=15
    Bottom=15

    [InputPanel/Highlight]
    Color={c["accent"]}
    Image=highlight.svg

    [InputPanel/Highlight/Margin]
    Left=15
    Right=15
    Top=10
    Bottom=10

    [InputPanel/PrevPage]
    Image=prev.svg

    [InputPanel/PrevPage/ClickMargin]
    Left=5
    Right=5
    Top=4
    Bottom=4

    [InputPanel/NextPage]
    Image=next.svg

    [InputPanel/NextPage/ClickMargin]
    Left=5
    Right=5
    Top=4
    Bottom=4

    [Menu]
    NormalColor={c["text"]}
    HighlightCandidateColor={c["accentText"]}
    Spacing=2

    [Menu/Background]
    Color={c["background"]}
    BorderColor={c["border"]}
    BorderWidth=0
    Image=panel.svg

    [Menu/Background/Margin]
    Left=15
    Right=15
    Top=15
    Bottom=15

    [Menu/ContentMargin]
    Left=11
    Right=11
    Top=11
    Bottom=11

    [Menu/CheckBox]
    Image=highlight.svg

    [Menu/Highlight]
    Color={c["accent"]}
    Image=highlight.svg

    [Menu/Highlight/Margin]
    Left=15
    Right=15
    Top=5
    Bottom=5

    [Menu/Separator]
    Color={c["textMuted"]}

    [Menu/SubMenu]
    Image=next.svg

    [Menu/TextMargin]
    Left=6
    Right=6
    Top=6
    Bottom=6

    [AccentColorField]
    0=Input Panel Border
    1=Input Panel Highlight Candidate Background
    2=Input Panel Highlight
    3=Menu Border
    4=Menu Separator
    5=Menu Selected Item Background
    """

    panel = f"""<?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="31" height="31" viewBox="0 0 62 62">
      <rect x="1" y="1" width="60" height="60" rx="12" ry="12" fill="{c["background"]}" stroke="{c["border"]}" stroke-width="2"/>
    </svg>
    """

    highlight = f"""<?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="31" height="31" viewBox="0 0 62 62">
      <rect x="8" y="8" width="46" height="46" rx="14" ry="14" fill="{c["accent"]}"/>
    </svg>
    """

    previous = f"""<?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="20" viewBox="0 0 4.2333334 5.2916667">
      <path d="M 2.91,4.23 L 1.32,2.65 L 2.91,1.06 Z" fill="{c["textMuted"]}"/>
    </svg>
    """

    following = f"""<?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="20" viewBox="0 0 4.2333334 5.2916667">
      <path d="M 1.32,1.06 L 2.91,2.65 L 1.32,4.23 Z" fill="{c["textMuted"]}"/>
    </svg>
    """

    home = os.path.expanduser("~")
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    files = {
        "theme.conf": conf,
        "panel.svg": panel,
        "highlight.svg": highlight,
        "prev.svg": previous,
        "next.svg": following,
    }

    directory = os.path.join(data, "fcitx5", "themes", "${theme}")
    os.makedirs(directory, exist_ok=True)
    for name, content in files.items():
        with open(os.path.join(directory, name), "w", encoding="utf-8") as handle:
            handle.write(content)

    state = os.path.join(config, "${statePath}")
    os.makedirs(os.path.dirname(state), exist_ok=True)
    with open(state, "w", encoding="utf-8") as handle:
        json.dump(c, handle, indent=2)
        handle.write("\n")

    try:
        subprocess.run(
            [
                "${reload}",
                "--session",
                "--dest=org.fcitx.Fcitx5",
                "--type=method_call",
                "/controller",
                "org.fcitx.Fcitx.Controller1.ReloadAddonConfig",
                "string:classicui",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        pass
  '';
in
{
  i18n.inputMethod.fcitx5.settings.addons.classicui.globalSection = {
    Theme = theme;
    DarkTheme = theme;
    UseDarkTheme = "False";
    Font = "Noto Sans CJK JP 10";
    MenuFont = "Noto Sans CJK JP 10";
    TrayFont = "Noto Sans CJK JP Bold 10";
  };

  home-manager.users.keewai.imports = [
    (impastoPaletteHook "fcitx5" "${statePath}" writeTheme)
  ];
}
