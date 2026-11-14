-- Minimal Gen3 (FRLG) modal list.  Gen3 has no game.stack, so mod.ui.push
-- (the Gen1/2 screen stack) cannot be used there; this rides the game3
-- stack instead.

local M = {}

local VISIBLE = 8
local LAYER = "music_improvement_menu"

local function font()
  local ok, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
  if ok and type(FrlgFont) == "table" and FrlgFont.draw then return FrlgFont end
  return nil
end

function M.openList(game, opts)
  local ok, Stack = pcall(require, "src.ui.game3.stack")
  if not ok or type(Stack) ~= "table" then return false end
  opts = opts or {}
  local menu = {
    isMenu = true,
    title = opts.title or "",
    items = opts.items or {},
    index = 1,
    scroll = 0,
    onChoose = opts.onChoose,
    onCancel = opts.onCancel,
  }
  local F = font()

  local function clamp()
    local n = #menu.items
    if n < 1 then menu.index, menu.scroll = 1, 0; return end
    if menu.index < 1 then menu.index = 1 end
    if menu.index > n then menu.index = n end
    if menu.index - 1 < menu.scroll then menu.scroll = menu.index - 1 end
    if menu.index > menu.scroll + VISIBLE then menu.scroll = menu.index - VISIBLE end
    menu.scroll = math.max(0, math.min(menu.scroll, n - VISIBLE))
  end

  local function drawText(text, x, y, colors)
    if F then
      pcall(F.draw, text, x, y, { colors = colors or F.COLOR.WHITE })
    else
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(text, x, y)
    end
  end

  function menu.draw()
    local G = love.graphics
    G.push("all")
    G.setColor(0, 0, 0, 0.85)
    G.rectangle("fill", 0, 0, G.getWidth(), G.getHeight())
    drawText(menu.title, 8, 6)
    for row = 1, VISIBLE do
      local i = menu.scroll + row
      local item = menu.items[i]
      if not item then break end
      local selected = i == menu.index
      local colors = F and (selected and F.COLOR.RED or F.COLOR.WHITE) or nil
      drawText((selected and "> " or "  ") .. tostring(item.label or item),
        8, 22 + (row - 1) * 14, colors)
    end
    G.pop()
  end

  local function close(cancelled)
    Stack.pop(LAYER)
    if cancelled and menu.onCancel then pcall(menu.onCancel) end
  end

  function menu.handleInput(input)
    if not input then return end
    if input:wasPressed("up") then
      menu.index = menu.index - 1
      clamp()
    elseif input:wasPressed("down") then
      menu.index = menu.index + 1
      clamp()
    elseif input:wasPressed("a") then
      local item = menu.items[menu.index]
      if item then
        close(false)
        if menu.onChoose then pcall(menu.onChoose, item) end
      end
    elseif input:wasPressed("b") then
      close(true)
    end
  end

  clamp()
  Stack.push(LAYER, menu, { hideBelow = true, fullscreen = true })
  return true
end

return M
