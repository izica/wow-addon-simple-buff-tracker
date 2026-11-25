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
| база | `SimpleBuffTrackerDB` (**на персонажа**): `settings`, `buffs`, `seenAuras` (все бафы, виденные на персонаже), `seenEnchants`, `seenEnchantNames` |

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
  (с превью), «показывать до конца бафа» (свой `buff.warnSeconds` или как у панели), условия показа (вкладка),
  удалить (StaticPopup). Поле сохраняет по Enter и при потере фокуса, **только если текст
  изменился** (имя предмета не в сумках обратно не разберётся). Ошибка — красным под полями.
  Правки — `BuffService.SetTargetKind/SetAuraText/SetSourceKind/SetSourceText/SetIconText`.
* У каждого поля одно описание (`AddInput` в редакторе): что читает/пишет, где ищет подсказки, какие
  ссылки берёт (`takes("spell"|"item")`), серая заметка под полем (`form:Note`: что вводить, перетащи или shift-клик),
  картинка справа с тултипом игры (`SetItemByID` / `SetSpellByID`). Перетаскивание — `OnReceiveDrag` и клик
  с предметом на курсоре (`GetCursorInfo`), шифт-клик — `MainWindow.PickLink`; оба через `editor:TakeLink`.
* **Панель**: `components/panel_settings.lua`, одна колонка в таком порядке: «Закрепить панель»
  (галочка = закреплена) первой, режим, порог, куда растут иконки, вид, размер (шаг 1), ряд, отступ,
  кнопка миникарты последней. Селекты и слайдеры одной нарисованной ширины (`sliderWidth` формы).
  Разблокированная — зелёный мувер: тащить левой, правый клик закрепляет (`/sbt lock`).
  Закреплённую панель двигают Shift + перетаскивание: при зажатом Shift и мыши над панелью
  поднимается тот же мувер, только без зелёного (`BuffPanel.UpdateMover`, `events/modifier.lua`;
  не в бою, перед боем `StopDragging`). Shift-клик по иконкам поэтому ничего не кастует.
* **Подсказки** во всех полях: `ui/suggestions.lua` (общий список под полем, страта TOOLTIP,
  ↑/↓ + Enter, клик) + `dataflows/icon_search.lua` (`SOURCES`: бафы на игроке, виденные раньше
  (`AuraScan.Seen`, `seenAuras` пишет `AuraScan.Update`), книга, сумки;
  поле предмета — только сумки). У остальных картинок клиента имён нет.
* `/sbt buffs` (левый клик по миникарте) — вкладка «Бафы», `/sbt config` (shift + левый) — «Панель».
  Escape закрывает (`UISpecialFrames`). Но игра закрывает все `UISpecialFrames` и когда открывает большую
  свою панель (книга/таланты: `ShowUIPanel` -> `CloseWindows` -> `CloseSpecialWindows`, UIParentPanelManager.lua
  ветки forever) — окно возвращается: `OnHide` не от нас запоминает `GetTime()`, хук `ShowUIPanel`
  (`events/ui_panels.lua`) в тот же кадр -> `MainWindow.OnGamePanelShown` показывает его снова. Escape панелей
  не открывает — остаётся закрытием. Свои закрытия (команда) идут с `isClosingOurselves`. Чат-команды перерисовывают окно (`MainWindow.Refresh`).
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

## Куда растёт панель

`settings.growDirection`: right / left / down / up (`GROW_DIRECTION`), `iconsPerRow` — иконок в линии (ряд
или столбец). Панель держится за середину края, откуда растут иконки (`GROW_ANCHOR`: вправо — LEFT,
влево — RIGHT, вниз — TOP, вверх — BOTTOM): `settings.position = { point = якорь, x, y от низа-лева экрана,
isCorner = true }` (`PinToAnchor` в `components/buff_panel.lua`; имя `isCorner` осталось от старых версий) —
больше иконок, панель длиннее от якоря, новые линии расходятся на обе стороны, якорь на месте. Старая позиция
(угол или CENTER) и смена направления переводятся на новый якорь при раскладке, панель не прыгает.

