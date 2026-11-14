# Рабочие заметки по аддону

Для агента. Правила кода — скилл `wow-addon` (`~/.claude/skills/wow-addon/SKILL.md`):
слои, snake_case файлов, полные имена, команды с тремя входами, тексты только в `lang/`.
`utilities/secrets.lua`, `event_bus.lua`, `localization.lua` взяты из SimpleAuras, `ui/` — из LootBuddy.

## Где что лежит

| | |
|---|---|
| исходник | `SimpleBuffTracker/` — **правим здесь** |
| игра видит | `B:\World of Warcraft\_forever_\Interface\AddOns\SimpleBuffTracker` — junction на `SimpleBuffTracker/` |
| клиент | WoW Forever, `_forever_`, `## Interface: 16001` |
| база | `SimpleBuffTrackerDB` (**на персонажа**): `settings`, `buffs`, `seenAuras` (все бафы, виденные на персонаже), `seenEnchants` |

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

## Окно аддона

Своё окно в стиле Forever, без AceConfig (`components/main_window.lua`): рамка окон игры
(`ui/client_border.lua`, `ui/panel.lua` с `gameSkin`), вкладки под окном (`ui/tab_bar.lua`).
Контролы `ui/` взяты из LootBuddy (они из PRR): селект — `WowStyle1DropdownTemplate`, слайдер со
стрелками — `MinimalSliderTemplate` (`ui/step_slider.lua`), поле — в рамке селекта
(`common-dropdown-textholder`), `ui/inset_panel.lua`, `ui/scroll_area.lua`, `ui/checkbox.lua`.
**Раскладка формы — только через `ui/form_layout.lua`**: контролы игры рисуют за своим фреймом (рамка
селекта и поля — 8 слева/справа, 7 сверху, 9 снизу; стрелки слайдера — 15 по бокам), и поставленные по
одному x стояли лесенкой. Форма ставит их по нарисованному краю: левый край под меткой, правый — одна линия.
Группы (`form:Group()`, `group:SetShown`, `form:Layout()`): скрытое поле с меткой и заметкой места не
занимает, остальные встают вплотную — редактор перекладывает форму на каждом `Display`.

* **Бафы**: слева `components/buff_list.lua` (иконка + имя, «Добавить баф»; порядок — перетаскиванием
  строки, золотая линия показывает место, `BuffService.MoveTo`), справа
  `components/buff_editor.lua`: что отслеживать, баф, чем обновлять, заклинание/предмет, иконка
  (с превью), «показывать до конца бафа» (свой `buff.warnSeconds` или как у панели), выше/ниже,
  удалить (StaticPopup). Поле сохраняет по Enter и при потере фокуса, **только если текст
  изменился** (имя предмета не в сумках обратно не разберётся). Ошибка — красным под полями.
  Правки — `BuffService.SetTargetKind/SetAuraText/SetSourceKind/SetSourceText/SetIconText`.
* У каждого поля одно описание (`AddInput` в редакторе): что читает/пишет, где ищет подсказки, какие
  ссылки берёт (`takes("spell"|"item")`), серая заметка под полем (`form:Note`: что вводить, перетащи или shift-клик),
  картинка справа с тултипом игры (`SetItemByID` / `SetSpellByID`). Перетаскивание — `OnReceiveDrag` и клик
  с предметом на курсоре (`GetCursorInfo`), шифт-клик — `MainWindow.PickLink`; оба через `editor:TakeLink`.
* **Панель**: `components/panel_settings.lua` — режим, размер, ряд, отступ, порог, разблокировка,
  закрепить панель (галочка = закреплена), кнопка миникарты.
* **Подсказки** во всех полях: `ui/suggestions.lua` (общий список под полем, страта TOOLTIP,
  ↑/↓ + Enter, клик) + `dataflows/icon_search.lua` (`SOURCES`: бафы на игроке, виденные раньше
  (`AuraScan.Seen`, `seenAuras` пишет `AuraScan.Update`), книга, сумки;
  поле предмета — только сумки). У остальных картинок клиента имён нет.
* `/sbt buffs` (левый клик по миникарте) — вкладка «Бафы», `/sbt config` (shift + левый) — «Панель».
  Escape закрывает (`UISpecialFrames`). Чат-команды перерисовывают окно (`MainWindow.Refresh`).
* **Shift-клик по своему бафу** (окно бафов клиента): в Forever кнопки бафов — `AuraButtonMixin`
  (Blizzard_BuffFrame), клик шлёт `EventRegistry` `"BuffButton.OnClick"`, аура —
  `buttonInfo.auraInstanceID` -> `C_UnitAuras.GetAuraDataByAuraInstanceID` (`events/buff_frame.lua`)
  -> `MainWindow.PickAura`: в поле в фокусе (иконке — spell id, остальным — имя), без фокуса —
  новый баф (или уже отслеживаемый). Чары на оружии событие не шлют.
* **Shift-клик по предмету/заклинанию** — хук на `ChatFrameUtil.InsertLink` (`events/chat_link.lua`)
  -> `MainWindow.PickLink`: поле предмета берёт item-ссылку, поля бафа/заклинания — spell, иконка — обе.
* Иконка бафа: `target.icon` запоминается, когда баф впервые виден на игроке (`RememberAura`),
  название текстом сверяется с текущими бафами (`BuffParser.ParseSpell`); выученная иконка
  перерисовывает окно (`BuffService.TakeLearnedIcons` в `ns.Core.Refresh`). Своя иконка
  (`buff.icon` + `buff.iconText`, `BuffParser.ParseIcon`: spell id, `item:<id>`, `icon:<id>`,
  ссылки) важнее всего.
* `/sbt debug` — что клиент отдаёт по каждой ауре (секретное помечено) и что нашлось для каждого бафа.

## Иконка на панели

`ui/buff_button.lua`: защищённая кнопка, внутри — `ActionButtonTemplate` игры как картинка
(`SetScale(size / 45)`, `EnableMouse(false)`), как в SimpleAuras; подсветка — на слое над шаблоном.
Нет шаблона — картинка в тонкой рамке.

## Миникарта

`components/minimap_button.lua` на LibDBIcon (+ LibDataBroker, CallbackHandler в `libs/`):
левый клик — `/sbt buffs`, shift + левый — `/sbt config`, правый — `/sbt mode`.
В тестах `.xml` из `.toc` не грузятся, LibDBIcon подменяет `FAKE_LIBRARIES`.

## Модель

```
buff = { target = { spellId, name } | { weapon = "mainhand"|"offhand" },
         source = nil | { kind = "spell", spellId, name } | { kind = "item", itemId } }
```

* Аура ищется по `spellId` или по имени (имя покрывает все ранги).
* Чары на оружии — не аура: `GetWeaponEnchantInfo` (`dataflows/weapon_enchant.lua`),
  длительность = самый большой остаток, виденный для того же enchantId.
* **Какие именно чары** (масло или Flametongue на одной руке): `target.enchantId` + `enchantName`, nil — любые.
  Имя чар — только в тултипе оружия (`C_TooltipInfo.GetInventoryItem`): зелёная строка «Имя (время)», не
  «Use:/Equip:/Chance on hit:» (своего типа строки у временных чар нет); читается вне боя, раз на id,
  копится в `seenEnchants[id] = имя`. Совпадение — тот же id или то же имя (`WeaponEnchant.Matches`).
  В редакторе — селект «Какие чары» вместо поля «Баф».
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
