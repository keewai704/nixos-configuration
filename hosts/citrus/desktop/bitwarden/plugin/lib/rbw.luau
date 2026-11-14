--!nonstrict
local M = {}

local function firstLine(text)
  if type(text) ~= "string" then
    return ""
  end
  local value = noctalia.string.trim(text)
  local line = string.match(value, "^[^\n]*")
  return line or ""
end

function M.errorText(result)
  local message = firstLine(result.stderr)
  if message == "" then
    message = firstLine(result.stdout)
  end
  return message
end

local function run(args, cb)
  local started = noctalia.runAsync(args, function(result)
    cb(result.exitCode == 0, result)
  end)
  if not started then
    cb(false, { exitCode = -1, stdout = "", stderr = "" })
  end
end

function M.available()
  return noctalia.commandExists("rbw")
end

function M.config(cb)
  run({ "rbw", "config", "show" }, function(ok, result)
    if not ok then
      cb(false, nil)
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      cb(false, nil)
      return
    end
    cb(true, decoded)
  end)
end

function M.setConfig(key, value, cb)
  run({ "rbw", "config", "set", key, value }, function(ok, result)
    cb(ok, M.errorText(result))
  end)
end

function M.unlocked(cb)
  run({ "rbw", "unlocked" }, function(ok, result)
    cb(ok, M.errorText(result))
  end)
end

function M.unlock(cb)
  run({ "rbw", "unlock" }, function(ok, result)
    cb(ok, M.errorText(result))
  end)
end

function M.lock(cb)
  run({ "rbw", "lock" }, function(ok, result)
    cb(ok, M.errorText(result))
  end)
end

function M.sync(cb)
  run({ "rbw", "sync" }, function(ok, result)
    cb(ok, M.errorText(result))
  end)
end

function M.list(cb)
  run({ "rbw", "list", "--raw" }, function(ok, result)
    if not ok then
      cb(nil, M.errorText(result))
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      cb(nil, M.errorText(result))
      return
    end
    cb(decoded, nil)
  end)
end

function M.get(id, cb)
  run({ "rbw", "get", "--raw", id }, function(ok, result)
    if not ok then
      cb(nil, M.errorText(result))
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" then
      cb(nil, M.errorText(result))
      return
    end
    cb(decoded, nil)
  end)
end

function M.code(id, cb)
  run({ "rbw", "code", id }, function(ok, result)
    if not ok then
      cb(nil)
      return
    end
    local value = noctalia.string.trim(result.stdout)
    if value == "" then
      cb(nil)
      return
    end
    cb(value)
  end)
end

return M