Место панели — только наше: клиент свою копию не хранит (`SetDontSavePosition(true)`, после перетаскивания
`SetUserPlaced(false)`). Иначе панель, сдвинутая через `StartMoving`, после входа ставилась клиентом по его
точке (левая / центр / правая треть экрана) и росла то влево, то в обе стороны. Каждая раскладка заново
ставит панель на её якорь (`PlacePanel`), кроме времени перетаскивания (тикер раскладывает раз в секунду —
панель прыгала под мышью). На разблокированной панели (и при Shift) мувер показывает якорь: открытый замок и
стрелку в сторону роста — снаружи панели, напротив середины стартового края, чтобы не закрывать иконки
(`PlaceAnchor`; от края наружу: стрелка, потом замок). Замок — своя картинка `media/lock_open.tga` (32×32,
рисует `scripts/make_icon.py`): путь к замку в текстурах клиента Forever не проверить.

## Иконка на панели

`ui/buff_button.lua`: защищённая кнопка, внутри — вид по `settings.iconTemplate` (`ICON_TEMPLATE`, селект
«Вид иконок» на вкладке «Панель»):
* `action_bar` — `ActionButtonTemplate` игры как картинка (`SetScale(size / 45)`, `EnableMouse(false)`), как
  в SimpleAuras;
* `borderless` — тот же шаблон, его рамка невидима (`GetNormalTexture`, `Border`, `SlotArt`, `SlotBackground`,
  `FloatingBG` -> alpha 0), маска иконки (скругление) остаётся;
* `square` — только картинка с обрезанной рамкой, квадратная.
Каждый вид создаётся при первом выборе и хранится, `SetTemplate` показывает один (только вне боя, в бою
селект отказывает). Счётчик предметов и подсветка — на слое над всеми видами. Нет шаблона — `square`.

Действие кнопки — только на левой кнопке мыши: `SetAction` пишет `type` как `type1`. Правый клик —
`HookScript("OnClick")` (на отпускании) -> `MainWindow.ShowBuff(buff)`: окно на вкладке «Бафы» с этим бафом,
работает и в бою (окно не защищённое).

Подсветка отсутствующего бафа — `ui/glow.lua` (`settings.missingGlow`, `GLOW_EFFECT`, селект «Подсветка
отсутствующего бафа»): `pixel` (линии бегут по краю), `autocast` (искры `Interface\Cooldown\star4`),
`proc` (`ActionButtonSpellAlertTemplate` клиента из Blizzard_ActionBar/Shared; нет шаблона — `pixel`),
`pulse` (красная рамка мигает). Всё рисуется текстурами в OnUpdate, без шаблонов анимаций. Рамка подсветки —
обычный фрейм над кнопкой, не защищённый: показывается и в бою (`Paint` -> `SetGlow`).

## Страницы в «Настройки → Модификации»

`components/settings_pages.lua` регистрирует на `PLAYER_LOGIN` (`Settings.RegisterCanvasLayoutCategory`,
подкатегория `RegisterCanvasLayoutSubcategory`, `RegisterAddOnCategory`; нет API — страниц нет):
* главная — `components/about_page.lua`: иконка, название, версия (`GetAddOnMetadata`), описание
  (`about.description`), большая кнопка «Открыть настройки бафов» — закрывает настройки игры
  (`SettingsPanel:Close(true)`) и открывает наше окно (`MainWindow.Open`);
