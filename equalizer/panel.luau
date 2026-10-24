--!nonstrict
-- panel.luau — эквалайзер: профили одним кликом.
--
-- Данные: presets.json рядом (имена, подсказки, полосы и доп. эффекты).
-- Применение — eqctl (EasyEffects), состояние читаем оттуда же, поэтому
-- панель и движок не расходятся. Кривая сверху — АЧХ выбранного профиля;
-- при смене профиля она плавно перетекает (onFrameTick), а не прыгает.

local DIR = noctalia.pluginDir() or ""
local STATE = noctalia.expandPath("~/.local/state/equalizer/state.json")

local data = nil          -- разобранный presets.json
local active = "flat"     -- id профиля
local bypass = false      -- эквалайзер в обходе
local running = false     -- EasyEffects запущен
local slots = {}          -- слот плитки -> id профиля

local display = nil       -- текущая (анимируемая) кривая
local anim = nil          -- { from, to, t, dur, fromCol, fromRow, toCol, toRow }
local pulse = 0           -- 1 -> 0 во время перехода: подсветка
local curveFor            -- объявим ниже; startAnim ссылается на неё
local uiGen = 0           -- растёт на каждое действие пользователя
local refreshSeq = 0      -- номер последнего запроса статуса
local activeSlot = nil    -- слот текущего профиля
local frameCol, frameRow = 0, 0 -- где сейчас «липкая рамка» (в координатах сетки)

local function gridCol(slot) return (slot - 1) % 2 end
local function gridRow(slot) return math.floor((slot - 1) / 2) end

-- Разгон-торможение: рамка отрывается, ускоряется и мягко садится на цель.
local function easeInOut(k)
  if k < 0.5 then return 4 * k * k * k end
  return 1 - ((-2 * k + 2) ^ 3) / 2
end

local FX_ORDER = { "bass_enhancer", "exciter", "deesser", "compressor", "stereo_tools", "limiter" }
local FX_LABELS = {
  bass_enhancer = "Bass", exciter = "Exciter", deesser = "De-ess",
  compressor = "Comp", stereo_tools = "Stereo", limiter = "Limit",
}

-- ── данные ──────────────────────────────────────────────────────

local function loadData()
  if data then return end
  local raw = noctalia.readFile(DIR .. "/presets.json")
  if raw then
    local ok, parsed = pcall(noctalia.json.decode, raw)
    if ok and parsed then data = parsed end
  end
  if not data then data = { bands = {}, presets = {} } end
end

local function presetById(id)
  for _, preset in ipairs(data.presets or {}) do
    if preset.id == id then return preset end
  end
  return nil
end

-- ── состояние ───────────────────────────────────────────────────

local function frameTicks(on)
  if panel and panel.setNeedsFrameTick then
    pcall(panel.setNeedsFrameTick, on)
  end
end

local function slotOf(id)
  for i = 1, #slots do
    if slots[i] == id then return i end
  end
  return nil
end

local function startAnim(id, slot)
  local to = curveFor(id)
  local from = display or curveFor("flat")
  if #from ~= #to then from = to end

  local target = slot or slotOf(id) or activeSlot or 1
  local origin = activeSlot or target
  anim = {
    from = from, to = to, t = 0, dur = 0.42,
    fromCol = gridCol(origin), fromRow = gridRow(origin),
    toCol = gridCol(target), toRow = gridRow(target),
  }
  frameCol, frameRow = anim.fromCol, anim.fromRow
  activeSlot = target
  pulse = 1
  frameTicks(true)
end

local function applyState(st)
  if type(st) ~= "table" then return end
  if st.preset and st.preset ~= active then
    active = st.preset
    startAnim(active, slotOf(active))
  end
  bypass = st.bypass == true
  running = st.running == true
end

local function refresh()
  refreshSeq = refreshSeq + 1
  local seq = refreshSeq
  local gen = uiGen
  noctalia.runAsync({ DIR .. "/eqctl", "status" }, function(result)
    -- Устаревший ответ не должен перебивать последний выбор: если за время
    -- запроса был новый клик (gen) или новый запрос (seq) — молча выходим.
    if seq ~= refreshSeq or gen ~= uiGen then return end
    if not result or result.exitCode ~= 0 then return end
    local ok, st = pcall(noctalia.json.decode, result.stdout or "")
    if ok then applyState(st) end
    render()
  end)
end

-- ── кривая АЧХ ──────────────────────────────────────────────────

local RANGE = 10 -- дБ вверх/вниз, столько рисуем

