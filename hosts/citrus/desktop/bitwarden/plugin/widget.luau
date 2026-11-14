--!nonstrict
local tr = noctalia.tr

local vault = "unknown"

local function draw()
  if vault == "unlocked" then
    barWidget.setGlyph("lock-open")
    barWidget.setTooltip(tr("widget.unlocked"))
  elseif vault == "locked" then
    barWidget.setGlyph("lock")
    barWidget.setTooltip(tr("widget.locked"))
  elseif vault == "setup" then
    barWidget.setGlyph("settings")
    barWidget.setTooltip(tr("widget.setup"))
  else
    barWidget.setGlyph("lock")
    barWidget.setTooltip(tr("widget.unknown"))
  end
end

local function refresh()
  if not noctalia.commandExists("rbw") then
    vault = "setup"
    draw()
    return
  end
  if noctalia.string.trim(noctalia.getConfig("email") or "") == "" then
    vault = "setup"
    draw()
    return
  end
  noctalia.runAsync({ "rbw", "unlocked" }, function(result)
    vault = result.exitCode == 0 and "unlocked" or "locked"
    draw()
  end)
end

noctalia.setUpdateInterval(15000)

noctalia.state.watch("vault", function(value)
  if value == "locked" or value == "unlocked" then
    vault = value
    draw()
  end
end)

function update()
  refresh()
end

function onClick()
  noctalia.togglePanel("keewai/bitwarden:panel")
end

function onRightClick()
  noctalia.runAsync({ "rbw", "lock" }, function()
    vault = "locked"
    draw()
    noctalia.state.set("vault", "locked")
  end)
end

function onIpc(event)
  if event == "refresh" then
    refresh()
  end
end

update()