* «Другие аддоны» — **самостоятельный модуль** `shared/other_addons/`, один и тот же во всех аддонах автора.
  Копируется папкой целиком, от аддона берёт только `ns` (кладёт себя в `ns.OtherAddons`):
  `addons.lua` — список (папка, название, `picture` — иконка CurseForge внутри модуля `icons/<id>.tga`,
  или `icon` — иконка игры, у кого иконки CurseForge нет), `lang/<en|de|fr|es|it|pt|ru|zh>.lua` — свои тексты
  на 8 языках (строка и фичи пунктами; старт — язык клиента, запасной английский; китайский предлагается
  только на китайском клиенте — в шрифтах других клиентов нет иероглифов). Селект языка в шапке страницы
  меняет тексты сразу; выбор модуль пишет в `options.saved.language`, если аддон дал таблицу (у нас
  `ns.db.otherAddons`), иначе до `/reload`. Новый язык — файл в `lang/` модуля + строка в `.toc`;
  тест проверяет, что у каждого языка есть все тексты и столько же пунктов, сколько в английском.
  `other_addons_page.lua` — карточки (статус: установлен / установлен, выключен / не установлен —
  `C_AddOns.IsAddOnLoaded` / `DoesAddOnExist`; высота по тексту, страница прокручивается; иконка копирования
  сразу после названия (`icons/copy.tga`, ставится в `Fit` по `GetStringWidth`, тултип) или клик по названию
  превращает само название в поле на месте (`card.nameBox`, тот же шрифт, текст выделен, в тултипе «Ctrl+C»);
  Ctrl+C копирует и на следующем кадре возвращает название, иконка на миг — зелёная галочка `icons/check.tga`;
  буфера обмена у аддонов нет; иконки копирования рисует `scripts/other_addons_icons.py`) и
  `ns.OtherAddons.Register(category, { exclude = ADDON, saved = таблица })` — подстраница под категорией
  аддона, свой аддон не показывается. Порядок в `.toc`: addons, все 8 файлов lang (en первым), page.
  Иконки собирает `python scripts/other_addons_icons.py` из `media/curseforge_icon.png` соседних репозиториев.
  Не-ASCII текст модуля (кириллица, умлауты, иероглифы) лежит только в его `lang/`.

## Миникарта

`components/minimap_button.lua` на LibDBIcon (+ LibDataBroker, CallbackHandler в `libs/`):
левый клик — `/sbt buffs`, shift + левый — `/sbt config`, правый — `/sbt move` (закрепить / разблокировать),
shift + правый — `/sbt mode`.
В тестах `.xml` из `.toc` не грузятся, LibDBIcon подменяет `FAKE_LIBRARIES`.

Картинка кнопки (и `## IconTexture` в списке аддонов) — своя: `SimpleBuffTracker/media/icon.tga`,
64×64, несжатый 32-битный TGA, путь без расширения в `Constants.ADDON_ICON`. Её и иконку
CurseForge (`media/curseforge_icon.png`, 400×400) рисует `python scripts/make_icon.py`
(концепт `swipe`: арканная искра с затемнением таймера; `variants` — все концепты для сравнения).
Новый файл картинки клиент видит только после перезапуска.

## Модель

```
buff = { target = { spellId, name } | { weapon = "mainhand"|"offhand" } | { isEquipped = true, equipItemId },
         source = nil | { kind = "spell", spellId, name } | { kind = "item", itemId } | { kind = "equip" } }
```

* Аура ищется по `spellId` или по имени (имя покрывает все ранги).
* **Надетый предмет** (`TARGET_KIND.EQUIPPED`, «Отслеживать: Надетый предмет»): активен, пока предмет надет
  (`Item.IsEquipped` -> `C_Item.IsEquippedItem`), без таймера; `isEquipped` держит вид, пока предмет не выбран.
  Клик — `source.kind = "equip"` -> макрос `/equip item:ID` (слот выбирает игра), ставится сам при выборе вида;
  поля «Заклинание/Предмет» и ползунка предупреждения у него нет. Чат: `/sbt add equip <предмет>`.
  Вид в селекте — `BuffService.TargetKind`.
* Чары на оружии — не аура: `GetWeaponEnchantInfo` (`dataflows/weapon_enchant.lua`),
  длительность = самый большой остаток, виденный для того же enchantId.