curveFor = function(id)
  local preset = presetById(id)
  local gains = (preset and preset.gains) or {}
  local n = #gains
  if n == 0 then return { 0.5, 0.5 } end

  -- Сглаживание косинусом: между полосами линия идёт плавно, без изломов.
  local out = {}
  local steps = 56
  for i = 0, steps do
    local t = (i / steps) * (n - 1)
    local low = math.floor(t) + 1
    local high = math.min(low + 1, n)
    local f = t - math.floor(t)
    local a = gains[low] or 0
    local b = gains[high] or 0
    local g = a + (b - a) * (0.5 - 0.5 * math.cos(f * math.pi))
    out[#out + 1] = math.max(0, math.min(1, (g + RANGE) / (2 * RANGE)))
  end
  return out
end

-- ── вид ─────────────────────────────────────────────────────────

local function chip(text, on)
  return ui.column({
    fill = on and "primary/0.10" or "on_surface/0.06",
    radius = 6, paddingH = 7, paddingV = 2,
  }, {
    ui.label({
      text = text, fontSize = 8.5,
      color = on and "primary" or "on_surface/0.35",
      maxLines = 1,
    }),
  })
end

local function graphCard()
  local preset = presetById(active)
  local on = not bypass
  local color = on and "primary" or "on_surface/0.35"

  local head = {
    ui.label({ text = preset and preset.name or "—", fontSize = 13,
               fontWeight = "semibold", color = on and "on_surface" or "on_surface/0.55",
               flexGrow = 1 }),
    ui.label({ text = on and (preset and preset.hint or "") or "выключен",
               fontSize = 10, color = "on_surface/0.45", maxLines = 1 }),
  }

  local foot = {
    ui.label({ text = "32 Гц", fontSize = 9, color = "on_surface/0.35" }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = "1 кГц", fontSize = 9, color = "on_surface/0.35" }),
    ui.spacer({ flexGrow = 1 }),
    ui.label({ text = "16 кГц", fontSize = 9, color = "on_surface/0.35" }),
  }

  local chips = { chip("EQ", on) }
  local fx = (preset and preset.effects) or {}
  for _, key in ipairs(FX_ORDER) do
    if fx[key] then chips[#chips + 1] = chip(FX_LABELS[key] or key, on) end
  end

  return ui.column({
    fill = "surface_variant/0.35", radius = 14,
    border = "on_surface/0.10", borderWidth = 1,
    paddingH = 14, paddingV = 12, gap = 6,
  }, {
    ui.row({ gap = 8, align = "center" }, head),
    ui.graph({
      values = display or curveFor(active),
      height = 62,
      color = color,
      fillOpacity = (on and 0.16 or 0.05) + 0.10 * pulse,
      lineWidth = 2,
    }),
    ui.row({ gap = 0, align = "center" }, foot),
    ui.row({ gap = 4, align = "center" }, chips),
  })
end

local function tile(slot)
  local id = slots[slot]
  local preset = presetById(id)
  if not preset then return ui.box({ width = 0, height = 0 }) end

  local selected = (id == active)
  local moving = anim ~= nil

  -- Насколько «липкая рамка» сейчас близка к этой плитке (0..1).
  local w = 0
  if moving then
    local dx = gridCol(slot) - frameCol
    local dy = gridRow(slot) - frameRow
    local dist = math.sqrt(dx * dx + dy * dy)
    w = math.max(0, math.min(1, 1 - dist / 1.15))
    w = w ^ 1.6
  end

  local lit = selected and (not moving or w > 0.5)
  local dim = bypass and not lit

  local head = {
    ui.label({
      text = preset.name, fontSize = 12.5, fontWeight = "semibold",
      color = lit and "primary" or (dim and "on_surface/0.55" or "on_surface"),
      maxLines = 1, flexGrow = 1,
    }),
  }
  if selected and (not moving or w > 0.55) then
    head[#head + 1] = ui.glyph({ name = "check", size = 12, color = "primary" })
  end

  -- Рамка едет по сетке: у прошлой плитки гаснет, у цели разгорается.
  local fill, border, borderWidth
  if moving then
    if w > 0.02 then
      fill = string.format("primary/%.2f", 0.05 + 0.10 * w)
      border = string.format("primary/%.2f", 0.08 + 0.40 * w)
      borderWidth = w > 0.45 and 2 or 1
    else
      fill = "surface_variant/0.40"
      border = "on_surface/0.08"
      borderWidth = 1
    end
  else
    fill = selected and "primary/0.14" or "surface_variant/0.40"
    border = selected and "primary/0.45" or "on_surface/0.08"
    borderWidth = selected and 2 or 1
  end

  return ui.column({
    gap = 3, flexGrow = 1, minHeight = 54,
    fill = fill,
    border = border,
    borderWidth = borderWidth, radius = 12,
    paddingH = 12, paddingV = 9,
    onClick = "onPick" .. slot,
  }, {
    ui.row({ gap = 6, align = "center" }, head),
    ui.label({
      text = preset.hint or "", fontSize = 9.5,
      color = "on_surface/0.45", maxLines = 1,
    }),
  })
end

local function grid()
  local rows = {}
  local count = #(data.presets or {})
  local index = 1
  for row = 1, math.ceil(count / 2) do
    local cells = {}
    for col = 1, 2 do
      if index <= count then
        slots[index] = data.presets[index].id
        cells[#cells + 1] = tile(index)
        index = index + 1
      else
        cells[#cells + 1] = ui.box({ flexGrow = 1 })
      end
    end
    rows[#rows + 1] = ui.row({ gap = 8, flexGrow = 1 }, cells)
  end
  return ui.column({ gap = 8, flexGrow = 1 }, rows)
end

render = function()
  loadData()

  local header = ui.row({ gap = 10, align = "center", paddingH = 16, paddingV = 14 }, {
    ui.glyph({ name = "adjustments-horizontal", size = 18, color = bypass and "on_surface/0.45" or "primary" }),
    ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "semibold", flexGrow = 1 }),
    ui.toggle({ checked = not bypass, onChange = "onEnabled" }),
    ui.button({ glyph = "x", glyphSize = 15, variant = "ghost", onClick = "onClosePanel" }),
  })

  local body = ui.column({ gap = 12, paddingH = 16, paddingV = 14, flexGrow = 1 }, {
    graphCard(),
    grid(),
  })

  panel.render(ui.column({ gap = 0, flexGrow = 1 }, { header, ui.separator({}), body }))
end

-- ── анимация ────────────────────────────────────────────────────

function onFrameTick(dt)
  if not anim then return end
  local ms = tonumber(dt) or 16
  anim.t = anim.t + math.min(ms, 120) / 1000
  local k = math.min(1, anim.t / anim.dur)
  local e = 1 - (1 - k) ^ 3          -- кривая: мягко выезжает
  local f = easeInOut(k)             -- рамка: разгон и торможение

  local out = {}
  for i = 1, #anim.to do
    local a = anim.from[i] or anim.to[i]
    out[i] = a + (anim.to[i] - a) * e
  end
  display = out
  pulse = 1 - e
  frameCol = anim.fromCol + (anim.toCol - anim.fromCol) * f
  frameRow = anim.fromRow + (anim.toRow - anim.fromRow) * f

  if k >= 1 then
    frameCol, frameRow = anim.toCol, anim.toRow
    anim = nil
    pulse = 0
    frameTicks(false)
  end
  render()
end

-- ── действия ────────────────────────────────────────────────────

local function run(args)
  noctalia.runAsync(args, function(result)
    if not result or result.exitCode ~= 0 then
      noctalia.notifyError(noctalia.tr("panel.title"), noctalia.tr("error.apply"))
      return
    end
    refresh()
  end)
end

-- Применения сериализуем: два одновременных `easyeffects -l` дают гонку —
-- state.json и звук достаются случайному из них. Если во время применения
-- кликнули другой профиль, применим последний, а промежуточные пропустим.
local applying = false
local pending = nil

local function applyPreset(id)
  if applying then
    pending = id
    return
  end
  applying = true
  noctalia.runAsync({ DIR .. "/eqctl", "apply", id }, function(result)
    applying = false
    if not result or result.exitCode ~= 0 then
      noctalia.notifyError(noctalia.tr("panel.title"), noctalia.tr("error.apply"))
    end
    local nextId = pending
    pending = nil
    if nextId and nextId ~= id then
      applyPreset(nextId)
    else
      refresh()
    end
  end)
end

local function pick(slot)
  local id = slots[slot]
  if not id then return end
  uiGen = uiGen + 1
  active = id
  bypass = false
  startAnim(id, slot)
  render()
  applyPreset(id)
end

function onPick1() pick(1) end
function onPick2() pick(2) end
function onPick3() pick(3) end
function onPick4() pick(4) end
function onPick5() pick(5) end
function onPick6() pick(6) end
function onPick7() pick(7) end
function onPick8() pick(8) end

function onEnabled(value)
  local checked = (value == "true")
  uiGen = uiGen + 1
  bypass = not checked
  render()
  run({ DIR .. "/eqctl", "bypass", checked and "off" or "on" })
end

-- IPC для тестов и внешних хоткеев:
--   noctalia msg plugin vlad-dev/equalizer:panel all pick 3
function onIpc(event, payload)
  if event ~= "pick" then return end
  local n = tonumber(payload)
  if n then
    pick(n)
    return
  end
  for i = 1, #slots do
    if slots[i] == payload then
      pick(i)
      return
    end
  end
end

function onClosePanel() panel.close() end

-- ── жизненный цикл ──────────────────────────────────────────────

function onOpen()
  loadData()
  -- Вступление: кривая и рамка выезжают из «плоского» профиля.
  display = curveFor("flat")
  active = "flat"
  activeSlot = 1
  frameCol, frameRow = gridCol(1), gridRow(1)
  render()
  refresh()
end

function onClose()
  anim = nil
  pulse = 0
end
