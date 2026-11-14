# Рабочие заметки по аддону

Для агента. Правила кода — скилл `wow-addon` (`~/.claude/skills/wow-addon/SKILL.md`):
слои, snake_case файлов, полные имена, команды с тремя входами, тексты только в `lang/`.
`utilities/secrets.lua`, `event_bus.lua`, `localization.lua` взяты из SimpleAuras.

## Где что лежит

| | |
|---|---|
| исходник | `SimpleBuffTracker/` — **правим здесь** |
| игра видит | `B:\World of Warcraft\_forever_\Interface\AddOns\SimpleBuffTracker` — junction на `SimpleBuffTracker/` |
| клиент | WoW Forever, `_forever_`, `## Interface: 16001` |
| база | `SimpleBuffTrackerDB` (**на персонажа**): `settings`, `buffs` |

Команда — `/sbt` (и `/simplebufftracker`), клавиши `SIMPLEBUFFTRACKER_*`, глобал для
Bindings.xml — `SimpleBuffTracker_RunCommand`. Новый файл в `.toc` — только перезапуск клиента.
До первого релиза миграций нет: формат данных меняем сразу.

## Проверка

```bash
python scripts/build_lang.py
python scripts/lualint.py $(find SimpleBuffTracker -path SimpleBuffTracker/libs -prune -o -name "*.lua" -print)
python tests/run_tests.py
```

`tests/run_tests.py` гоняет аддон в LuaJIT (`pip install lupa`) со стабами клиента. Стабы
строгие: Show/Hide/SetPoint/SetAttribute защищённой кнопки или панели в бою — ошибка, перебор
аур, пока они скрыты, — ошибка. Внешний вид и реальный клик — только в игре.

## Настройки

Не своё окно, а страницы в «Настройки → Модификации → Simple Buff Tracker»
(`components/settings_window.lua`, AceConfig-3.0 + AceConfigDialog-3.0 `AddToBlizOptions`,
как в Purple Note): главная — панель (режим, размер, ряд, отступ, порог «скоро кончится»,
разблокировка, кнопка миникарты), подстраница «Бафы» — дерево, страница на баф (что
отслеживать, чем обновлять, выше/ниже, удалить). Таблица опций — функция, страница бафов
собирается заново при каждой перерисовке: после правки списка — `SettingsWindow.Refresh()`
(зовут и чат-команды). Поля ввода AceGUI принимают перетащенное заклинание/предмет.
Регистрация — один раз на `PLAYER_LOGIN`, `/sbt config` открывает и закрывает.

## Миникарта

`components/minimap_button.lua` на LibDBIcon (+ LibDataBroker, CallbackHandler в `libs/`):
левый клик — `/sbt config`, правый — `/sbt mode`. Позиция и
скрытие — `settings.minimap`, `/sbt minimap` прячет и показывает. В тестах `.xml` из `.toc`
не грузятся, библиотеки (LibDBIcon, AceConfig) подменяет `FAKE_LIBRARIES`; `Options(имя)`
строит таблицу опций, тесты жмут её `set`/`func`, как игрок.

## Модель

```
buff = { target = { spellId, name } | { weapon = "mainhand"|"offhand" },
         source = nil | { kind = "spell", spellId, name } | { kind = "item", itemId } }
```

* Аура ищется по `spellId` или по имени (имя покрывает все ранги).
* Чары на оружии — не аура: `GetWeaponEnchantInfo` (`dataflows/weapon_enchant.lua`),
  длительность = самый большой остаток, виденный для того же enchantId.
* Клик (`Buff.Action`): spell -> `type=spell`, item -> `type=item`, item на оружие ->
  `type=macro`, `/use item:ID` + `/use 16|17`.
* Режим `missing`: показываются нет-бафы и те, у кого осталось ≤ `settings.warnSeconds`
  (если сам баф длиннее порога).

## Что нельзя сломать

* Иконки — защищённые кнопки (`ui/buff_button.lua`, `SecureActionButtonTemplate`). В бою
  нельзя Show/Hide/SetPoint/SetSize/SetAttribute ни кнопок, ни панели (родитель):
  `components/buff_panel.lua` в бою только перекрашивает уже показанные иконки, раскладка —
  по `PLAYER_REGEN_ENABLED`. Серость — на текстуре, не `SetAlpha` кнопки.
* Ауры в бою скрыты (`C_Secrets.ShouldAurasBeSecret`), перебор их тогда — ошибка клиента:
  `AuraScan.Update` сначала спрашивает, в бою держит последнее чтение (таймеры — простые
  числа, истекают по часам).
* `ns.db` появляется по `ADDON_LOADED` — на уровне файла не кэшировать.
