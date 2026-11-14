--!nonstrict
local rbw = require("./lib/rbw.luau")
local format = require("./lib/format.luau")

local tr = noctalia.tr
local TOTP_PERIOD = 30

local settings = { email = "", baseUrl = "", syncOnUnlock = true, lockOnClose = false }
local view = "checking"
local lastError = ""
local notice = ""
local items = {}
local details = {}
local selectedId = nil
local revealed = {}
local totpCode = nil
local totpRemaining = -1
local search = ""
local filterIndex = 0
local filterKinds = {}
local filterOptions = {}
local detailQueue = {}
local detailWaiters = {}
local detailBusy = false
local clipboardClearAt = nil
local clearSeconds = 30
local searchKey = 0
local showCloseButton = true

local render
local copyToClipboard

local function secondsLeft()
  return TOTP_PERIOD - (os.time() % TOTP_PERIOD)
end

local function copyButton(value, label)
  return ui.button({
    glyph = "copy",
    variant = "ghost",
    controlSize = "sm",
    tooltip = tr("action.copy"),
    onClick = function()
      copyToClipboard(value, label)
    end,
  })
end

local function openButton(uri)
  return ui.button({
    glyph = "external-link",
    variant = "ghost",
    controlSize = "sm",
    tooltip = tr("action.open"),
    onClick = function()
      noctalia.runAsync({ "xdg-open", uri })
    end,
  })
end

local function fieldRow(key, label, value, actions, options)
  options = options or {}
  local rowChildren = {
    ui.label({
      text = value,
      fontSize = 13,
      color = options.color or "on_surface",
      flexGrow = 1,
      maxLines = options.maxLines or 2,
    }),
  }
  for _, action in ipairs(actions or {}) do
    table.insert(rowChildren, action)
  end
  return ui.column({ key = key, gap = 2, align = "stretch" }, {
    ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
    ui.row({ align = "center", gap = 6 }, rowChildren),
  })
end

local function maskedRow(key, label, secret, hiddenText, shownText)
  local isRevealed = revealed[key] == true
  local actions = {
    ui.button({
      glyph = isRevealed and "eye-off" or "eye",
      variant = "ghost",
      controlSize = "sm",
      tooltip = isRevealed and tr("action.hide") or tr("action.reveal"),
      onClick = function()
        revealed[key] = not isRevealed
        render()
      end,
    }),
    copyButton(secret, label),
  }
  return fieldRow(key, label, isRevealed and shownText or hiddenText, actions, {
    maxLines = isRevealed and 8 or 1,
  })
end

local function section(title, children)
  return ui.column({ gap = 8, align = "stretch" }, {
    ui.label({ text = title, fontSize = 13, fontWeight = "medium", color = "on_surface_variant" }),
    ui.column({
      gap = 10,
      align = "stretch",
      padding = 12,
      radius = 12,
      fill = "surface_container/0.6",
      border = "outline_variant/0.4",
      borderWidth = 1,
    }, children),
  })
end

local function chip(glyph, text, key)
  return ui.row({
    key = key,
    gap = 4,
    align = "center",
    paddingH = 8,
    paddingV = 3,
    radius = 8,
    fill = "surface_container/0.8",
  }, {
    ui.glyph({ name = glyph, size = 13, color = "on_surface_variant" }),
    ui.label({ text = text, fontSize = 11, color = "on_surface_variant" }),
  })
end

local function addAll(target, values)
  for _, value in ipairs(values or {}) do
    table.insert(target, value)
  end
end

local function itemById(id)
  for _, item in ipairs(items) do
    if item.id == id then
      return item
    end
  end
  return nil
end

local function entryTypeOf(item, detail)
  if item ~= nil and type(item.type) == "string" then
    return item.type
  end
  local data = detail ~= nil and detail.data or nil
  if type(data) ~= "table" then
    return "Note"
  end
  if data.cardholder_name ~= nil or data.number ~= nil or data.brand ~= nil then
    return "Card"
  end
  if data.public_key ~= nil or data.private_key ~= nil then
    return "SSH Key"
  end
  if data.first_name ~= nil or data.last_name ~= nil or data.ssn ~= nil or data.address1 ~= nil then
    return "Identity"
  end
  if data.username ~= nil or data.password ~= nil or data.totp ~= nil or data.uris ~= nil then
    return "Login"
  end
  return "Note"
