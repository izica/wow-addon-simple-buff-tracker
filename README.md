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

## Window

Left click on the minimap button or `/sbt buffs`:

* **Buffs** -- the tracked buffs on the left; on the right the chosen one: what is
  tracked, how a click puts it back, its icon, how long before its end it shows up.
  Every field suggests pictures and names while you type (your buffs, spellbook,
  bags); while typing, shift-click an item in the bags, a spell in the spellbook or a
  buff of yours (top right of the screen). With no field in focus a shift-clicked
  buff of yours is added as a new one.
* **Panel** (shift + left click, or `/sbt config`) -- the mode, icon size, icons in a
  row, spacing, the warning time, unlock, the minimap button.

The icons on the panel look like the buttons of the action bars.

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
