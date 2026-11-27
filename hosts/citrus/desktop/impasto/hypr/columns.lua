local most = 3
local pending = {}

local function widths(id)
    local seen, list = {}, {}
    for _, window in ipairs(hl.get_workspace_windows(id) or {}) do
        local layout = window.layout
        if not window.floating and not window.hidden and type(layout) == "table"
            and layout.name == "scrolling" and layout.column and not seen[layout.column.index] then
            seen[layout.column.index] = true
            list[#list + 1] = layout.column.width
        end
    end
    return list
end

local function fit(id)
    local active = hl.get_active_workspace()
    if not id or id < 1 or not active then
        return
    end
    if active.id ~= id then
        pending[id] = true
        return
    end
    pending[id] = nil
    local list = widths(id)
    if #list < 2 or #list > most then
        return
    end
    local target = 1 / #list
    for _, width in ipairs(list) do
        if math.abs(width - target) > 0.005 then
            hl.dispatch(hl.dsp.layout(string.format("colresize all %.4f", target)))
            return
        end
    end
end

local function later(id)
    hl.timer(function()
        fit(id)
    end, { timeout = 1, type = "oneshot" })
end

local function current()
    local active = hl.get_active_workspace()
    later(active and active.id)
end

local function from_window(window)
    local workspace = window and window.workspace
    later(workspace and workspace.id)
    current()
end

hl.on("window.open", from_window)
hl.on("window.close", from_window)
hl.on("window.move_to_workspace", from_window)
hl.on("workspace.active", function(workspace)
    if workspace and pending[workspace.id] then
        later(workspace.id)
    end
end)

return { refit = current }
