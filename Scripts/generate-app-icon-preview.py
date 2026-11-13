#!/usr/bin/env python3
"""Render the app icon preview the iPhone settings and About screens show.

The system draws an Icon Composer icon only on the Home Screen, so the app
ships a flattened copy of its own: `<name>Preview`, light and dark, at 60 pt
and 3x, rendered by Icon Composer's ictool from `<name>.icon`, where <name>
is the product name ProductIdentity declares.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IDENTITY = ROOT / "OdeShared/Application/ProductIdentity.swift"
ICON_ROOT = ROOT / "OdeShared/Resources/OdeIcon"
PREVIEWS = ROOT / "OdeShared/Resources/AppIconPreviews.xcassets"


def main():
    name = re.search(r'static let name = "([^"]+)"', IDENTITY.read_text()).group(1)
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    exporter = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    preview = PREVIEWS / f"{name}Preview.imageset"
    preview.mkdir(parents=True, exist_ok=True)
    images = []
    for rendition, filename, appearance in [("Default", "icon.png", None), ("Dark", "icon-dark.png", "dark")]:
        subprocess.run([str(exporter), str(ICON_ROOT / f"{name}.icon"), "--export-image", "--output-file",
                        str(preview / filename), "--platform", "iOS", "--rendition", rendition,
                        "--width", "60", "--height", "60", "--scale", "3"], check=True, stdout=subprocess.DEVNULL)
        image = {"filename": filename, "idiom": "universal", "scale": "3x"}
        if appearance:
            image = {"appearances": [{"appearance": "luminosity", "value": appearance}], **image}
        images.append(image)
    (preview / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print(f"Rendered {preview.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