end

local function matchesSearch(item)
  if search == "" then
    return true
  end
  local needle = string.lower(search)
  local function hit(value)
    return type(value) == "string" and string.find(string.lower(value), needle, 1, true) ~= nil
  end
  if hit(item.name) or hit(item.user) or hit(item.folder) then
    return true
  end
  if type(item.uris) == "table" then
    for _, uri in ipairs(item.uris) do
      if hit(uri) then
        return true
      end
    end
  end
  return false
end

local function passesFilter(item)
  local kind = filterKinds[filterIndex + 1]
  if kind == nil or kind == "all" then
    return true
  end
  if string.sub(kind, 1, 7) == "folder:" then
    return item.folder == string.sub(kind, 8)
  end
  return item.type == kind
end

local function rebuildFilters()
  local folders = {}
  local seen = {}
  for _, item in ipairs(items) do
    local folder = format.nonEmpty(item.folder)
    if folder ~= nil and seen[folder] == nil then
      seen[folder] = true
      table.insert(folders, folder)
    end
  end
  table.sort(folders)
  filterOptions = {
    tr("filter.all"),
    tr("filter.login"),
    tr("filter.card"),
    tr("filter.identity"),
    tr("filter.note"),
    tr("filter.ssh"),
  }
  filterKinds = { "all", "Login", "Card", "Identity", "Note", "SSH Key" }
  for _, folder in ipairs(folders) do
    table.insert(filterOptions, tr("filter.folder", { name = folder }))
    table.insert(filterKinds, "folder:" .. folder)
  end
  if filterIndex > #filterOptions - 1 then
    filterIndex = 0
  end
end

local function itemSubtitle(item)
  local detail = details[item.id]
  local data = detail ~= nil and detail.data or nil
  local entryType = entryTypeOf(item, detail)
  if entryType == "Login" then
    return format.nonEmpty(item.user) or tr("list.no_username")
  end
  if entryType == "Card" then
    local brand = type(data) == "table" and format.nonEmpty(data.brand) or nil
    local number = type(data) == "table" and format.nonEmpty(data.number) or nil
    if brand ~= nil and number ~= nil then
      return brand .. " " .. format.repeatBullet(4) .. " " .. string.sub(format.onlyDigits(number), -4)
    end
    if brand ~= nil then
      return brand
    end
    return format.nonEmpty(item.folder) or tr("type.card")
  end
  if entryType == "Identity" then
    if type(data) == "table" then
      local name = format.identityName(data)
      if name ~= "" then
        return name
      end
    end
    return format.nonEmpty(item.folder) or tr("type.identity")
  end
  if entryType == "SSH Key" then
    local user = format.nonEmpty(item.user)
    if user ~= nil then
      return user
    end
    return format.nonEmpty(item.folder) or tr("type.ssh")
  end
  return format.nonEmpty(item.folder) or tr("type.note")
end

local pumpDetails

local function loadDetail(id, callback)
  local cached = details[id]
  if cached ~= nil then
    callback(cached, nil)
    return
  end
  local waiters = detailWaiters[id]
  if waiters == nil then
    waiters = {}
    detailWaiters[id] = waiters
    table.insert(detailQueue, id)
  end
  table.insert(waiters, callback)
  pumpDetails()
end

pumpDetails = function()
  if detailBusy then
    return
  end
  local id = table.remove(detailQueue, 1)
  if id == nil then
    return
  end
  detailBusy = true
  rbw.get(id, function(value, message)
    detailBusy = false
    if value ~= nil then
      details[id] = value
    end
    local waiters = detailWaiters[id] or {}
    detailWaiters[id] = nil
    for _, callback in ipairs(waiters) do
      callback(value, message)
    end
    if view == "ready" then
      render()
    end
    pumpDetails()
  end)
end

