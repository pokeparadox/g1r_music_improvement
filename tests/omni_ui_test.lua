-- Standalone: luajit tests/omni_ui_test.lua
-- OmniUI bridge: no-op without Omni, one registration, themed screen/toast draws.
package.path = "./?.lua;" .. package.path

local function freshApi()
  local calls = {}
  local registrations = {}
  local theme = {
    bg = { 0.05, 0.05, 0.08, 1 },
    surface = { 0.1, 0.1, 0.15, 1 },
    surfaceHigh = { 0.2, 0.2, 0.3, 1 },
    ink = { 0.94, 0.96, 0.98, 1 },
    text = { 0.94, 0.96, 0.98, 1 },
    heading = { 0.9, 0.8, 0.3, 1 },
    accent = { 0.3, 0.7, 1, 1 },
  }
  local function record(name)
    return function(...)
      calls[#calls + 1] = { name = name, args = { ... } }
      return true
    end
  end
  local Layout = {
    drawCard = record("drawCard"),
    drawSlot = record("drawSlot"),
    drawText = record("drawText"),
    drawHintBar = record("drawHintBar"),
    drawProgressBar = record("drawProgressBar"),
    textWidth = function() return 42 end,
  }
  local api = {
    Layout = Layout,
    Theme = { get = function() return theme end },
    registerScreen = function(id, def)
      registrations[#registrations + 1] = { id = id, def = def }
      return true
    end,
  }
  return api, calls, registrations, theme
end

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

local function hasCall(calls, name)
  for _, call in ipairs(calls) do
    if call.name == name then return call end
  end
  return nil
end

local function clear(calls)
  for i = #calls, 1, -1 do calls[i] = nil end
end

-- No Omni installed: everything is a harmless no-op.
package.loaded["mods.omni_ui.api.PublicApi"] = nil
local absent = dofile("omni_ui.lua")
eq(absent.install(), false, "install without Omni")
eq(absent.isActive(), false, "inactive without Omni")
eq(absent.draw(nil, { g1rMusicScreen = "jukebox" }, 240, 160), false, "draw without Omni")
eq(absent.drawToast("test", 240, 160), false, "toast without Omni")

-- Omni present.
local api, calls, registrations, theme = freshApi()
package.loaded["mods.omni_ui.api.PublicApi"] = api
local m = dofile("omni_ui.lua")
eq(m.install(), true, "install with Omni")
eq(m.install(), true, "install idempotent")
eq(#registrations, 1, "single registration")
eq(registrations[1].id, "g1r_music_improvement_menu", "screen id")
local def = registrations[1].def
eq(def.match({ g1rMusicScreen = "jukebox" }), true, "match tagged state")
eq(def.match({}), false, "match untagged state")
eq(def.match(nil), false, "match nil state")

-- Registers through def.draw exactly as Omni calls it (w/h/theme forwarded).
local jukebox = {
  g1rMusicScreen = "jukebox",
  title = "MUSIC TEST",
  items = {
    { label = "Pallet Town", right = "G1" },
    { label = "Route 1", right = "G3 Mix" },
  },
  index = 2,
  scroll = 0,
  footer = "L/R VARIANT\nA PLAY  B BACK",
}
def.draw(nil, jukebox, 240, 160, api.Theme.get())
eq(hasCall(calls, "drawCard") ~= nil, true, "list card")
eq(hasCall(calls, "drawSlot") ~= nil, true, "selected slot")
local hintBar = hasCall(calls, "drawHintBar")
eq(hintBar ~= nil, true, "hint bar")
local hints = hintBar and hintBar.args[5] or {}
eq(#hints, 3, "multi-key footer splits into three hint pills")
eq(hints[1] and hints[1].key, "L/R", "shoulder hint key")
eq(hints[2] and hints[2].key, "A", "play hint key")
eq(hints[3] and hints[3].key, "B", "back hint key")
eq(hints[3] and hints[3].label, "BACK", "back hint label")
local titleCall
for _, call in ipairs(calls) do
  if call.name == "drawText" and call.args[1] == "MUSIC TEST" then titleCall = call end
end
eq(titleCall ~= nil, true, "list title")
eq(titleCall.args[2], 8, "title x")
eq(titleCall.args[3], 8, "title y")

clear(calls)
local sources = {
  g1rMusicScreen = "sources",
  title = "MUSIC SOURCES",
  items = { { label = "SHUFFLE", right = "YES" }, { label = "G3", right = "N/A" } },
  index = 1,
  footer = "A TOGGLE\nB DONE",
}
eq(m.draw(nil, sources, 240, 160), true, "sources draw")
eq(hasCall(calls, "drawCard") ~= nil, true, "sources card")

clear(calls)
eq(m.draw(nil, { g1rMusicScreen = "confirm", title = "ENHANCE MUSIC?",
  items = { { label = "YES" }, { label = "NO" } }, index = 1 }, 240, 160), true,
  "confirm draw")
eq(hasCall(calls, "drawCard") ~= nil, true, "confirm card")

-- Auto-fit: viewport height caps the 16-row request, never exceeds it.
clear(calls)
local many = {
  g1rMusicScreen = "jukebox", title = "MUSIC TEST", items = {},
  index = 1, scroll = 0, rows = 16,
}
for i = 1, 20 do
  many.items[i] = { label = string.format("ROW%02d", i), right = "G1" }
end
local function drawnRows()
  local seen = {}
  for _, call in ipairs(calls) do
    if call.name == "drawText" then
      local label = tostring(call.args[1] or "")
      local row = label:match("ROW%d%d")
      if row then seen[row] = true end
    end
  end
  return seen
end
m.draw(nil, many, 800, 600)
local wide = drawnRows()
eq(wide.ROW16 ~= nil, true, "auto-fit draws up to 16 rows")
eq(wide.ROW17 == nil, true, "auto-fit caps at 16 rows")
clear(calls)
m.draw(nil, many, 240, 160)
local narrow = drawnRows()
eq(narrow.ROW08 == nil, true, "small viewport clamps visible rows")

clear(calls)
eq(m.draw(nil, { g1rMusicScreen = "progress", progress = 3, total = 7 }, 240, 160),
  true, "progress draw")
local bar = hasCall(calls, "drawProgressBar")
eq(bar ~= nil, true, "progress bar")
eq(bar.args[5], 3, "progress current")
eq(bar.args[6], 7, "progress total")

clear(calls)
eq(m.drawToast("Pallet Town — G1", 240, 160), true, "toast themed")
local toastCard = hasCall(calls, "drawCard")
eq(toastCard.args[1], 8, "toast x")
eq(toastCard.args[2], 8, "toast y")
eq(toastCard.args[3], 54, "toast width")
eq(toastCard.args[4], 20, "toast height")
eq(toastCard.args[5].color, theme.bg, "toast card uses dark background")
local toastText = hasCall(calls, "drawText")
eq(toastText and toastText.args[4].color, theme.ink,
  "toast text uses light ink")

-- A throwing Omni Layout degrades to native drawing (drawToast returns false).
api.Layout.drawCard = function() error("broken") end
eq(m.drawToast("Pallet Town — G1", 240, 160), false, "toast fallback")

print("omni_ui ok")
