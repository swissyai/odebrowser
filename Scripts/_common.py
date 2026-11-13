"""Helpers the release and maintenance scripts share: the repository root,
running a command, a file's SHA-256 and reading a JSON file.

The Chromium engine-input scripts that `control-plane/chromium_engine.py`
lists in `INPUTS` keep their own copies, so the engine key stays the same.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any

REPO = Path(__file__).resolve().parents[1]


def run(*command: object, **kwargs: Any) -> subprocess.CompletedProcess:
    """Runs `command`, each part as text, raising when it exits non-zero."""
    return subprocess.run([str(part) for part in command], check=True, text=True, **kwargs)


def sha256(path: str | Path) -> str:
    """The SHA-256 of the file at `path`, as lowercase hex, read in blocks."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: str | Path) -> Any:
    """The JSON value the file at `path` holds."""
    return json.loads(Path(path).read_text())
