--!nonstrict
-- shortcut.luau — плитка эквалайзера на главной Control Center.
--
-- Подпись статичная: Noctalia 5.3 собирает плитки один раз и не перерисовывает
-- текст, даже если скрипт вызывает setLabel (проверено: update() тикает, label
-- меняется внутри, на экране — нет). Живое имя профиля показывает виджет в баре
-- (widget.luau); здесь — только вход в панель.

function update()
  shortcut.setIcon("adjustments-horizontal")
  shortcut.setLabel("Эквалайзер")
  shortcut.setActive(true)
  shortcut.setEnabled(true)
end

function onClick()
  noctalia.togglePanel("vlad-dev/equalizer:panel")
end

update()
