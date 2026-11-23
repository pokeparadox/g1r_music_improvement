-- OmniUI 0.5.0 presenter bridge.  The native screens keep drawing exactly as
-- before; Omni calls the registered custom screen with its own viewport and
-- theme, and this module repaints the same state with Omni's Layout primitives.
local M = {}

local api
local installed = false

local function getApi()
  if api then return api end
  local ok, PublicApi = pcall(require, "mods.omni_ui.api.PublicApi")
  if ok and type(PublicApi) == "table" and type(PublicApi.registerScreen) == "function" then
    api = PublicApi
  end
  return api
end

local function safe(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok, result
end

local function themeOf(theme)
  if type(theme) == "table" then return theme end
  local PublicApi = getApi()
  if PublicApi and type(PublicApi.Theme) == "table" then
    local ok, resolved = safe(PublicApi.Theme.get)
    if ok and type(resolved) == "table" then return resolved end
  end
  return {}
end

function M.install()
  if installed then return true end
  local PublicApi = getApi()
  if not PublicApi then return false end
  local ok = safe(PublicApi.registerScreen, "g1r_music_improvement_menu", {
    match = function(state)
      return type(state) == "table" and type(state.g1rMusicScreen) == "string"
    end,
    draw = function(game, state, w, h, theme)
      M.draw(game, state, w, h, theme)
    end,
  })
  installed = ok and true or false
  return installed
end

function M.isActive()
  return installed
end

local function hintsFrom(source)
  local lines = {}
  if type(source) == "table" then
    for _, line in ipairs(source) do lines[#lines + 1] = tostring(line) end
  elseif source then
    for line in tostring(source):gmatch("[^\n]+") do lines[#lines + 1] = line end
  end
  local hints = {}
  for _, line in ipairs(lines) do
    -- Two spaces separate hint pills inside one line ("A PLAY  B BACK").
    for chunk in (line .. "  "):gmatch("(.-)%s%s+") do
      local key, label = chunk:match("^%s*(%S+)%s+(.+)$")
      if key and label then
        hints[#hints + 1] = { key = key, label = label }
      elseif chunk:match("%S") then
        hints[#hints + 1] = { key = "", label = chunk }
      end
    end
  end
  return hints
end

function M.draw(game, state, w, h, theme)
  local PublicApi = getApi()
  if not installed or not PublicApi or type(PublicApi.Layout) ~= "table" then return false end
  if type(state) ~= "table" then return false end
  local Layout = PublicApi.Layout
  w, h = tonumber(w) or 240, tonumber(h) or 160
  local t = themeOf(theme)
  local pad = 8
  safe(Layout.drawCard, 0, 0, w, h, {
    color = t.bg or (type(t.colors) == "table" and t.colors.bg) or nil,
    borderWidth = 0,
  })

  local kind = state.g1rMusicScreen
  if kind == "progress" then
    safe(Layout.drawText, "PREPARING MUSIC", pad, pad, {
      font = "heading", color = t.heading,
    })
    local total = math.max(1, tonumber(state.total) or 1)
    local progress = math.max(0, math.min(total, tonumber(state.progress) or 0))
    safe(Layout.drawProgressBar, pad, pad + 40, w - pad * 2, 16, progress, total, {})
    safe(Layout.drawText, string.format("%d / %d", progress, total), pad, pad + 64, {})
    return true
  end

  if kind ~= "confirm" and kind ~= "jukebox" and kind ~= "sources" then return false end
  safe(Layout.drawText, tostring(state.title or ""), pad, pad, {
    font = "heading", color = t.heading,
  })

  local items = type(state.items) == "table" and state.items or {}
  local top = pad + 24
  local available = math.max(24, h - top - pad - 26)
  local minLineH = 12
  local fit = math.max(2, math.floor(available / minLineH))
  local requested = tonumber(state.rows) or tonumber(state.visible) or #items
  local visibleMax = math.max(2, math.min(16, requested or 16))
  local visible = math.max(0, math.min(#items, visibleMax, fit))
  local lineH = math.max(minLineH, math.min(22,
    math.floor(available / math.max(1, visible))))
  local scroll = tonumber(state.scroll) or 0
  for row = 1, visible do
    local index = scroll + row
    local item = items[index]
    if item then
      local y = top + (row - 1) * lineH
      local selected = index == state.index
      if selected then
        safe(Layout.drawSlot, pad, y - 2, w - pad * 2, lineH - 2, {
          color = t.surfaceHigh or t.surface,
        })
      end
      safe(Layout.drawText, (selected and "> " or "  ") .. tostring(item.label or item),
        pad + 4, y, { color = selected and t.accent or t.text })
      if item.right ~= nil then
        safe(Layout.drawText, tostring(item.right), w - pad - 92, y, {
          align = "right", width = 80, color = t.text,
        })
      end
    end
  end

  local hints = hintsFrom(state.footer or state.hint)
  if #hints > 0 then
    safe(Layout.drawHintBar, pad, h - 24, w - pad * 2, 20, hints, {})
  end
  return true
end

function M.drawToast(text, w, h, theme)
  local PublicApi = getApi()
  if not installed or not PublicApi or type(PublicApi.Layout) ~= "table" then return false end
  local Layout = PublicApi.Layout
  local t = themeOf(theme)
  local message = tostring(text or "")
  local width = #message * 6 + 12
  if type(Layout.textWidth) == "function" then
    local ok, measured = safe(Layout.textWidth, message, "body")
    if ok and tonumber(measured) then width = tonumber(measured) + 12 end
  end
  -- Omni themes use near-white `ink`; keep it for text, never for the card.
  local card = t.bg or t.surface or { 0, 0, 0, 0.72 }
  local ink = t.ink or t.heading or { 1, 1, 1, 1 }
  local ok = safe(Layout.drawCard, 8, 8, width, 20, {
    color = card, borderWidth = 0,
  })
  if not ok then return false end
  safe(Layout.drawText, message, 14, 12, { color = ink })
  return true
end

return M
