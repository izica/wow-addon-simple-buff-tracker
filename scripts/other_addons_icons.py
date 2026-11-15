"""The icons of the author's addons for the shared Other Addons page.

    python scripts/other_addons_icons.py

Takes each addon's CurseForge icon (media/curseforge_icon.png in its repository,
next to this one) and writes it as SimpleBuffTracker/shared/other_addons/icons/<id>.tga,
64x64, uncompressed 32-bit TGA (what the game reads). The module carries the
icons itself: an addon that is not installed has no files in the game.
An addon without a CurseForge icon is listed at the end; its card keeps a game icon.
Needs Pillow.
"""

import os

from PIL import Image, ImageChops, ImageDraw

REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GITHUB = os.path.dirname(REPOSITORY)
OUTPUT = os.path.join(REPOSITORY, "SimpleBuffTracker", "shared", "other_addons", "icons")
SIZE = 64

# id in shared/other_addons/addons.lua -> the addon's repository folder
REPOSITORIES = {
    "purple_note": "wow-addon-blacklist",
    "prr": "wow-addon-reagent-or-material",
    "target_it": "wow-addon-fast-target-button",
    "simple_buff_tracker": "wow-addon-simple-buff-tracker",
}


GLYPH_SIZE = 32
GLYPH_SCALE = 8      # drawn bigger, scaled down for smooth edges


def draw_glyphs():
    """White glyphs the page tints itself: copy.tga (two sheets) and check.tga (a tick)."""
    canvas = GLYPH_SIZE * GLYPH_SCALE
    unit = canvas / 32
    white = (255, 255, 255, 255)

    copy = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(copy)
    line = round(2.6 * unit)
    radius = round(3 * unit)
    # the sheet behind: only its outline shows past the front one
    draw.rounded_rectangle((4 * unit, 3 * unit, 20 * unit, 22 * unit), radius=radius, outline=white, width=line)
    # the sheet in front, solid, with a gap around it so the two read apart
    draw.rounded_rectangle((9.5 * unit, 8.5 * unit, 28.5 * unit, 29.5 * unit), radius=radius, fill=(0, 0, 0, 0))
    gap = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(gap).rounded_rectangle((9.5 * unit, 8.5 * unit, 28.5 * unit, 29.5 * unit), radius=radius, fill=255)
    copy.putalpha(ImageChops.subtract(copy.getchannel("A"), gap))
    draw = ImageDraw.Draw(copy)
    draw.rounded_rectangle((12 * unit, 11 * unit, 28 * unit, 29 * unit), radius=radius, fill=white)

    check = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(check)
    draw.line([(6 * unit, 17 * unit), (13 * unit, 24 * unit), (26 * unit, 9 * unit)], fill=white,
              width=round(4 * unit), joint="curve")

    for name, image in (("copy", copy), ("check", check)):
        target = os.path.join(OUTPUT, name + ".tga")
        image.resize((GLYPH_SIZE, GLYPH_SIZE), Image.LANCZOS).save(target, compression=None)
        print(target)


def main():
    os.makedirs(OUTPUT, exist_ok=True)
    draw_glyphs()
    missing = []
    for addon_id, folder in REPOSITORIES.items():
        source = os.path.join(GITHUB, folder, "media", "curseforge_icon.png")
        if not os.path.exists(source):
            missing.append(addon_id)
            continue
        image = Image.open(source).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
        target = os.path.join(OUTPUT, addon_id + ".tga")
        image.save(target, compression=None)
        print(target)
    if missing:
        print("no CurseForge icon:", ", ".join(missing))


if __name__ == "__main__":
    main()
