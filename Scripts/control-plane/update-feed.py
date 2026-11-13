#!/usr/bin/env python3
"""Carries an update feed from one release to the next, and makes a local
copy of a feed for testing an update on this Mac.

  update-feed.py carry <previous updates folder> <new updates folder>

Copies the previous release's appcast.xml and every file its items name that
the folder holds (disk images, deltas, release notes) into the new release's
updates folder, cloning them where the volume allows. Sparkle's
generate_appcast then adds the new release to that appcast and keeps the
newest items, so people can go back to an earlier version from inside Ode.
An item whose disk image is missing stops the carry: remove the item from the
previous appcast first (that is also how a bad release is pulled).

  update-feed.py prune <updates folder>

Moves every file in the updates folder that the appcast no longer names, such
as the disk image of an item generate_appcast dropped, into old_updates/,
which is never published. Nothing is deleted.

  update-feed.py describe <appcast.xml> [<installed Info.plist>]

Lists the feed's items, and for each whether the installed Ode would take it:
Sparkle needs a newer build number, and Ode a newer marketing version.

  update-feed.py localize <updates folder> <new served folder> <url prefix>

Writes a served folder for a feed on this Mac: links to the files the feed
names, and an appcast whose downloads and release notes point at `url prefix`
(an http://127.0.0.1 address), without phased rollout, so a check offers the
newest item at once. The original feed's signature no longer covers the
copy, so the copy has to be signed again with Sparkle's sign_update before
Ode accepts it. The original folder is never changed.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import appcast  # noqa: E402

SIGNATURE = re.compile(r"\n?<!--\s*sparkle-signatures:.*?-->\n?", re.DOTALL)
ENCLOSURE_URL = re.compile(r'(<enclosure\b[^>]*?\burl=")([^"]+)(")', re.DOTALL)
NOTES_LINK = re.compile(r"(<sparkle:(?:releaseNotesLink|fullReleaseNotesLink)\b[^>]*>)\s*([^<\s]+)\s*(</sparkle:)")
PHASED = re.compile(r"[ \t]*<sparkle:phasedRolloutInterval>[^<]*</sparkle:phasedRolloutInterval>[ \t]*\n?")
RELEASE_NOTE_SUFFIXES = (".html", ".md", ".txt")


def basename(url: str) -> str:
    """The file a feed URL names, as it sits in the updates folder."""
    return urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit("/", 1)[-1])


def named_files(feed: str) -> tuple[list[str], list[str]]:
    """The full archives the feed's items download, and every other file it
    names: deltas and release notes."""
    archives, others = [], []
    for item in appcast.items(feed):
        archives += [basename(url) for url in item.downloads]
        others += [basename(url) for url in item.deltas + item.release_notes]
    for archive in archives:
        stem = archive.rsplit(".", 1)[0]
        others += [stem + suffix for suffix in RELEASE_NOTE_SUFFIXES]
    return list(dict.fromkeys(archives)), list(dict.fromkeys(name for name in others if name not in archives))


def clone(source: Path, destination: Path) -> None:
    """Copies `source` as an APFS clone where the volume allows it."""
    if subprocess.run(["cp", "-c", str(source), str(destination)], capture_output=True).returncode != 0:
        shutil.copy2(source, destination)


def carry(previous: Path, updates: Path) -> list[str]:
    feed_path = previous / "appcast.xml"
    if not feed_path.is_file():
        raise SystemExit(f"No appcast.xml in {previous}.")
    feed = feed_path.read_text(encoding="utf-8")
    archives, others = named_files(feed)
    missing = [name for name in archives if not (previous / name).is_file()]
    if missing:
        raise SystemExit("The previous feed names disk images its folder does not hold: " + ", ".join(missing)
                         + ". Remove those items from its appcast.xml first.")
    updates.mkdir(parents=True, exist_ok=True)
    carried = []
    for name in ["appcast.xml", *archives, *others]:
        source = previous / name
        if not source.is_file():
            continue
        destination = updates / name
        if destination.exists():
            raise SystemExit(f"{destination} already exists; a new release must not reuse an earlier file name.")
        clone(source, destination)
        carried.append(name)
    return carried


def prune(updates: Path) -> list[str]:
    feed = (updates / "appcast.xml").read_text(encoding="utf-8")
    archives, others = named_files(feed)
    named = {"appcast.xml", *archives, *others}
    moved = []
    for path in sorted(updates.iterdir()):
        if path.is_file() and not path.name.startswith(".") and path.name not in named:
            old = updates / "old_updates"
            old.mkdir(exist_ok=True)
            if (old / path.name).exists():
                raise SystemExit(f"{old / path.name} already exists.")
            path.rename(old / path.name)
            moved.append(path.name)
    return moved


def localize_feed(feed: str, prefix: str, served: set[str]) -> str:
    """The feed with downloads and notes that this folder serves pointing at
    `prefix`, no phased rollout and no signature."""
    def rewrite(match: re.Match) -> str:
        name = basename(match.group(2))
        if name not in served:
            return match.group(0)
        return match.group(1) + prefix + urllib.parse.quote(name) + match.group(3)

    feed = SIGNATURE.sub("\n", feed)
    feed = PHASED.sub("", feed)
    feed = ENCLOSURE_URL.sub(rewrite, feed)
    return NOTES_LINK.sub(rewrite, feed)


def localize(updates: Path, served: Path, prefix: str) -> list[str]:
    parsed = urllib.parse.urlparse(prefix)
    if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1") or not prefix.endswith("/"):
        raise SystemExit("The prefix must be an http://127.0.0.1 address ending in a slash.")
    feed_path = updates / "appcast.xml"
    if not feed_path.is_file():
        raise SystemExit(f"No appcast.xml in {updates}.")
    if served.exists():
        raise SystemExit(f"{served} already exists.")
    feed = feed_path.read_text(encoding="utf-8")
    archives, others = named_files(feed)
    present = [name for name in [*archives, *others] if (updates / name).is_file()]
    served.mkdir(parents=True)
    for name in present:
        os.symlink(updates.resolve() / name, served / name)
    (served / "appcast.xml").write_text(localize_feed(feed, prefix, set(present)), encoding="utf-8")
    return present


def numeric(version: str) -> list[int]:
    """A dotted version as numbers, the way Ode compares marketing versions."""
    return [int(part) if part.isdigit() else 0 for part in re.split(r"[.\-]", version.strip())]


def items(feed: str) -> list[tuple[str, str]]:
    """Each item's marketing version and build number, newest first as listed."""
    return [(item.short_version or item.version, item.version) for item in appcast.items(feed) if item.version]