* **Какие именно чары** (масло и Flametongue): **в Forever на одной руке висят оба сразу**, а
  `GetWeaponEnchantInfo` отдаёт одни (проверено в игре: масло 30 мин + Flametongue 5 60 мин -> только id 1665 и
  3569 с). Поэтому список чар руки — из тултипа (`C_TooltipInfo.GetInventoryItem`), строки по форматам клиента
  `ITEM_ENCHANT_TIME_LEFT_HOURS/_MIN/_SEC` (переведены клиентом; `|4hour:hrs;` раскрывается в два точных
  слова), у каждой имя и остаток. Id из API привязывается к строке с ближайшим остатком (±90 с) ->
  `seenEnchants[id] = имя`; все имена — `seenEnchantNames`. Тултип читается вне боя, в бою строки тикают по часам.
  Баф выбирает чары **по имени** (`target.enchantName`, `BuffService.SetEnchant`); старые бафы по id берут
  имя по id (`WeaponEnchant.TargetName`). `WeaponEnchant.Find` — чары руки для бафа.
  В редакторе — селект «Какие чары» вместо поля «Баф».
* Клик (`Buff.Action`): spell -> `type=spell`, item -> `type=item`, item на оружие ->
  `type=macro`, `/use item:ID` + `/use 16|17`.
* Режим `missing`: показываются нет-бафы и те, у кого осталось ≤ `settings.warnSeconds`
  (если сам баф длиннее порога). Порог («Предупреждать за») работает **в обоих режимах**: истекающий баф
  светится той же подсветкой, что и отсутствующий (`Paint`, `needsAttention`), иначе в режиме «Все бафы»
  ползунок ничего бы не делал.
* Баф без цели (только что добавлен, `Buff.HasTarget` = false) на панель не ставится — раньше висел «?».
  «Добавить баф» сразу ставит курсор в поле «Баф» (`BuffEditor:StartEditing`).
* Первый вход без бафов — одна строка в чат, где их добавлять (`settings.welcomed`, `events/addon_loaded.lua`):
  пустая панель невидима, новичок иначе не знает, с чего начать.
* **Условия показа** — `buff.conditions` (nil — всегда): `hiddenPlaces = { world|party|raid|pvp = true }` — где **не**
  показывать (тип инстанса из `IsInInstance`, `INSTANCE_KIND`; `world` — вне инстансов; по умолчанию все галочки
  стоят — хранятся только снятые; арена и сценарий не в списке — показываются всегда; ничего — везде; несколько — любой из них), `itemId` (только пока
  предмет в сумках), `talent = { spellId, name }` + `talentMissing` (только пока изучен / не изучен). Должны
  выполняться все заданные; не выполнены — бафа нет ни в каком режиме (`BuffConditions.Hold` в
  `BuffService.VisibleStates`). Изучен ли: сначала дерево талантов по имени (`dataflows/talents.lua`,
  классический `GetTalentInfo` -> name, icon, tier, column, rank; другой формат API — талантов нет), потом
  `IsPlayerSpell` / `C_SpellBook.IsSpellKnown` по id, имя без id — `Spell.Find`. Пустая таблица условий
  удаляется. Перерисовка — `events/conditions.lua` (зона, таланты, заклинания; событие, которого нет на
  клиенте, пропускается — `ns.Events.OnIfExists`), сумки — `BAG_UPDATE_DELAYED`. В бою раскладки нет, как
  и для режима `missing`: баф пропадёт/появится после боя.
* **Зоны** (`conditions.zones = { { mapId, name } }`, пусто — любая): `dataflows/zones.lua` на `C_Map`. Где
  игрок — текущая карта и **все карты над ней** (`Zones.Here`): выбранный Элвиннский лес держит и Златоземье.
  Список для подсказок — все потомки корневой карты типа Zone/Dungeon (`GetMapChildrenInfo(root, nil, true)`,
  читается раз). Пикер — **поле с метками** (`ui/tag_input.lua`): выбранные зоны стоят метками в бронзовой
  рамке внутри поля, курсор после них, поле растёт рядами (`form:Field(control, getHeight)`). Фокус на пустом
  поле сразу открывает список с зоной, где игрок («(вы здесь)», `input:ShowSuggestionsFor("")`), ввод —
  подсказки зон (`IconSearch.SOURCES.ZONES`, выбранные не предлагаются; список висит под полем — `anchor`
  у `AttachSuggestions`). Клик по метке убирает зону, Backspace в пустом поле — последнюю. Без `C_Map` — по имени (`GetRealZoneText`).
