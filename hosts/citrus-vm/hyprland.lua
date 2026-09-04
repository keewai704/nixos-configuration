-- Hyprland behavior for citrus-vm. The generated configuration prepends the
-- Nix-managed display output and shared theme table.

local main_mod = "SUPER"
local terminal = "uwsm app -- kitty"
local file_manager = "uwsm app -- thunar"
local launcher = "pgrep -x rofi >/dev/null && pkill -x rofi || rofi -show drun"
local wallpaper_picker = "quickshell -n -c hyprquickpaper"
local clipboard = "pgrep -x rofi >/dev/null && pkill -x rofi || cliphist list | rofi -dmenu -p '' | cliphist decode | wl-copy"
local session_menu = "pgrep -x wlogout >/dev/null || wlogout -b 1 -c 20 -r 20 -L 1700 -R 1700 -T 325 -B 325"

hl.monitor({
    output = display_output,
    mode = "1920x1080@60",
    position = "0x0",
    scale = 1,
})

hl.env("XCURSOR_SIZE", tostring(theme.cursor.size))
hl.env("XCURSOR_THEME", theme.cursor.name)

hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 12,
        border_size = 2,
        resize_on_border = true,
        extend_border_grab_area = 12,
        col = {
            active_border = {
                colors = theme.colors.activeBorder,
                angle = 45,
            },
            inactive_border = theme.colors.inactiveBorder,
        },
        snap = {
            enabled = true,
            respect_gaps = true,
        },
    },

    decoration = {
        rounding = 12,
        rounding_power = 2,
        active_opacity = 0.99,
        inactive_opacity = 0.96,
        fullscreen_opacity = 1.0,
        dim_inactive = true,
        dim_strength = 0.03,
        shadow = {
            enabled = true,
            range = 12,
            render_power = 3,
            color = theme.colors.shadow,
            color_inactive = theme.colors.shadowInactive,
            offset = { 0, 2 },
        },
        blur = {
            -- Keep this deliberately light: citrus-vm uses software rendering.
            enabled = true,
            size = 3,
            passes = 1,
            new_optimizations = true,
            ignore_opacity = true,
            noise = 0.01,
            contrast = 0.92,
            brightness = 0.95,
            vibrancy = 0.15,
            popups = true,
            popups_ignorealpha = 0.2,
        },
    },

    input = {
        repeat_rate = 35,
        repeat_delay = 300,
        numlock_by_default = true,
        touchpad = {
            natural_scroll = true,
        },
    },

    dwindle = {
        preserve_split = true,
        precise_mouse_move = true,
    },

    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles = true,
        scroll_event_delay = 120,
    },

    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        background_color = theme.colors.background,
        focus_on_activate = true,
    },

    cursor = {
        hide_on_key_press = true,
    },
})

hl.layer_rule({
    match = { namespace = "rofi" },
    blur = true,
    ignore_alpha = 0.15,
})

hl.curve("quick", {
    type = "bezier",
    points = { { 0.2, 0.9 }, { 0.3, 1.0 } },
})

hl.animation({ leaf = "global", enabled = true, speed = 8, bezier = "quick" })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "quick" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "quick" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "quick" })

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

local function bind(keys, dispatcher, description, flags)
    flags = flags or {}
    flags.description = description
    hl.bind(keys, dispatcher, flags)
end

bind(main_mod .. " + Return", hl.dsp.exec_cmd(terminal), "Open terminal")
bind(main_mod .. " + E", hl.dsp.exec_cmd(file_manager), "Open file manager")
bind(main_mod .. " + Q", hl.dsp.window.close(), "Close window")
bind(
    main_mod .. " + Space",
    hl.dsp.exec_cmd(launcher),
    "Open application launcher"
)
bind(
    main_mod .. " + SHIFT + Space",
    hl.dsp.exec_cmd(wallpaper_picker),
    "Open wallpaper picker"
)
bind(
    main_mod .. " + I",
    hl.dsp.exec_cmd("uwsm app -- pavucontrol"),
    "Open audio controls"
)
bind(
    main_mod .. " + N",
    hl.dsp.exec_cmd("dunstctl history-pop"),
    "Open notification history"
)
bind(
    main_mod .. " + V",
    hl.dsp.exec_cmd(clipboard),
    "Open clipboard history"
)
bind(
    main_mod .. " + SHIFT + W",
    hl.dsp.exec_cmd("systemctl --user --quiet is-active waybar && systemctl --user stop waybar || systemctl --user start waybar"),
    "Toggle Waybar"
)
bind(
    main_mod .. " + ALT + C",
    hl.dsp.exec_cmd(session_menu),
    "Open session menu"
)
bind(
    main_mod .. " + ALT + L",
    hl.dsp.exec_cmd("hyprlock"),
    "Lock session"
)
bind(
    main_mod .. " + F",
    hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    "Toggle fullscreen"
)
bind(
    main_mod .. " + SHIFT + F",
    hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    "Toggle maximize"
)
bind(main_mod .. " + P", hl.dsp.window.pseudo({ action = "toggle" }), "Toggle pseudotiling")
bind(main_mod .. " + O", hl.dsp.layout("togglesplit"), "Toggle split direction")