def describe(feed: str, installed: dict | None) -> list[str]:
    lines = []
    if installed:
        lines.append(f"Installed: Ode {installed['CFBundleShortVersionString']} ({installed['CFBundleVersion']})")
    lines.append("This feed offers:")
    for short, build in items(feed):
        line = f"  Ode {short} ({build})"
        if installed:
            newer_build = numeric(build) > numeric(installed["CFBundleVersion"])
            newer_version = numeric(short) > numeric(installed["CFBundleShortVersionString"])
            line += ("  the installed Ode takes it" if newer_build and newer_version
                     else "  not offered to the installed Ode: " + ", ".join(
                         reason for reason, newer in (("build number not newer", newer_build),
                                                      ("marketing version not newer", newer_version)) if not newer))
        lines.append(line)
    return lines


def main() -> None:
    if len(sys.argv) == 4 and sys.argv[1] == "carry":
        for name in carry(Path(sys.argv[2]), Path(sys.argv[3])):
            print(f"Carried {name}")
    elif len(sys.argv) == 3 and sys.argv[1] == "prune":
        for name in prune(Path(sys.argv[2])):
            print(f"Moved {name} to old_updates/")
    elif len(sys.argv) in (3, 4) and sys.argv[1] == "describe":
        installed = None
        if len(sys.argv) == 4 and Path(sys.argv[3]).is_file():
            import plistlib
            with open(sys.argv[3], "rb") as stream:
                installed = plistlib.load(stream)
        print("\n".join(describe(Path(sys.argv[2]).read_text(encoding="utf-8"), installed)))
    elif len(sys.argv) == 5 and sys.argv[1] == "localize":
        served = localize(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
        print(f"Serving appcast.xml and the {len(served)} files it names.")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