local function fetchTotp(id)
  rbw.code(id, function(code)
    if selectedId ~= id then
      return
    end
    totpCode = code
    totpRemaining = secondsLeft()
    render()
  end)
end

local function selectItem(id)
  if selectedId == id then
    return
  end
  selectedId = id
  revealed = {}
  totpCode = nil
  totpRemaining = -1
  render()
  loadDetail(id, function(detail)
    if selectedId ~= id or detail == nil then
      return
    end
    if type(detail.data) == "table" and format.nonEmpty(detail.data.totp) ~= nil then
      fetchTotp(id)
    end
    render()
  end)
end

local function startEnrich()
  local queued = 0
  for _, item in ipairs(items) do
    if queued >= 80 then
      return
    end
    if item.type == "Card" or item.type == "Identity" then
      if details[item.id] == nil then
        queued = queued + 1
        loadDetail(item.id, function() end)
      end
    end
  end
end

local function startList(withSync)
  view = "syncing"
  lastError = ""
  notice = ""
  render()
  local function finish()
    rbw.list(function(list, message)
      if list == nil then
        lastError = message
        view = "error"
        render()
        return
      end
      items = list
      details = {}
      detailQueue = {}
      detailWaiters = {}
      rebuildFilters()
      if selectedId ~= nil and itemById(selectedId) == nil then
        selectedId = nil
        totpCode = nil
      end
      view = "ready"
      if notice == "" then
        notice = tr("header.count", { count = #items })
      end
      render()
      if selectedId ~= nil then
        local id = selectedId
        selectedId = nil
        selectItem(id)
      end
      startEnrich()
    end)
  end
  if withSync then
    rbw.sync(function(ok, message)
      if not ok then
        notice = message
      end
      finish()
    end)
  else
    finish()
  end
end

local function lockedBody(message)
  local text = noctalia.string.trim(message or "")
  local lowered = string.lower(text)
  if text == "" or string.find(lowered, "not running", 1, true) ~= nil or string.find(lowered, "locked", 1, true) ~= nil then
    return tr("state.locked_body")
  end
  return text
end

local function publishVault(value)
  noctalia.state.set("vault", value)
end

local function loadSettings()
  settings.email = noctalia.string.trim(noctalia.getConfig("email") or "")
  settings.baseUrl = noctalia.string.trim(noctalia.getConfig("base_url") or "")
  settings.syncOnUnlock = noctalia.getConfig("sync_on_unlock") ~= false
  settings.lockOnClose = noctalia.getConfig("lock_on_close") == true
  clearSeconds = tonumber(noctalia.getConfig("clear_clipboard_seconds")) or 0
end

copyToClipboard = function(value, label)
  if type(value) ~= "string" or value == "" then
    return
  end
  if not noctalia.copyToClipboard(value, "text/plain") then
    noctalia.notifyError(tr("title"), tr("error.copy_failed"))
    return
  end
  if clearSeconds > 0 then
    clipboardClearAt = os.time() + clearSeconds
  end
  noctalia.notify(tr("title"), tr("notice.copied", { label = label }))
end

local function resetSensitive()
  items = {}
  details = {}
  detailQueue = {}
  detailWaiters = {}
  detailBusy = false
  selectedId = nil
  revealed = {}
  totpCode = nil
  totpRemaining = -1
  search = ""
  filterIndex = 0
  clipboardClearAt = nil
end

local function ensureConfig(callback)
  rbw.config(function(ok, config)
    local currentEmail = ok and type(config) == "table" and config.email or nil
    local currentBase = ok and type(config) == "table" and config.base_url or nil
    if currentEmail == settings.email and (settings.baseUrl == "" or currentBase == settings.baseUrl) then
      callback(nil)
      return
    end
    rbw.setConfig("email", settings.email, function(emailOk, emailError)
      if not emailOk then
        callback(emailError ~= "" and emailError or tr("error.config_failed"))
        return
      end
      if settings.baseUrl == "" then
        callback(nil)
        return
      end
      rbw.setConfig("base_url", settings.baseUrl, function(baseOk, baseError)
        if not baseOk then
          callback(baseError ~= "" and baseError or tr("error.config_failed"))
          return
        end
        callback(nil)
      end)
    end)
  end)
end

local function checkVault()
  view = "checking"
  lastError = ""
  notice = ""
  render()
  if not rbw.available() then
    view = "no_rbw"
    render()
    return
  end
  if settings.email == "" then
    view = "setup"
    render()
    return
  end
  ensureConfig(function(configError)
    if configError ~= nil then
      lastError = configError
      view = "error"
      render()
      return
    end
    rbw.unlocked(function(ok, message)
      if ok then
        publishVault("unlocked")
        startList(false)
        return
      end
      publishVault("locked")
      lastError = lockedBody(message)
      view = "locked"
      render()
    end)
  end)
end

local function startUnlock()
  if view == "unlocking" then
    return
  end
  view = "unlocking"
  lastError = ""
  render()
  rbw.unlock(function(ok, message)
    if not ok then
      publishVault("locked")
      lastError = message ~= "" and message or tr("error.unlock_failed")
      view = "locked"
      render()
      return
    end
    publishVault("unlocked")
    startList(settings.syncOnUnlock)
  end)
end

local function startLock()
  rbw.lock(function()
    publishVault("locked")
    resetSensitive()
    lastError = ""
    notice = ""
    view = "locked"
    render()
  end)
end

local function startSync()
  if view ~= "ready" then
    return
  end
  startList(true)
end

local function detailHeader(item, detail)
  local entryType = entryTypeOf(item, detail)
  local folder = format.nonEmpty(detail.folder) or format.nonEmpty(item ~= nil and item.folder or nil)
  local chips = {
    chip(format.typeGlyph(entryType), tr(format.typeKey(entryType)), "chip:type"),
    chip("folder", folder or tr("detail.no_folder"), "chip:folder"),
  }
  return ui.column({ gap = 8, align = "stretch" }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = format.typeGlyph(entryType), size = 24, color = "primary" }),
      ui.label({ text = detail.name or "", fontSize = 18, fontWeight = "bold", flexGrow = 1, maxLines = 2 }),
    }),
    ui.row({ gap = 6, align = "center" }, chips),
  })
