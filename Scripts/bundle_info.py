"""Reading property lists and app bundles' Info.plist values."""
from __future__ import annotations

from pathlib import Path
import plistlib
from typing import Any


def read_plist(path: str | Path) -> Any:
    """The property list at `path`, XML or binary."""
    with Path(path).open("rb") as stream:
        return plistlib.load(stream)


def info(app: str | Path) -> dict:
    """The Info.plist of the app bundle at `app`."""
    return read_plist(Path(app) / "Contents" / "Info.plist")
