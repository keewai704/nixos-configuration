{
  pkgs,
  ...
}:
let
  appid = "916440";

  launcher = pkgs.writeShellApplication {
    name = "anno1800";
    text = ''
      appid=${appid}
      python=${pkgs.python3}/bin/python3

      prefix="$("$python" - "$appid" <<'PY'
import re
import sys
from pathlib import Path

appid = sys.argv[1]
home = Path.home()

roots = [
    home / ".local/share/Steam",
    home / ".steam/root",
    home / ".steam/debian-installation",
]
libraryfolders = home / ".local/share/Steam/steamapps/libraryfolders.vdf"
if libraryfolders.is_file():
    text = libraryfolders.read_text(encoding="utf-8", errors="ignore")
    roots += [Path(match) for match in re.findall(r'"path"\s*"([^"]+)"', text)]

prefix = None
seen = set()
for root in roots:
    if str(root) in seen:
        continue
    seen.add(str(root))
    candidate = root / "steamapps" / "compatdata" / appid / "pfx"
    if candidate.is_dir():
        prefix = candidate
        break


def indent(line):
    return len(line) - len(line.lstrip())


def patch_forceoffline(path):
    lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
    start = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if indent(line) == 0 and stripped.startswith("user"):
            key, _, rest = stripped.partition(":")
            if key.strip() == "user" and not rest.strip():
                start = index
            break
    if start is None:
        lines = ["user:", "  forceoffline: true", ""] + lines
    else:
        end = len(lines)
        for index in range(start + 1, len(lines)):
            line = lines[index]
            if line.strip() and indent(line) == 0:
                end = index
                break
        for index in range(start + 1, end):
            if lines[index].strip().startswith("forceoffline"):
                lines[index] = "  forceoffline: true"
                break
        else:
            lines.insert(start + 1, "  forceoffline: true")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{path}: user.forceoffline = true", file=sys.stderr)


if prefix is None:
    sys.exit(0)

user = prefix / "drive_c" / "users" / "steamuser"
candidates = [
    user / "AppData" / "Local" / "Ubisoft Game Launcher" / "settings.yml",
    user / "AppData" / "Roaming" / "Ubisoft Game Launcher" / "settings.yml",
]
patched = False
for candidate in candidates:
    if candidate.is_file():
        patch_forceoffline(candidate)
        patched = True
if not patched:
    patch_forceoffline(candidates[0])

print(prefix)
PY
)"

      if [ -z "$prefix" ]; then
        echo "Anno 1800 (AppID $appid) の Proton prefix がありません。Steam からインストールしてください。" >&2
        steam "steam://store/$appid"
        exit 0
      fi

      echo "Proton prefix: $prefix" >&2
      steam "steam://rungameid/$appid"
    '';
  };
in
{
  home-manager.users.keewai.home.packages = [ launcher ];
}