* **Бой** (`conditions.combat = "in"|"out"`): флаг боя — из событий (`BuffConditions.SetInCombat` в
  `events/conditions.lua`), не `InCombatLockdown`. Панель перекладывается на `PLAYER_REGEN_DISABLED` — последний
  момент, когда защищённые иконки ещё можно показать/скрыть, — и на `PLAYER_REGEN_ENABLED`.
* Страница условий **прокручивается** (`ui/scroll_area.lua`, `conditionsArea`): условий больше, чем высота окна;
  `test_editor_fits` проверяет только основную страницу.
* В редакторе две **вкладки сверху** — «Баф» | «Условия (N)» (`ui/segment_tabs.lua`: текст, выбранная —
  белая с золотым подчёркиванием; страницы `mainPage` / `conditionsPage` в `buff_editor.lua`, у каждой своя
  форма). Под полями бафа места нет (окно 610, проверяет `test_editor_fits`). Выбранная вкладка остаётся при
  выборе другого бафа — одно условие нескольким бафам подряд. Места — четыре галочки в один ряд (мир, подземелье, рейд, поле боя)
  (`form:CheckboxRow`). Поле таланта берёт spell- и talent-ссылки, подсказки — дерево талантов и книга
  вместе с пассивками (`IconSearch.SOURCES.TALENTS`).
* На странице условий — строка «Сейчас: на панели» (зелёная) или «Сейчас: скрыт (почему)» (красная):
  `BuffConditions.Reason` -> ключ `settings.hidden_*` и аргумент; тот же текст — в тултипе серой строки списка.
  Все места сняты — красное предупреждение вместо заметки (`BuffConditions.IsNowhere`). Вкладки редактора —
  «Основное» | «Условия» («Баф» путался с вкладкой окна «Бафы»).
* Ряд кнопок редактора — только «Удалить» справа, ошибка правки — слева от неё. Кнопок «Выше/Ниже» нет:
  порядок — перетаскиванием в списке. Баф, который условия сейчас скрывают, в списке серый, в тултипе —
  почему (список перерисовывают зона, таланты, сумки — `events/conditions.lua`).

## Что нельзя сломать

* Размер текста — только шрифтовым объектом игры (`GameFontHighlightSmall2` и т.п., `SetFontObject` /
  шаблон в `CreateFontString`), **не** `SetFont(файл, размер)` с файлом из `GetFont()`: объект — семейство
  с файлом на каждый алфавит, `SetFont` оставляет один латинский, и кириллица (и иероглифы) становятся
  квадратами (так было на странице «Другие аддоны»). `SetFont` годится только для цифр (таймер на иконке).
* Иконки — защищённые кнопки (`ui/buff_button.lua`, `SecureActionButtonTemplate`). В бою
  нельзя Show/Hide/SetPoint/SetSize/SetAttribute ни кнопок, ни панели (родитель):
  `components/buff_panel.lua` в бою только перекрашивает уже показанные иконки, раскладка —
  по `PLAYER_REGEN_ENABLED`. Серость — на текстуре, не `SetAlpha` кнопки.
* Ауры в бою скрыты (`C_Secrets.ShouldAurasBeSecret`), перебор их тогда — ошибка клиента:
  `AuraScan.Update` сначала спрашивает, в бою держит последнее чтение (таймеры — простые
  числа, истекают по часам).
* `ns.db` появляется по `ADDON_LOADED` — на уровне файла не кэшировать.