end

local function loginCredentialsSection(detail)
  local data = type(detail.data) == "table" and detail.data or {}
  local rows = {}
  local username = format.nonEmpty(data.username)
  if username ~= nil then
    table.insert(rows, fieldRow("login:username", tr("field.username"), username, {
      copyButton(username, tr("field.username")),
    }))
  end
  local password = format.nonEmpty(data.password)
  if password ~= nil then
    table.insert(rows, maskedRow("login:password", tr("field.password"), password, format.mask(), password))
  end
  if format.nonEmpty(data.totp) ~= nil then
    local actions = {}
    if totpCode ~= nil then
      table.insert(actions, ui.label({ text = tostring(math.max(totpRemaining, 0)) .. "s", fontSize = 11, color = "on_surface_variant" }))
      table.insert(actions, copyButton(totpCode, tr("field.totp")))
    end
    local display = format.mask()
    if totpCode ~= nil then
      display = #totpCode == 6 and (string.sub(totpCode, 1, 3) .. " " .. string.sub(totpCode, 4, 6)) or totpCode
    end
    table.insert(rows, fieldRow("login:totp", tr("field.totp"), display, actions))
  end
  if #rows == 0 then
    return nil
  end
  return section(tr("section.login_credentials"), rows)
end

local function autofillSection(detail)
  local data = type(detail.data) == "table" and detail.data or {}
  local uris = data.uris
  if type(uris) ~= "table" or #uris == 0 then
    return nil
  end
  local rows = {}
  for index, entry in ipairs(uris) do
    local uri = type(entry) == "table" and entry.uri or entry
    if format.nonEmpty(uri) ~= nil then
      local actions = {}
      if string.match(uri, "^https?://") ~= nil then
        table.insert(actions, openButton(uri))
      end
      table.insert(actions, copyButton(uri, tr("field.website")))
      local label = index == 1 and tr("field.website") or tr("field.website_index", { index = index })
      table.insert(rows, fieldRow("uri:" .. tostring(index), label, uri, actions))
    end
  end
  if #rows == 0 then
    return nil
  end
  return section(tr("section.autofill"), rows)
