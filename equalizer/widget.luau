--!nonstrict
-- widget.luau — живой индикатор профиля эквалайзера в баре.
--
-- Плитка Control Center собирается один раз при создании панели и больше не
-- перечитывает подпись плагина (Noctalia 5.3), поэтому актуальное имя профиля
-- показываем здесь: бар перерисовывается на каждом update().

local DIR = noctalia.pluginDir() or ""
local STATE = noctalia.expandPath("~/.local/state/equalizer/state.json")
local PANEL = "vlad-dev/equalizer:panel"

local names = {}
local hints = {}
local loaded = false

local function loadPresets()
  if loaded then return end
  local raw = noctalia.readFile(DIR .. "/presets.json")
  if not raw then return end
  local ok, data = pcall(noctalia.json.decode, raw)
  if not ok or not data then return end
  for _, preset in ipairs(data.presets or {}) do
    names[preset.id] = preset.name
    hints[preset.id] = preset.hint
  end
  loaded = true
end

local function readState()
  local raw = noctalia.readFile(STATE)
  if not raw then return {} end
  local ok, data = pcall(noctalia.json.decode, raw)
  if not ok or not data then return {} end
  return data
end

function update()
  loadPresets()
  local st = readState()
  local preset = st.preset or "flat"
  local off = st.bypass == true
  local name = names[preset] or "Эквалайзер"
  local hint = hints[preset]

  barWidget.setGlyph("adjustments-horizontal")
  barWidget.setColor(off and "on_surface_variant" or "primary")
  barWidget.setText(off and (name .. " · выкл") or name)

  local tip = "Эквалайзер: " .. name
  if hint and hint ~= "" then tip = tip .. " — " .. hint end
  if off then tip = tip .. "\nОбход включён" end
  barWidget.setTooltip(tip .. "\nЛКМ — профили")
end

function onClick()
  noctalia.togglePanel(PANEL)
end

noctalia.setUpdateInterval(2000)
