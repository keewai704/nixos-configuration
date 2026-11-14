local scratchpad = "special:scratchpad"

local function rebind(combination, action, options)
    hl.unbind(combination)
    hl.bind(combination, action, options)
end

local function toggle_floating()
    local window = hl.get_active_window()
    if not window then
        return
    end
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    if not window.floating then
        hl.dispatch(hl.dsp.window.center())
    end
end

local function switch_floating_focus()
    local window = hl.get_active_window()
    local floating = window ~= nil and window.floating
    hl.dispatch(hl.dsp.window.cycle_next({ tiled = floating, floating = not floating }))
end

local function restore_from_scratchpad()
    local window = hl.get_active_window()
    local monitor = hl.get_active_monitor()
    if window and window.workspace and window.workspace.name == scratchpad
        and monitor and monitor.active_workspace then
        hl.dispatch(hl.dsp.window.move({ workspace = monitor.active_workspace.id }))
    end
end

local function resize_height(fraction)
    return function()
        local monitor = hl.get_active_monitor()
        if not monitor then
            return
        end
        local step = math.floor(monitor.height / (monitor.scale or 1) * fraction)
        hl.dispatch(hl.dsp.window.resize({ x = 0, y = step, relative = true }))
    end
end

rebind("SUPER + Escape", hl.dsp.exec_cmd("hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"),
       { description = "Session · Quit the session" })

rebind("SUPER + H", hl.dsp.focus({ direction = "l" }), { description = "Windows · Focus the window left (H)" })
rebind("SUPER + J", hl.dsp.focus({ direction = "d" }), { description = "Windows · Focus the window down (J)" })
rebind("SUPER + K", hl.dsp.focus({ direction = "u" }), { description = "Windows · Focus the window up (K)" })
rebind("SUPER + L", hl.dsp.focus({ direction = "r" }), { description = "Windows · Focus the window right (L)" })
rebind("SUPER + F1", hl.dsp.window.cycle_next(), { description = "Windows · Focus the next window" })
rebind("SUPER + mouse_up", hl.dsp.layout("focus l"), { description = "Windows · Focus the column left, from the wheel" })
rebind("SUPER + mouse_down", hl.dsp.layout("focus r"), { description = "Windows · Focus the column right, from the wheel" })

rebind("SUPER + SHIFT + left", hl.dsp.layout("swapcol l"), { description = "Windows · Move the column left" })
rebind("SUPER + SHIFT + right", hl.dsp.layout("swapcol r"), { description = "Windows · Move the column right" })
rebind("SUPER + comma", hl.dsp.layout("consume_or_expel prev"), { description = "Windows · Consume into the column left" })
rebind("SUPER + period", hl.dsp.layout("consume_or_expel next"), { description = "Windows · Consume into the column right" })

rebind("SUPER + T", toggle_floating, { description = "Windows · Float or tile the window (T)" })
rebind("SUPER + SHIFT + T", switch_floating_focus, { description = "Windows · Switch focus between floating and tiled" })
rebind("SUPER + P", hl.dsp.window.pin({ action = "toggle" }), { description = "Windows · Pin the window" })
rebind("SUPER + M", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
       { description = "Windows · Maximise to the edges" })
rebind("SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
       { description = "Windows · Maximise" })
rebind("SUPER + R", hl.dsp.layout("colresize +conf"), { description = "Windows · Next column width" })
rebind("SUPER + SHIFT + R", hl.dsp.layout("colresize -conf"), { description = "Windows · Previous column width" })
rebind("SUPER + minus", hl.dsp.layout("colresize -0.02"), { repeating = true, description = "Windows · Narrow the column" })
rebind("SUPER + equal", hl.dsp.layout("colresize +0.02"), { repeating = true, description = "Windows · Widen the column" })
rebind("SUPER + CTRL + minus", resize_height(-0.02), { repeating = true, description = "Windows · Shorten the window" })
rebind("SUPER + CTRL + equal", resize_height(0.02), { repeating = true, description = "Windows · Heighten the window" })

rebind("SUPER + W", hl.dsp.group.toggle(), { description = "Windows · Tab the column" })
rebind("SUPER + ALT + right", hl.dsp.group.next(), { description = "Windows · Next tab" })
rebind("SUPER + ALT + left", hl.dsp.group.prev(), { description = "Windows · Previous tab" })

rebind("SUPER + Space", hl.dsp.workspace.toggle_special("scratchpad"), { description = "Workspaces · Show or hide the scratchpad (Space)" })
rebind("SUPER + SHIFT + Space", hl.dsp.window.move({ workspace = scratchpad, follow = false }),
       { description = "Workspaces · Send the window to the scratchpad" })
rebind("SUPER + CTRL + Space", restore_from_scratchpad, { description = "Workspaces · Bring the window back from the scratchpad" })
rebind("SUPER + TAB", hl.dsp.window.cycle_next(), { description = "Workspaces · Focus the next window (Tab)" })
rebind("SUPER + O", hl.dsp.global("quickshell:overview"), { description = "Shell · Open the workspace overview (O)" })

rebind("SUPER + B", hl.dsp.exec_cmd("bitwarden"), { description = "Applications · Open Bitwarden" })
rebind("ALT + bracketleft", hl.dsp.global("quickshell:brightnessDown"), { repeating = true, description = "Media · Brightness down, from Alt" })
rebind("ALT + bracketright", hl.dsp.global("quickshell:brightnessUp"), { repeating = true, description = "Media · Brightness up, from Alt" })

rebind("SUPER + SHIFT + C", hl.dsp.global("quickshell:palette"), { description = "Shell · Open the palette, from C" })

rebind("Print", hl.dsp.global("quickshell:captureScreen"), { description = "Shell · Capture the whole screen, from Print" })
rebind("ALT + Print", hl.dsp.global("quickshell:captureWindow"), { description = "Shell · Capture a window, from Print" })
rebind("ALT + Sys_Req", hl.dsp.global("quickshell:captureWindow"), { description = "Shell · Capture a window, from Sys_Req" })
rebind("SUPER + SHIFT + S", hl.dsp.global("quickshell:captureRegion"), { description = "Shell · Capture a region, from S" })