end

local function cardSection(detail)
  local card = type(detail.data) == "table" and detail.data or {}
  local rows = {}
  local cardholder = format.nonEmpty(card.cardholder_name)
  if cardholder ~= nil then
    table.insert(rows, fieldRow("card:cardholder", tr("field.cardholder_name"), cardholder, {
      copyButton(cardholder, tr("field.cardholder_name")),
    }))
  end
  local number = format.nonEmpty(card.number)
  if number ~= nil then
    table.insert(rows, maskedRow("card:number", tr("field.number"), number, format.maskCardNumber(number), format.cardNumber(number)))
  end
  local expiration = format.expiry(card.exp_month, card.exp_year)
  if expiration ~= nil then
    table.insert(rows, fieldRow("card:expiration", tr("field.expiration"), expiration, {}))
  end
  local code = format.nonEmpty(card.code)
  if code ~= nil then
    table.insert(rows, maskedRow("card:code", tr("field.security_code"), code, format.mask(), code))
  end
  local title = tr("section.card_details")
  local brand = format.nonEmpty(card.brand)
  if brand ~= nil then
    title = tr("section.card_details_brand", { brand = brand })
  end
  return section(title, rows)
end

local function identitySections(detail)
  local identity = type(detail.data) == "table" and detail.data or {}
  local sections = {}
  local personal = {}
  local fullName = format.identityName(identity)
  if fullName ~= "" then
    table.insert(personal, fieldRow("identity:name", tr("field.name"), fullName, {
      copyButton(fullName, tr("field.name")),
    }))
  end
  local username = format.nonEmpty(identity.username)
  if username ~= nil then
    table.insert(personal, fieldRow("identity:username", tr("field.username"), username, {
      copyButton(username, tr("field.username")),
    }))
  end
  if #personal > 0 then
    table.insert(sections, section(tr("section.personal_details"), personal))
  end
  local identification = {}
  local ssn = format.nonEmpty(identity.ssn)
  if ssn ~= nil then
    table.insert(identification, maskedRow("identity:ssn", tr("field.ssn"), ssn, format.mask(), ssn))
  end
  local passport = format.nonEmpty(identity.passport_number)
  if passport ~= nil then
    table.insert(identification, fieldRow("identity:passport", tr("field.passport"), passport, {
      copyButton(passport, tr("field.passport")),
    }))
  end
  local license = format.nonEmpty(identity.license_number)
  if license ~= nil then
    table.insert(identification, fieldRow("identity:license", tr("field.license"), license, {
      copyButton(license, tr("field.license")),
    }))
  end
  if #identification > 0 then
    table.insert(sections, section(tr("section.identification"), identification))
  end
  local contact = {}
  local email = format.nonEmpty(identity.email)
  if email ~= nil then
    table.insert(contact, fieldRow("identity:email", tr("field.email"), email, {
      copyButton(email, tr("field.email")),
    }))
  end
  local phone = format.nonEmpty(identity.phone)
  if phone ~= nil then
    table.insert(contact, fieldRow("identity:phone", tr("field.phone"), phone, {
      copyButton(phone, tr("field.phone")),
    }))
  end
  if #contact > 0 then
    table.insert(sections, section(tr("section.contact_info"), contact))
  end
  local address = format.addressLines(identity)
  if address ~= "" then
    table.insert(sections, section(tr("section.address"), {
      fieldRow("identity:address", tr("field.address"), address, {
        copyButton(address, tr("field.address")),
      }, { maxLines = 6 }),
    }))
  end
  return sections
end

local function sshSection(detail)
  local key = type(detail.data) == "table" and detail.data or {}
  local rows = {}
  local private = format.nonEmpty(key.private_key)
  if private ~= nil then
    table.insert(rows, maskedRow("ssh:private", tr("field.private_key"), private, format.mask(), private))
  end
  local public = format.nonEmpty(key.public_key)
  if public ~= nil then
    table.insert(rows, fieldRow("ssh:public", tr("field.public_key"), public, {
      copyButton(public, tr("field.public_key")),
    }, { maxLines = 3 }))
  end
  local fingerprint = format.nonEmpty(key.fingerprint)
  if fingerprint ~= nil then
    table.insert(rows, fieldRow("ssh:fingerprint", tr("field.fingerprint"), fingerprint, {
      copyButton(fingerprint, tr("field.fingerprint")),
    }))
  end
  if #rows == 0 then
    return nil
  end
  return section(tr("section.ssh_key"), rows)
