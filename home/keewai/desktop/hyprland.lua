local main_mod = "SUPER"
local terminal = "uwsm app -- kitty"
local file_manager = "uwsm app -- thunar"

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.monitor({
    output = "desc:Dell Inc. AW3926QW",
    mode = "5120x2160@120",
    position = "auto",
    scale = 1,
    bitdepth = 10,
    cm = "srgb",
    vrr = 2,
})

local sunshine_instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
if sunshine_instance then
    local sunshine_layout = os.getenv("XDG_RUNTIME_DIR")
        .. "/sunshine-display/"
        .. sunshine_instance
        .. "/layout.lua"
    local sunshine_file = io.open(sunshine_layout, "r")
    if sunshine_file then
        sunshine_file:close()
        dofile(sunshine_layout)
    else
        hl.monitor({ output = "SUNSHINE", disabled = true })
    end
end

hl.env("XCURSOR_SIZE", tostring(cursor.size))
hl.env("XCURSOR_THEME", cursor.name)
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

hl.config({
    debug = {
        damage_tracking = "monitor",
    },

    render = {
        cm_auto_hdr = 1,
        direct_scanout = 0,
    },

    general = {
        layout = "master",
        gaps_in = 6,
        gaps_out = 12,
        border_size = 2,
        resize_on_border = true,
        extend_border_grab_area = 12,
        col = {
            active_border = {
                colors = colors.activeBorder,
                angle = 45,
            },
            inactive_border = colors.inactiveBorder,
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
            color = colors.shadow,
            color_inactive = colors.shadowInactive,
            offset = { 0, 2 },
        },
        blur = {
            enabled = true,
            variant = hl.get_config("decoration:blur:variant") and "acrylic" or nil,
            acrylic = {
                clarity = 0.1,
                refraction = 32,
                bulb = 64,
            },
            size = 10,
            passes = 3,
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

    master = {
        orientation = "center",
        mfact = 1 / 3,
        new_status = "slave",
        slave_count_for_center_master = 2,
    },

    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles = true,
        scroll_event_delay = 120,
    },

    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        background_color = colors.background,
        focus_on_activate = true,
    },

    cursor = {
        hide_on_key_press = true,
    },
})

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

hl.window_rule({ match = { class = "^gcr-prompter$" }, tag = "+auth-prompt" })
hl.window_rule({ match = { class = "^pinentry.*$" }, tag = "+auth-prompt" })
hl.window_rule({
    match = { tag = "auth-prompt" },
    float = true,
    center = true,
    pin = true,
    stay_focused = true,
    dim_around = true,
    no_dim = true,
    opacity = "1.0 override 1.0 override",
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
    if island_bind then
        return island_bind(keys, dispatcher, description, flags)
    end
    flags = flags or {}
    flags.description = description
    hl.bind(keys, dispatcher, flags)
end

bind(main_mod .. " + Return", hl.dsp.exec_cmd(terminal), "Open terminal")
bind(main_mod .. " + E", hl.dsp.exec_cmd(file_manager), "Open file manager")
bind(main_mod .. " + Q", hl.dsp.window.close(), "Close window")
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
        "Focus " .. item.label .. " (" .. item.key .. ")"
    )
    bind(
        main_mod .. " + " .. item.arrow,
        hl.dsp.focus({ direction = item.direction }),
        "Focus " .. item.label
    )
    bind(
        main_mod .. " + SHIFT + " .. item.key,
        hl.dsp.window.move({ direction = item.direction }),
        "Move window " .. item.label .. " (" .. item.key .. ")"
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
        "Resize window " .. item.label .. " (" .. item.key .. ")",
        flags
    )
    bind(
        main_mod .. " + CTRL + " .. item.arrow,
        hl.dsp.window.resize({ x = item.x, y = item.y, relative = true }),
        "Resize window " .. item.label,
        { repeating = true }
    )
end

local previous_workspaces = {}
local active_workspaces = {}

for _, monitor in ipairs(hl.get_monitors() or {}) do
    if monitor.active_workspace then
        active_workspaces[monitor.name] = monitor.active_workspace.id
    end
end

hl.on("workspace.active", function(workspace)
    local monitor = workspace and workspace.monitor
    if not monitor then
        return
    end
    local name = monitor.name
    if active_workspaces[name] and active_workspaces[name] ~= workspace.id then
        previous_workspaces[name] = active_workspaces[name]
    end
    active_workspaces[name] = workspace.id
end)

local function to_workspace(workspace)
    return function()
        local monitor = hl.get_active_monitor()
        local active = hl.get_active_workspace()
        local previous = monitor and previous_workspaces[monitor.name]
        local target = workspace
        if active and active.id == workspace and previous and previous ~= workspace then
            target = previous
        end
        hl.dispatch(hl.dsp.focus({ workspace = target, on_current_monitor = true }))
    end
end

for workspace = 1, 10 do
    local key = workspace % 10
    bind(main_mod .. " + " .. key, to_workspace(workspace), "Open workspace " .. workspace)
    bind(
        main_mod .. " + SHIFT + " .. key,
        hl.dsp.window.move({ workspace = workspace, follow = true }),
        "Move window to workspace " .. workspace
    )
end

local function take_workspace(direction)
    return function()
        local here = hl.get_active_monitor()
        if not here then
            return
        end
        hl.dispatch(hl.dsp.focus({ monitor = direction }))
        local there = hl.get_active_monitor()
        if not there or there.name == here.name then
            return
        end
        hl.dispatch(hl.dsp.workspace.swap_monitors({ monitor1 = here.name, monitor2 = there.name }))
    end
end

for _, item in ipairs({
    { key = "left", direction = "l", label = "left" },
    { key = "right", direction = "r", label = "right" },
}) do
    bind(
        main_mod .. " + ALT + " .. item.key,
        hl.dsp.focus({ monitor = item.direction }),
        "Screens · Focus the screen " .. item.label
    )
    bind(
        main_mod .. " + ALT + SHIFT + " .. item.key,
        take_workspace(item.direction),
        "Screens · Take the workspace to the screen " .. item.label
    )
end

bind(main_mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Next workspace")
bind(main_mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Previous workspace")
bind(main_mod .. " + mouse:272", hl.dsp.window.drag(), "Drag window", { mouse = true })
bind(main_mod .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

bind(
    "ALT + bracketleft",
    hl.dsp.global("quickshell:brightnessDown"),
    "Media · Brightness down (Alt)",
    { locked = true, repeating = true }
)
bind(
    "ALT + bracketright",
    hl.dsp.global("quickshell:brightnessUp"),
    "Media · Brightness up (Alt)",
    { locked = true, repeating = true }
)

bind(
    main_mod .. " + SHIFT + E",
    hl.dsp.exec_cmd("uwsm stop"),
    "Log out (hold)",
    { long_press = true }
)