local directions = {
    { key = "H", arrow = "left", direction = "l", label = "left", x = -30, y = 0 },
    { key = "J", arrow = "down", direction = "d", label = "down", x = 0, y = 30 },
    { key = "K", arrow = "up", direction = "u", label = "up", x = 0, y = -30 },
    { key = "L", arrow = "right", direction = "r", label = "right", x = 30, y = 0 },
}

for _, item in ipairs(directions) do
    bind(
        main_mod .. " + " .. item.key,
        hl.dsp.focus({ direction = item.direction }),
        "Focus " .. item.label
    )
    bind(
        main_mod .. " + " .. item.arrow,
        hl.dsp.focus({ direction = item.direction }),
        "Focus " .. item.label
    )
    bind(
        main_mod .. " + SHIFT + " .. item.key,
        hl.dsp.window.move({ direction = item.direction }),
        "Move window " .. item.label
    )
    bind(
        main_mod .. " + SHIFT + " .. item.arrow,
        hl.dsp.window.move({ direction = item.direction }),
        "Move window " .. item.label
    )
end

for _, item in ipairs(directions) do
    local flags = { repeating = true }
    bind(
        main_mod .. " + CTRL + " .. item.key,
        hl.dsp.window.resize({ x = item.x, y = item.y, relative = true }),
        "Resize window",
        flags
    )
    bind(
        main_mod .. " + CTRL + " .. item.arrow,
        hl.dsp.window.resize({ x = item.x, y = item.y, relative = true }),
        "Resize window",
        { repeating = true }
    )
end

bind(
    main_mod .. " + Tab",
    hl.dsp.focus({ workspace = "previous_per_monitor" }),
    "Previous workspace"
)
bind("ALT + Tab", hl.dsp.exec_cmd("rofi -show window"), "Switch windows")

for workspace = 1, 10 do
    local key = workspace % 10
    bind(
        main_mod .. " + " .. key,
        hl.dsp.focus({ workspace = workspace }),
        "Open workspace " .. workspace
    )
    bind(
        main_mod .. " + SHIFT + " .. key,
        hl.dsp.window.move({ workspace = workspace, follow = true }),
        "Move window to workspace " .. workspace
    )
end

bind(main_mod .. " + S", hl.dsp.workspace.toggle_special("scratchpad"), "Toggle scratchpad")
bind(
    main_mod .. " + SHIFT + S",
    hl.dsp.window.move({ workspace = "special:scratchpad" }),
    "Move window to scratchpad"
)

bind(main_mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Next workspace")
bind(main_mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Previous workspace")
bind(main_mod .. " + mouse:272", hl.dsp.window.drag(), "Drag window", { mouse = true })
bind(main_mod .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"),
    "Raise volume",
    { locked = true, repeating = true }
)
bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    "Lower volume",
    { locked = true, repeating = true }
)
bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    "Toggle audio mute",
    { locked = true }
)
bind(
    "XF86AudioMicMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    "Toggle microphone mute",
    { locked = true }
)
bind(
    "XF86AudioPlay",
    hl.dsp.exec_cmd("playerctl play-pause"),
    "Toggle media playback",
    { locked = true }
)
bind(
    "XF86AudioPause",
    hl.dsp.exec_cmd("playerctl play-pause"),
    "Toggle media playback",
    { locked = true }
)
bind(
    "XF86AudioNext",
    hl.dsp.exec_cmd("playerctl next"),
    "Play next track",
    { locked = true }
)
bind(
    "XF86AudioPrev",
    hl.dsp.exec_cmd("playerctl previous"),
    "Play previous track",
    { locked = true }
)

bind(main_mod .. " + F1", function()
    hl.notification.create({
        text = table.concat({
            "Hyprland shortcuts",
            "Super+Enter: terminal    Super+E: files    Super+Q: close",
            "Super+H/J/K/L: focus    +Shift: move    +Ctrl: resize",
            "Super+1..0: workspace    +Shift: move window",
            "Super+Space: launcher    +Shift: wallpapers    Super+I: audio",
            "Super+N: notifications    Super+V: clipboard",
            "Super+Shift+W: toggle bar",
            "Super+Alt+C: power menu    Super+Alt+L: lock",
            "Super+F: fullscreen",
            "Super+S: scratchpad    Alt+Tab: window picker",
            "Hold Super+Shift+E: log out",
        }, "\n"),
        timeout = 8000,
        color = theme.colors.notification,
        font_size = 15,
    })
end, "Show shortcut help")

bind(
    main_mod .. " + SHIFT + E",
    hl.dsp.exec_cmd("uwsm stop"),
    "Log out (hold)",
    { long_press = true }
)
