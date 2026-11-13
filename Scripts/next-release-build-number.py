#!/usr/bin/env python3
"""Keep new Sparkle builds newer than every completed channel publication."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import appcast  # noqa: E402


APPCAST_FILENAMES = (
    "appcast.xml", "appcast-webkit.xml",
    "appcast-development.xml", "appcast-development-webkit.xml",
    "appcast-experimental.xml", "appcast-experimental-webkit.xml",
)


def next_build_number(git_ref: str, minimum: int) -> int:
    if minimum < 1:
        raise ValueError("The minimum build number must be positive")
    build_number = minimum
    for filename in APPCAST_FILENAMES:
        reference = f"{git_ref}:{filename}"
        exists = subprocess.run(
            ["git", "cat-file", "-e", reference], capture_output=True, check=False,
        )
        if exists.returncode != 0:
            continue
        feed = subprocess.run(
            ["git", "show", reference], capture_output=True, check=True, text=True,
        ).stdout
        for item in appcast.items(feed):
            if item.build is None:
                raise ValueError(f"Invalid Sparkle build number in {reference}: {item.version!r}")
            build_number = max(build_number, item.build + 1)
    return build_number


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--git-ref", required=True)
    parser.add_argument("--minimum", required=True, type=int)
    arguments = parser.parse_args()
    print(next_build_number(arguments.git_ref, arguments.minimum))


if __name__ == "__main__":
    main()
