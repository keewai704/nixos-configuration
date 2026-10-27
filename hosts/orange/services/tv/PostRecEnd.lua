local info = edcb.GetRecFileInfoBasic(tonumber(env.RecInfoID))
local prefix = '@recordings@/'
if info and (info.recStatus == 1 or info.recStatus == 6) and info.scrambles == 0
    and info.recFilePath:sub(1, #prefix) == prefix then
    local path = '@queue@/' .. tostring(info.id) .. '.job'
    local file = assert(io.open(path .. '.new', 'wb'))
    assert(file:write(info.recFilePath, '\0', tostring(info.sid), '\0', tostring(info.id), '\0'))
    assert(file:close())
    assert(os.rename(path .. '.new', path))
end