end

local function notesSection(detail, entryType)
  local notes = format.nonEmpty(detail.notes)
  if notes == nil then
    return nil
  end
  local title = entryType == "Note" and tr("section.secure_note") or tr("section.additional_options")
  return section(title, {
    fieldRow("notes", tr("field.note"), notes, {
      copyButton(notes, tr("field.note")),
    }, { maxLines = 10 }),
  })
end

local function customFieldsSection(detail)
  local fields = detail.fields
  if type(fields) ~= "table" or #fields == 0 then
    return nil
  end
  local rows = {}
  for index, field in ipairs(fields) do
    local name = format.nonEmpty(field.name) or tr("field.custom_field")
    local value = format.nonEmpty(field.value)
    local key = "custom:" .. tostring(index)
    if field.type == "hidden" then
      if value ~= nil then
        table.insert(rows, maskedRow(key, name, value, format.mask(), value))
      else
        table.insert(rows, fieldRow(key, name, "", {}))
      end
    elseif field.type == "boolean" then
      local checked = value == "true"
      table.insert(rows, ui.row({ key = key, align = "center", gap = 8, paddingV = 2 }, {
        ui.glyph({ name = checked and "circle-check" or "circle", size = 16, color = checked and "primary" or "on_surface_variant" }),
        ui.label({ text = name, fontSize = 13, flexGrow = 1 }),
      }))
    elseif field.type == "linked" then
      table.insert(rows, fieldRow(key, name, tr("field.linked"), {}, { color = "on_surface_variant" }))
    else
      local actions = {}
      if value ~= nil then
        table.insert(actions, copyButton(value, name))
      end
      table.insert(rows, fieldRow(key, name, value or "", actions, { maxLines = 6 }))
    end
  end
  return section(tr("section.custom_fields"), rows)
end

local function historySection(detail)
  local history = detail.history
  local count = type(history) == "table" and #history or 0
  local rows = {
    fieldRow("history:count", tr("detail.password_history_label"), tr("detail.password_history", { count = count }), {}),
  }
  if count == 0 then
    table.insert(rows, ui.label({ text = tr("detail.password_history_empty"), fontSize = 11, color = "on_surface_variant" }))
  else
    for index, entry in ipairs(history) do
      local password = format.nonEmpty(entry.password)
      if password ~= nil then
        table.insert(rows, maskedRow("history:" .. tostring(index), format.date(entry.last_used_date), password, format.mask(), password))
      end
    end
  end
  return section(tr("section.item_history"), rows)
end

local function renderDetail()
  if selectedId == nil then
    return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 8 }, {
      ui.glyph({ name = "lock-open", size = 32, color = "on_surface_variant" }),
      ui.label({ text = tr("detail.empty_title"), fontSize = 14, fontWeight = "medium" }),
      ui.label({ text = tr("detail.empty_body"), fontSize = 12, color = "on_surface_variant", textAlign = "center", maxWidth = 360 }),
    })
  end
  local item = itemById(selectedId)
  local detail = details[selectedId]
  if detail == nil then
    return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 8 }, {
      ui.glyph({ name = "hourglass", size = 28, color = "on_surface_variant" }),
      ui.label({ text = tr("detail.loading"), fontSize = 12, color = "on_surface_variant" }),
    })
  end
  local entryType = entryTypeOf(item, detail)
  local children = { detailHeader(item, detail) }
  if entryType == "Login" then
    addAll(children, { loginCredentialsSection(detail) })
    addAll(children, { autofillSection(detail) })
  elseif entryType == "Card" then
    addAll(children, { cardSection(detail) })
  elseif entryType == "Identity" then
    addAll(children, identitySections(detail))
  elseif entryType == "SSH Key" then
    addAll(children, { sshSection(detail) })
  end
  addAll(children, { notesSection(detail, entryType) })
  addAll(children, { customFieldsSection(detail) })
  addAll(children, { historySection(detail) })
  local nodes = {}
  for _, child in ipairs(children) do
    if child ~= nil then
      table.insert(nodes, child)
    end
  end
  return ui.scroll({ flexGrow = 1, gap = 14, align = "stretch" }, nodes)
