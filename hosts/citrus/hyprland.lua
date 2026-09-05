-- Hyprland behavior for citrus. The generated configuration prepends
-- Noctalia IPC and the shared theme table.

local main_mod = "SUPER"
local terminal = "uwsm app -- kitty"
local file_manager = "uwsm app -- thunar"
local function noctalia(action)
    return noctalia_ipc .. action
end

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.monitor({
    output = "desc:Dell Inc. AW3926QW",
    mode = "5120x2160@165",
    position = "auto",
    scale = 1,
    bitdepth = 10,
    cm = "srgb",
    vrr = 2, -- Enable adaptive sync for fullscreen applications.
})

hl.env("XCURSOR_SIZE", tostring(theme.cursor.size))
hl.env("XCURSOR_THEME", theme.cursor.name)
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

hl.config({
    render = {
        cm_auto_hdr = 1, -- Switch to HDR for fullscreen HDR content.
    },

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
        active_opacity = 1.0,
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

hl.window_rule({ match = { class = "firefox" }, opacity = "1.0 override" })

-- XWayland uses Steam app IDs; native Wayland Proton windows expose an xdg tag.
hl.window_rule({ match = { class = "^steam_app_[0-9]+$" }, tag = "+proton-game" })
hl.window_rule({ match = { xdg_tag = "^proton-game$" }, tag = "+proton-game" })
hl.window_rule({
    match = { tag = "proton-game" },
    opacity = "1.0 override 1.0 override 1.0 override",
    border_size = 0,
    rounding = 0,
    decorate = false,
    no_shadow = true,
    no_blur = true,
    no_dim = true,
    no_anim = true,
})

hl.window_rule({
    match = { class = "dev.noctalia.Noctalia" },
    float = true,
    size = { 1080, 920 },
})

hl.layer_rule({
    name = "noctalia",
    match = {
        namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
    },
    no_anim = true,
    ignore_alpha = 0.5,
    blur = true,
    blur_popups = true,
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
bind("Print", hl.dsp.exec_cmd(noctalia("screenshot-region")), "Take region screenshot")
bind("SHIFT + Print", hl.dsp.exec_cmd(noctalia("screenshot-fullscreen all")), "Take full-screen screenshot")
bind("CTRL + Print", hl.dsp.exec_cmd("grimblast --notify copysave active"), "Take active window screenshot")
bind(
    main_mod .. " + Space",
    hl.dsp.exec_cmd(noctalia("panel-toggle launcher")),
    "Open application launcher"
)
bind(
    main_mod .. " + SHIFT + Space",
    hl.dsp.exec_cmd(noctalia("panel-toggle wallpaper")),
    "Open wallpaper picker"
)
bind(
    main_mod .. " + I",
    hl.dsp.exec_cmd(noctalia("panel-toggle control-center")),
    "Open Noctalia Control Center"
)
bind(
    main_mod .. " + N",
    hl.dsp.exec_cmd(noctalia("panel-toggle control-center notifications")),
    "Open notification history"
)
bind(
    main_mod .. " + V",
    hl.dsp.exec_cmd(noctalia("panel-toggle clipboard")),
    "Open clipboard history"
)
bind(
    main_mod .. " + Z",
    hl.dsp.exec_cmd(noctalia("settings-toggle")),
    "Open Noctalia settings"
)
bind(
    main_mod .. " + ALT + C",
    hl.dsp.exec_cmd(noctalia("panel-toggle session")),
    "Open session menu"
)
bind(
    main_mod .. " + ALT + L",
    hl.dsp.exec_cmd(noctalia("session lock")),
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
bind("ALT + Tab", hl.dsp.exec_cmd(noctalia("window-switcher")), "Switch windows")

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
    hl.dsp.exec_cmd(noctalia("volume-up")),
    "Raise volume",
    { locked = true, repeating = true }
)
bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(noctalia("volume-down")),
    "Lower volume",
    { locked = true, repeating = true }
)
bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd(noctalia("volume-mute")),
    "Toggle audio mute",
    { locked = true }
)
bind(
    "XF86AudioMicMute",
    hl.dsp.exec_cmd(noctalia("mic-mute")),
    "Toggle microphone mute",
    { locked = true }
)
bind(
    "XF86AudioPlay",
    hl.dsp.exec_cmd(noctalia("media toggle")),
    "Toggle media playback",
    { locked = true }
)
bind(
    "XF86AudioPause",
    hl.dsp.exec_cmd(noctalia("media toggle")),
    "Toggle media playback",
    { locked = true }
)
bind(
    "XF86AudioNext",
    hl.dsp.exec_cmd(noctalia("media next")),
    "Play next track",
    { locked = true }
)
bind(
    "XF86AudioPrev",
    hl.dsp.exec_cmd(noctalia("media previous")),
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
            "Super+Space: launcher    +Shift: wallpapers    Super+I: controls",
            "Super+N: notifications    Super+V: clipboard",
            "Print: region    Shift+Print: all screens    Ctrl+Print: active window",
            "Super+Z: Noctalia settings",
            "Super+Alt+C: session    Super+Alt+L: lock",
            "Super+F: fullscreen",
            "Super+S: scratchpad    Alt+Tab: cycle windows",
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
