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

from PIL import Image

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


def main():
    os.makedirs(OUTPUT, exist_ok=True)
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
