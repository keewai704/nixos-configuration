-- Hyprland behavior for citrus. The generated configuration prepends
-- the shared theme table.

local main_mod = "SUPER"
local terminal = "uwsm app -- kitty"
local file_manager = "uwsm app -- thunar"

-- Lock once after login, including greetd's automatic initial session.
hl.on("hyprland.start", function()
    hl.exec_cmd("island-action lock")
end)

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
        active_opacity = 0.92,
        inactive_opacity = 0.88,
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
            -- Keep reloads valid on the old compositor until the next login.
            variant = hl.get_config("decoration:blur:variant") and "acrylic" or nil,
            size = 8,
            passes = 2,
            new_optimizations = true,
            ignore_opacity = true,
            noise = 0.005,
            contrast = 0.92,
            brightness = 1.0,
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
bind(main_mod .. " + D", hl.dsp.exec_cmd("islandctl toggle"), "Toggle Dynamic Island")
bind(main_mod .. " + SHIFT + Z", hl.dsp.exec_cmd("islandctl settings"), "Open Island settings")
bind("Print", hl.dsp.exec_cmd("island-action screenshot-region"), "Take region screenshot")
bind("SHIFT + Print", hl.dsp.exec_cmd("island-action screenshot-all"), "Take full-screen screenshot")
bind("CTRL + Print", hl.dsp.exec_cmd("island-action screenshot-active"), "Take active window screenshot")
bind(
    main_mod .. " + Space",
    hl.dsp.exec_cmd("islandctl launcher"),
    "Open application launcher"
)
bind(
    main_mod .. " + SHIFT + Space",
    hl.dsp.exec_cmd("islandctl wallpaper"),
    "Open wallpaper picker"
)
bind(
    main_mod .. " + I",
    hl.dsp.exec_cmd("islandctl controls"),
    "Open Island Control Center"
)
bind(
    main_mod .. " + N",
    hl.dsp.exec_cmd("islandctl notifications"),
    "Open notification history"
)
bind(
    main_mod .. " + V",
    hl.dsp.exec_cmd("islandctl clipboard"),
    "Open clipboard history"
)
bind(
    main_mod .. " + Z",
    hl.dsp.exec_cmd("islandctl settings"),
    "Open Island settings"
)
bind(
    main_mod .. " + ALT + C",
    hl.dsp.exec_cmd("islandctl session"),
    "Open session menu"
)
bind(
    main_mod .. " + ALT + L",
    hl.dsp.exec_cmd("islandctl lock"),
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
bind("ALT + Tab", hl.dsp.exec_cmd("islandctl windows"), "Switch windows")

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
    hl.dsp.exec_cmd("islandctl volumeUp"),
    "Raise volume",
    { locked = true, repeating = true }
)
bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd("islandctl volumeDown"),
    "Lower volume",
    { locked = true, repeating = true }
)
bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd("islandctl mute"),
    "Toggle audio mute",
    { locked = true }
)
bind(
    "XF86AudioMicMute",
    hl.dsp.exec_cmd("islandctl micMute"),
    "Toggle microphone mute",
    { locked = true }
)
bind(
    "XF86AudioPlay",
    hl.dsp.exec_cmd("islandctl playPause"),
    "Toggle media playback",
    { locked = true }
)
bind(
    "XF86AudioPause",
    hl.dsp.exec_cmd("islandctl playPause"),
    "Toggle media playback",
    { locked = true }
)
bind(
    "XF86AudioNext",
    hl.dsp.exec_cmd("islandctl next"),
    "Play next track",
    { locked = true }
)
bind(
    "XF86AudioPrev",
    hl.dsp.exec_cmd("islandctl previous"),
    "Play previous track",
    { locked = true }
)

bind(
    "ALT + bracketleft",
    hl.dsp.exec_cmd("islandctl brightnessDown"),
    "Lower brightness",
    { locked = true, repeating = true }
)
bind(
    "ALT + bracketright",
    hl.dsp.exec_cmd("islandctl brightnessUp"),
    "Raise brightness",
    { locked = true, repeating = true }
)
bind(
    "XF86MonBrightnessDown",
    hl.dsp.exec_cmd("islandctl brightnessDown"),
    "Lower brightness",
    { locked = true, repeating = true }
)
bind(
    "XF86MonBrightnessUp",
    hl.dsp.exec_cmd("islandctl brightnessUp"),
    "Raise brightness",
    { locked = true, repeating = true }
)

bind(main_mod .. " + F1", function()
    hl.notification.create({
        text = table.concat({
            "Hyprland shortcuts",
            "Super+Enter: terminal    Super+E: files    Super+Q: close",
            "Super+H/J/K/L: focus    +Shift: move    +Ctrl: resize",
            "Super+1..0: workspace    +Shift: move window",
            "Super+Space: launcher    +Shift: wallpapers    Super+I: controls",
            "Super+N: notifications    Super+V: clipboard    Super+Z: settings",
            "Print: region    Shift+Print: all screens    Ctrl+Print: active window",
            "Super+D: Dynamic Island    Super+Shift+Z: Island settings",
            "Super+Alt+C: session    Super+Alt+L: lock",
            "Alt+[: brightness down    Alt+]: brightness up",
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
