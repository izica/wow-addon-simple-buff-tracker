"""Pack the addon into builds/<Addon>-<version>.zip for CurseForge.

The version is taken from "## Version:" in the addon's .toc. Inside the zip is
one folder named like the addon -- exactly what goes into Interface/AddOns.
Files the game does not load are left out: lang/*.json (the sources of the
generated lang/*.lua).

Run from anywhere, after build_lang.py and the linter:
    python scripts/build_zip.py
An existing zip of the same version is refused: raise the version first.
"""

import os
import re
import sys
import zipfile

REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "SimpleBuffTracker"
ADDON_FOLDER = os.path.join(REPOSITORY, ADDON)
BUILDS_FOLDER = os.path.join(REPOSITORY, "builds")


def read_version():
    toc_path = os.path.join(ADDON_FOLDER, ADDON + ".toc")
    with open(toc_path, encoding="utf-8") as toc:
        for line in toc:
            match = re.match(r"^##\s*Version:\s*(\S+)", line)
            if match:
                return match.group(1)
    sys.exit("no '## Version:' line in " + toc_path)


def is_packed(relative_path):
    parts = relative_path.replace("\\", "/").split("/")
    is_lang_source = len(parts) == 2 and parts[0] == "lang" and parts[1].endswith(".json")
    return not is_lang_source


def main():
    version = read_version()
    os.makedirs(BUILDS_FOLDER, exist_ok=True)
    zip_path = os.path.join(BUILDS_FOLDER, "%s-%s.zip" % (ADDON, version))
    if os.path.exists(zip_path):
        sys.exit("already built: %s -- raise the version in the .toc" % zip_path)

    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for folder, _, files in os.walk(ADDON_FOLDER):
            for name in sorted(files):
                path = os.path.join(folder, name)
                relative_path = os.path.relpath(path, ADDON_FOLDER)
                if not is_packed(relative_path):
                    continue
                archive.write(path, ADDON + "/" + relative_path.replace("\\", "/"))
                count += 1
    print("%s: %d files" % (os.path.relpath(zip_path, REPOSITORY), count))


if __name__ == "__main__":
    main()
