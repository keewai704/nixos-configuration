"""Offline regression check for the 43PR controls; run via system.build.desktop43prCheck."""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    state = root / "state"
    state.mkdir()
    env = os.environ | {
        "PATH": f"{root}:{os.environ['PATH']}",
        "XDG_STATE_HOME": str(state),
        "CHECK_LOG": str(root / "calls"),
    }
    mock = root / "mock"
    mock.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "name = Path(sys.argv[0]).name\n"
        "args = sys.argv[1:]\n"
        "with open(os.environ['CHECK_LOG'], 'a') as log:\n"
        "    log.write(json.dumps([name, *args]) + '\\n')\n"
        "if name == 'hyprctl' and args == ['-j', 'monitors']:\n"
        "    print(os.environ.get('MONITORS', '[{\"name\":\"DP-1\",\"focused\":false},{\"name\":\"DP-2\",\"focused\":true}]'))\n"
        "elif name == 'hyprctl' and len(args) == 2:\n"
        "    print(os.environ.get(args[1].upper(), '100'))\n"
        "elif name == 'pactl':\n"
        "    print('auto_null' if args == ['get-default-sink'] else os.environ.get('SOURCES', '[]'))\n"
        "elif name == 'rofi': print(os.environ['CHOICE'])\n"
        "elif name == 'systemctl' and 'is-active' in args:\n"
        "    sys.exit(int(os.environ.get('INACTIVE', '1')))\n"
    )
    mock.chmod(0o755)
    for name in (
        "hyprctl",
        "pactl",
        "wf-recorder",
        "rofi",
        "systemctl",
        "notify-send",
        "install",
    ):
        (root / name).symlink_to(mock)

    scripts = {}
    for filename in sys.argv[2:]:
        source = Path(filename)
        target = root / source.name
        # Keep the exact generated script, replacing only its dependency PATH for mocks.
        target.write_text(
            re.sub(r"^export PATH=.*\n", "", source.read_text(), flags=re.MULTILINE)
        )
        target.chmod(0o755)
        scripts[source.name] = target

    def run(name, *args, expected=0, **settings):
        (root / "calls").write_text("")
        result = subprocess.run(
            [scripts[name], *args], env=env | settings, capture_output=True, check=False
        )
        assert result.returncode == expected, (name, result.stdout, result.stderr)
        return [json.loads(line) for line in (root / "calls").read_text().splitlines()]

    for action, current, expected in (
        ("up", "100", "100"),
        ("down", "20", "20"),
        ("down", "95.5", "90"),
    ):
        assert run("43pr-display", action, GAMMA=current)[-1] == [
            "hyprctl",
            "hyprsunset",
            "gamma",
            expected,
        ]
    assert run("43pr-display", "night", TEMPERATURE="3000")[-2:] == [
        ["hyprctl", "hyprsunset", "temperature", "6500"],
        ["hyprctl", "hyprsunset", "identity"],
    ]
    assert run("43pr-display", "night", TEMPERATURE="6000")[-1] == [
        "hyprctl",
        "hyprsunset",
        "temperature",
        "3000",
    ]
    run("43pr-display", "invalid", expected=2)
    run("43pr-display", "down", GAMMA="invalid", expected=1)
    calls = run("43pr-opacity", CHOICE="70%")
    assert ["hyprctl", "eval", "apply_43pr_opacity(0.7)"] in calls
    assert (state / "43pr-opacity").read_text() == "0.7\n"
    assert not any(
        c[0] == "hyprctl" for c in run("43pr-opacity", CHOICE="os.execute('false')")
    )
    for inactive, action in (("1", "start"), ("0", "stop")):
        assert run("43pr-recorder", INACTIVE=inactive)[-1] == [
            "systemctl",
            "--user",
            action,
            "43pr-recorder.service",
        ]
    for sources, audio in (
        ("[]", []),
        ('[{"name":"auto_null.monitor"}]', ["--audio=auto_null.monitor"]),
    ):
        calls = run("43pr-record-screen", SOURCES=sources)
        recorder = calls[-1]
        assert recorder[: 1 + len(audio)] == ["wf-recorder", *audio], calls
        assert [arg for arg in recorder if arg.startswith("--audio")] == audio
        assert recorder[recorder.index("--output") + 1] == "DP-2"
    recorder = run("43pr-record-screen", MONITORS='[{"name":"HDMI-A-1"}]')[-1]
    assert recorder[recorder.index("--output") + 1] == "HDMI-A-1"
    calls = run("43pr-record-screen", MONITORS="[]", expected=1)
    assert not any(call[0] == "wf-recorder" for call in calls)

    # Execute the real Lua config with a minimal Hyprland API recorder.
    (state / "hyprland-gui.lua").write_text("gui_loaded = true\n")
    (state / "43pr-opacity").write_text("invalid\n")
    check = root / "check.lua"
    check.write_text("""
local rules, bindings, decoration = {}, {}, {}
local noop = function() end
local dispatcher = setmetatable({}, {__index = function(self) return self end, __call = function() return noop end})
hl = setmetatable({
  dsp = dispatcher,
  config = function(t) if t.decoration then decoration = t.decoration end end,
  window_rule = function(t) if t.name then rules[t.name] = t end end,
  bind = function(key) bindings[key] = true end,
}, {__index = function() return noop end})
package.path = os.getenv("XDG_STATE_HOME") .. "/?.lua;" .. package.path
dofile(arg[1])
assert(gui_loaded)
assert(decoration.active_opacity == 1 and decoration.inactive_opacity == 1)
assert(rules["43pr-opacity"].opacity == "0.9 override")
apply_43pr_opacity(0)
assert(rules["43pr-opacity"].opacity == "0.4 override")
apply_43pr_opacity(2)
assert(tonumber(rules["43pr-opacity"].opacity:match("^[%d.]+")) == 1)
assert(rules["43pr-fullscreen-opacity"].opacity == "1.0 override")
for _, key in ipairs({"SUPER + O", "SUPER + R", "SUPER + W", "XF86MonBrightnessDown", "XF86MonBrightnessUp"}) do
  assert(bindings[key], key)
end
""")
    subprocess.run(["lua", check, sys.argv[1]], env=env, check=True)
    print(
        "43PR controls: opacity, brightness bounds, night mode, recorder audio/toggle, Lua overrides passed"
    )
