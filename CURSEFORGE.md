<!--
Summary (CurseForge "Summary" field, 40 words):
Tracks your buffs on one icon panel: all with timers, or only the missing ones, which glow. One click puts a buff back: recasts the spell, eats food for Well Fed, drinks an elixir or applies oil to your weapon.
-->

# Simple Buff Tracker

**Never pull without your buffs again.** Simple Buff Tracker puts the buffs you care about on one small panel of icons that look like action bar buttons. A missing buff greys out, glows and waits for you: **one click puts it back** – casts the spell, eats the food, drinks the elixir or puts the oil on your weapon. Made for **WoW Forever**.

Arcane Intellect, Well Fed, a scroll, Wizard Oil on the main hand and Flametongue on top of it – see what is up, what is about to run out and what is gone, at a glance.

## Features

### What it tracks
- **Any buff** – by spell name, ID or link. The name covers every rank of the spell.
- **Weapon enchants** – oils, sharpening stones, poisons and weapon spells like Flametongue, on the main hand or the off hand.
- **The exact enchant** – an oil and Flametongue can sit on one weapon at once. Pick which enchant a buff tracks, and each is tracked on its own.
- **Remembers what you have had** – every buff and enchant seen on your character is remembered and suggested while you type.

### The panel
- **Two modes** – all tracked buffs with their timers, or **only the missing ones** (and the ones about to run out).
- **Show before it runs out** – choose how early a buff counts as missing: for the whole panel, or for each buff on its own.
- **Missing buff glow** – Pixel Glow, Autocast Shine, the game's own action button proc glow, or a red pulse.
- **Icon style** – like the action bars, the same without the border, or plain square icons.
- **Your layout** – icon size, icons per line, spacing, and which way the icons grow: right, left, down or up.
- **Item count** – a buff from an item shows how many you have left in your bags, in red when you are out.
- **Move it anywhere** – unlock and drag it, right-click to lock again; or Shift + drag the locked panel.

### One click to put it back
Give a buff a **source**, and a click on its icon reapplies it:
- **a spell** – casts it;
- **an item** – food, a scroll, an elixir: uses it;
- **an oil, stone or poison** on a weapon buff – uses it and puts it on that weapon right away.

A buff without a source is only tracked.

### Easy to set up
- **Add a buff in one click** – open the window and Shift-click one of your buffs (top right of the screen).
- **Drag and drop** – drag a spell from the spellbook or an item from your bags into a field, or Shift-click it.
- **Suggestions while you type** – your spells, the items in your bags and every buff you have had, with their icons.
- **Drag to reorder** the buffs in the list.
- Buffs and settings are kept per character.

### In combat
The game hides auras from addons and locks action buttons in combat. The panel keeps what it saw before the pull: timers run out by the clock, the glow still comes up, clicks still work. A new set of icons appears as soon as combat ends.

## Settings

Left-click the minimap button (or `/sbt buffs`) – the **Buffs** tab: the tracked buffs and their sources.
Shift-click the minimap button (or `/sbt config`) – the **Panel** tab: lock, display mode, warning time, glow, growth direction, icon style, size, icons per line, spacing, the minimap button.

## Commands

| Command | |
|---|---|
| `/sbt buffs` | open the buff window |
| `/sbt config` | open the panel settings |
| `/sbt add Arcane Intellect = spell` | track a buff and recast it with a click |
| `/sbt add Well Fed = item Roasted Quail` | track a buff and eat the food with a click |
| `/sbt add mainhand = item Brilliant Wizard Oil` | track a weapon enchant and apply the oil with a click |
| `/sbt list`, `/sbt remove <number>` | list or remove the tracked buffs |
| `/sbt mode [all\|missing]` | switch the display mode |
| `/sbt lock`, `/sbt unlock`, `/sbt move` | lock or unlock the panel |
| `/sbt minimap` | show or hide the minimap button |

Key bindings (*Options → Keybindings → AddOns → Simple Buff Tracker*): switch the display mode, open the buff window, open the panel settings, lock or unlock the panel.

Minimap button: **left-click** – buffs, **Shift-click** – panel settings, **right-click** – lock or unlock the panel, **Shift-right-click** – switch the display mode.

## Feedback

A buff or a weapon enchant that is not seen? Type `/sbt debug`, take a screenshot of the chat and leave it in a comment – it will be fixed in the next version.