end

local function listRow(item)
  local selected = item.id == selectedId
  return ui.row({
    key = "row:" .. item.id,
    gap = 10,
    align = "center",
    padding = 8,
    radius = 10,
    fill = selected and "primary/0.22" or "surface_container/0.5",
    onClick = function()
      selectItem(item.id)
    end,
  }, {
    ui.glyph({
      name = format.typeGlyph(entryTypeOf(item, details[item.id])),
      size = 18,
      color = selected and "primary" or "on_surface_variant",
    }),
    ui.column({ gap = 1, align = "stretch", flexGrow = 1 }, {
      ui.label({ text = item.name or "", fontSize = 13, fontWeight = "medium", maxLines = 1 }),
      ui.label({ text = itemSubtitle(item), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
    }),
  })
end

local function renderLeft()
  local rows = {}
  for _, item in ipairs(items) do
    if passesFilter(item) and matchesSearch(item) then
      table.insert(rows, listRow(item))
    end
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = tr("list.empty"), fontSize = 12, color = "on_surface_variant", paddingV = 8 }))
  end
  return ui.column({
    width = 320,
    gap = 8,
    align = "stretch",
    fill = "surface_container/0.35",
    radius = 12,
    padding = 10,
  }, {
    ui.input({
      key = "search:" .. tostring(searchKey),
      value = search,
      placeholder = tr("search.placeholder"),
      controlSize = "sm",
      onChange = function(value)
        search = value or ""
        render()
      end,
    }),
    ui.select({
      key = "filter",
      options = filterOptions,
      selectedIndex = filterIndex,
      controlSize = "sm",
      onChange = function(index)
        filterIndex = tonumber(index) or 0
        render()
      end,
    }),
    ui.scroll({ flexGrow = 1, gap = 4, align = "stretch" }, rows),
  })
end

local function paneButton(text, variant, onClick)
  return ui.button({ text = text, variant = variant, controlSize = "sm", onClick = onClick })
end

local function statePane()
  local glyph = "lock"
  local title = tr("state.checking_title")
  local body = nil
  local color = "on_surface_variant"
  local actions = {}
  if view == "no_rbw" then
    glyph = "alert-triangle"
    title = tr("state.no_rbw_title")
    body = tr("state.no_rbw_body")
    actions = {
      paneButton(tr("action.settings"), "primary", function()
        noctalia.openSettings()
      end),
    }
  elseif view == "setup" then
    glyph = "settings"
    title = tr("state.setup_title")
    body = tr("state.setup_body")
    actions = {
      paneButton(tr("action.settings"), "primary", function()
        noctalia.openSettings()
      end),
      paneButton(tr("action.recheck"), "outline", function()
        loadSettings()
        checkVault()
      end),
    }
  elseif view == "locked" then
    glyph = "lock"
    title = tr("state.locked_title")
    body = lastError ~= "" and lastError or tr("state.locked_body")
    actions = {
      paneButton(tr("action.unlock"), "primary", function()
        startUnlock()
      end),
      paneButton(tr("action.settings"), "outline", function()
        noctalia.openSettings()
      end),
    }
  elseif view == "unlocking" then
    glyph = "hourglass"
    title = tr("state.unlocking_title")
    body = tr("state.unlocking_body")
    actions = {
      paneButton(tr("action.settings"), "outline", function()
        noctalia.openSettings()
      end),
    }
  elseif view == "syncing" then
    glyph = "refresh"
    title = tr("state.syncing_title")
  elseif view == "error" then
    glyph = "alert-triangle"
    color = "error"
    title = tr("state.error_title")
    body = lastError
    actions = {
      paneButton(tr("action.retry"), "primary", function()
        loadSettings()
        checkVault()
      end),
      paneButton(tr("action.settings"), "outline", function()
        noctalia.openSettings()
      end),
    }
  end
  local children = {
    ui.glyph({ name = glyph, size = 40, color = color }),
    ui.label({ text = title, fontSize = 16, fontWeight = "bold" }),
  }
  if body ~= nil and body ~= "" then
    table.insert(children, ui.label({
      text = body,
      fontSize = 12,
      color = "on_surface_variant",
      textAlign = "center",
      maxWidth = 460,
      maxLines = 6,
    }))
  end
  if #actions > 0 then
    table.insert(children, ui.row({ gap = 8, align = "center", justify = "center" }, actions))
  end
  return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 10, padding = 12 }, children)
