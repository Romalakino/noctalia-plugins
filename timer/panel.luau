--!nonstrict
-- Timer panel (fork vlad-dev/timer) — минимализм.
--
-- На панели только большие цифры и две кнопки. Поля ввода нет: панель
-- объявляет capture_keys (см. plugin.toml) и читает нажатия в onKey — это
-- эмуляция набора. Цифры при этом остаются большим текстом, курсора нет.
--
-- Клавиши:
--   0-9        — дописать цифру к вводимому времени (400 → 4:00, 130 → 1:30)
--   BackSpace   — стереть последнюю
--   Enter       — старт (в паузе — продолжить)
--
-- Контракт с service.luau (noctalia.state):
--   timer.state          IDLE | RUNNING | PAUSED | NOTIFY
--   timer.remaining      остаток (в IDLE — «сколько набрано»)
--   timer.formattedTime  остаток строкой (его пишет сервис)
--   timer.cmd            START | PAUSE | RESET

local STATE = "IDLE"
local remaining = 0
local formattedTime = "0"
local draft = "" -- набранные цифры: "400", "10300"

------------------------------------------------------------------------- утиль

-- "400" → 4:00, "130" → 1:30, "10300" → 1:03:00 (как в апстриме)
local function parseTime(text)
  local digits = tostring(text or ""):gsub("%D", "")
  if digits == "" then
    return 0
  end
  if #digits <= 2 then
    return tonumber(digits) or 0
  end

  local secs = tonumber(digits:sub(-2)) or 0
  if #digits <= 4 then
    return (tonumber(digits:sub(1, -3)) or 0) * 60 + math.min(59, secs)
  end
  return (tonumber(digits:sub(1, -5)) or 0) * 3600
    + math.min(59, tonumber(digits:sub(-4, -3)) or 0) * 60
    + math.min(59, secs)
end

local function fmt(seconds)
  local s = math.max(0, math.floor(seconds or 0))
  local m = s // 60
  if m >= 60 then
    return string.format("%d:%02d:%02d", m // 60, m % 60, s % 60)
  end
  return string.format("%d:%02d", m, s % 60)
end

local function isRunning()
  return STATE == "RUNNING" or STATE == "PAUSED"
end

local render -- forward declaration: хелперы ниже вызывают render

local function startWith(seconds)
  if seconds > 0 then
    noctalia.state.set("timer.remaining", seconds)
    noctalia.state.set("timer.cmd", "START")
  end
end

------------------------------------------------------------------- управление

-- Нажатия клавиш из capture_keys. Второй аргумент — нажатие/отпускание.
function onKey(chord, pressed)
  if pressed == false or pressed == "false" then
    return
  end

  if chord == "Return" or chord == "KP_Enter" then
    if STATE == "IDLE" then
      startWith(parseTime(draft))
    elseif STATE == "PAUSED" then
      noctalia.state.set("timer.cmd", "START")
    end
    return
  end

  if chord == "BackSpace" or chord == "Backspace" then
    if STATE == "IDLE" then
      draft = draft:sub(1, -2)
      render()
    end
    return
  end

  local digit = chord:match("^%d$")
  if digit and STATE == "IDLE" and #draft < 6 then
    draft = draft .. digit
    render()
  end
end

function onToggle()
  if STATE == "RUNNING" then
    noctalia.state.set("timer.cmd", "PAUSE")
  elseif STATE == "PAUSED" then
    noctalia.state.set("timer.cmd", "START")
  elseif STATE == "NOTIFY" then
    noctalia.state.set("timer.cmd", "RESET")
  else
    startWith(parseTime(draft))
  end
end

function onReset()
  draft = ""
  noctalia.state.set("timer.cmd", "RESET")
end

------------------------------------------------------------------------- вывод

function render()
  local idle = STATE == "IDLE"
  local seconds = parseTime(draft)
  local color = STATE == "NOTIFY" and "error"
    or (isRunning() and "primary")
    or (seconds > 0 and "primary" or "outline")

  local primaryText, primaryVariant
  if STATE == "RUNNING" then
    primaryText, primaryVariant = noctalia.tr("ui.pause"), "secondary"
  elseif STATE == "PAUSED" then
    primaryText, primaryVariant = noctalia.tr("ui.resume"), "primary"
  elseif STATE == "NOTIFY" then
    primaryText, primaryVariant = noctalia.tr("ui.dismiss"), "secondary"
  else
    primaryText, primaryVariant = noctalia.tr("ui.start"), "primary"
  end

  panel.render(ui.column({ gap = 12, padding = 16 }, {
    ui.column({
      paddingV = 16,
      fill = "surface_variant/0.35",
      radius = 14,
      align = "center",
    }, {
      ui.label({
        text = idle and fmt(seconds) or formattedTime,
        fontSize = 64,
        fontWeight = "bold",
        color = color,
      }),
    }),
    ui.row({ gap = 8 }, {
      ui.button({
        text = noctalia.tr("ui.reset"),
        variant = "outline",
        flexGrow = 1,
        onClick = "onReset",
        enabled = STATE ~= "IDLE" or seconds > 0,
      }),
      ui.button({
        text = primaryText,
        variant = primaryVariant,
        flexGrow = 1,
        onClick = "onToggle",
        enabled = STATE ~= "IDLE" or seconds > 0,
      }),
    }),
  }))
end

--------------------------------------------------------------------- жизненный

function onOpen(_context)
  STATE = noctalia.state.get("timer.state") or "IDLE"
  remaining = noctalia.state.get("timer.remaining") or 0
  formattedTime = noctalia.state.get("timer.formattedTime") or "0"
  if draft == "" and remaining > 0 then
    draft = tostring(remaining) -- показать то, что уже стоит, как «400»
  end
  render()
end

noctalia.state.watch("timer.state", function(value)
  STATE = value
  render()
end)

noctalia.state.watch("timer.formattedTime", function(value)
  formattedTime = value
  render()
end)

noctalia.state.watch("timer.remaining", function(value)
  remaining = value
  render()
end)
