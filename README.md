# Simple Buff Tracker

A World of Warcraft addon (Forever client, interface 16001): your buffs as icons on one panel.

* **Two modes**: all tracked buffs with their timers, or only the missing ones
  (and the ones about to run out).
* **A buff** is a spell aura (by name, id or link; the name covers every rank)
  or a temporary weapon enchant (`mainhand` / `offhand`).
* **A source** (optional) puts the buff back with a click on its icon: a spell
  to cast, or an item to use -- food, scroll, elixir; on a weapon buff -- oil,
  stone or poison, put on the weapon right away. Without a source the buff is
  only tracked.

## Settings

* **Buff window** (left click on the minimap button, or `/sbt buffs`): the buffs --
  add, edit, reorder, delete. Drag a spell from the spellbook or an item from the
  bags into a field, or shift-click a buff of yours (top right of the screen): into
  the field you are typing in, or as a new buff.
* **Panel settings** -- Options -> AddOns -> Simple Buff Tracker (shift + left click
  on the minimap button, or `/sbt config`).

## Commands

```
/sbt add Arcane Intellect = spell
/sbt add Well Fed = item Roasted Quail
/sbt add mainhand = item [Brilliant Wizard Oil]
/sbt add Trueshot Aura
/sbt list
/sbt remove <number>
/sbt mode [all|missing]
/sbt unlock | lock | move
/sbt minimap
/sbt config
/sbt buffs
/sbt size <pixels>
/sbt row <count>
/sbt warn <seconds>
```

In combat the client hides auras from addons and does not let them move
secure buttons: the panel keeps what it saw before combat (timers still run
out by the clock), a new set of icons appears after combat.