end

local function headerStatus()
  if view ~= "ready" then
    return notice
  end
  if notice ~= "" then
    return notice
  end
  return tr("header.count", { count = #items })
end

local function renderHeader()
  local children = {
    ui.glyph({ name = view == "ready" and "lock-open" or "lock", size = 18, color = "primary" }),
    ui.label({ text = tr("title"), fontSize = 15, fontWeight = "bold" }),
    ui.label({ text = headerStatus(), fontSize = 11, color = "on_surface_variant", flexGrow = 1, maxLines = 1 }),
  }
  if view == "ready" then
    table.insert(children, ui.button({
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("action.sync"),
      onClick = function()
        startSync()
      end,
    }))
    table.insert(children, ui.button({
      glyph = "lock",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("action.lock"),
      onClick = function()
        startLock()
      end,
    }))
  end
  table.insert(children, ui.button({
    glyph = "settings",
    variant = "ghost",
    controlSize = "sm",
    tooltip = tr("action.settings"),
    onClick = function()
      noctalia.openSettings()
    end,
  }))
  if showCloseButton then
    table.insert(children, ui.button({
      glyph = "close",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("action.close"),
      onClick = function()
        panel.close()
      end,
    }))
  end
  return ui.row({ gap = 8, align = "center" }, children)
end

render = function()
  local body
  if view == "ready" then
    body = ui.row({ flexGrow = 1, gap = 12, align = "stretch" }, {
      renderLeft(),
      ui.column({ flexGrow = 1, gap = 8, align = "stretch" }, { renderDetail() }),
    })
  else
    body = statePane()
  end
  panel.render(ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, {
    renderHeader(),
    body,
  }))
end

function onOpen(_context)
  loadSettings()
  showCloseButton = noctalia.getSetting("shell.show_close_buttons") ~= false
  resetSensitive()
  searchKey = searchKey + 1
  view = "checking"
  lastError = ""
  notice = ""
  panel.setWantsSecondTicks(true)
  render()
  checkVault()
end

function onClose()
  if clipboardClearAt ~= nil then
    local remaining = clipboardClearAt - os.time()
    clipboardClearAt = nil
    if remaining > 0 then
      noctalia.runAsync({ "sh", "-c", "sleep " .. tostring(remaining) .. "; noctalia msg clipboard-copy ' '" })
    end
  end
  resetSensitive()
  lastError = ""
  notice = ""
  view = "checking"
  if settings.lockOnClose then
    noctalia.runAsync({ "rbw", "lock" })
    publishVault("locked")
  end
end

function onExit(_signal, _reason)
  resetSensitive()
end

function update()
  if clipboardClearAt ~= nil and os.time() >= clipboardClearAt then
    clipboardClearAt = nil
    noctalia.copyToClipboard(" ", "text/plain")
  end
  if view ~= "ready" or selectedId == nil then
    return
  end
  local detail = details[selectedId]
  if detail == nil or type(detail.data) ~= "table" or format.nonEmpty(detail.data.totp) == nil then
    return
  end
  local remaining = secondsLeft()
  if remaining == totpRemaining then
    return
  end
  local rolled = totpRemaining >= 0 and remaining > totpRemaining
  totpRemaining = remaining
  if rolled then
    fetchTotp(selectedId)
    return
  end
  render()
end
