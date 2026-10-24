# Equalizer для Noctalia

Системный эквалайзер с простыми профилями: движок — **EasyEffects** (headless),
интерфейс — плагин [Noctalia](https://github.com/noctalia-dev/noctalia): плитка
в Control Center и панель с профилями.

![панель](docs/panel.png)

## Что умеет

- 8 профилей: Плоский, Бас+, Бас++, Меньше низа, Вокал, Мягче верх, Тёплый, Кино.
- Кроме полос EQ — дополнительные эффекты EasyEffects: bass_enhancer, exciter,
  deesser, compressor, stereo_tools, limiter (у каждого профиля свой набор).
- Кривая АЧХ плавно перетекает при смене профиля, а подсветка «отрывается» от
  прошлой плитки и перелетает на новую.
- Быстрое переключение не откатывается: применения сериализуются, устаревшие
  ответы состояния отбрасываются.
- Обход (bypass) целиком, состояние переживает перезапуск EasyEffects.
- Живое имя профиля в баре (`🎛 Кино`), плитка в Control Center — вход в панель.

## Зависимости

```bash
sudo pacman -S easyeffects lsp-plugins python3
```

`lsp-plugins` обязателен: без него EasyEffects молча пропускает звук насквозь,
хотя пресеты «загружаются».

## Установка

```bash
# весь сборник плагинов
git clone https://github.com/Romalakino/noctalia-plugins ~/dev/noctalia-plugins

# или только эквалайзер
git clone https://github.com/Romalakino/equalizer ~/dev/noctalia-plugins/equalizer
```

В `~/.local/state/noctalia/settings.toml`:

```toml
[plugins]
enabled = [ ..., "vlad-dev/equalizer" ]

[control_center]
    [[control_center.shortcuts]]
    type = "vlad-dev/equalizer:eq"

# живое имя профиля в баре
[bar.default]
center = [ ..., "eq_widget" ]

[widget.eq_widget]
type = "vlad-dev/equalizer:eq_widget"
```

Автозапуск движка (`~/.config/niri/cfg/autostart.kdl`):

```kdl
spawn-at-startup "easyeffects" "--hide-window"
```

Клавиша (`~/.config/niri/cfg/keybinds.kdl`):

```kdl
Mod+Shift+E { spawn "noctalia" "msg" "panel-toggle" "vlad-dev/equalizer:panel"; }
```

## Управление

```bash
eqctl status                 # {"running":true,"bypass":false,"preset":"bass"}
eqctl apply bass             # включить профиль (и снять bypass)
eqctl bypass on|off|toggle   # обход целиком
eqctl sync                   # перегенерировать пресеты EasyEffects
```

Панель также принимает IPC:

```bash
noctalia msg plugin vlad-dev/equalizer:panel all pick 3
noctalia msg plugin vlad-dev/equalizer:panel all pick vocal
```

## Как это устроено

`presets.json` — единственный источник правды. `eqctl` генерирует из него
пресеты EasyEffects (`~/.local/share/easyeffects/output/vlad-eq-*.json`) и
применяет их через `easyeffects -l`. Панель читает тот же файл и рисует кривую;
состояние берёт из `~/.local/state/equalizer/state.json`.

Дополнительные эффекты описываются блоком `effects` у профиля; `eqctl` собирает
их в `plugins_order` в фиксированном порядке.

### Почему имя профиля в баре, а плитка статичная

Noctalia 5.3 собирает плитки плагинов в Control Center один раз при создании
панели и больше не перечитывает подпись: `shortcut.setLabel()` меняет состояние
внутри плагина, но кнопка на экране остаётся прежней (`PanelManager::refresh()`
делает только перелейаут). Проверено и на 5.3.0, и на master. Поэтому плитка —
статичный вход в панель, а живое имя профиля показывает виджет в баре: бар
перерисовывается на каждом `update()`.

## Лицензия

MIT
