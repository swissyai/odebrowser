"""Reads a Sparkle appcast: each item's version, short version and build
number, the oldest macOS it runs on, its channel, and the files it names,
with the signature of its download.

The scripts that read a feed read it here, so they agree on what each item
offers. A script that changes a feed edits its text instead, so the bytes
Sparkle signed stay as they were everywhere else.
"""
from __future__ import annotations

from dataclasses import dataclass
import re
import xml.etree.ElementTree as ElementTree

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
RELEASE_NOTES = (SPARKLE + "releaseNotesLink", SPARKLE + "fullReleaseNotesLink")
BUILD = re.compile(r"[0-9]+")


@dataclass(frozen=True)
class Item:
    """One `<item>` of a feed. An element the item leaves out reads as empty
    text; every URL is as the feed spells it."""

    version: str
    """`sparkle:version`, the build number Sparkle compares."""
    short_version: str
    """`sparkle:shortVersionString`, the marketing version people see."""
    minimum_system_version: str
    channel: str
    """`sparkle:channel`; empty for an item every channel takes."""
    downloads: tuple[str, ...]
    """The full archives the item downloads, outside `sparkle:deltas`."""
    signature: str | None
    """The EdDSA signature of the first download."""
    deltas: tuple[str, ...]
    release_notes: tuple[str, ...]
    """The `releaseNotesLink` and `fullReleaseNotesLink` addresses, in order."""

    @property
    def build(self) -> int | None:
        """`version` as a number, or None when it is not only digits."""
        return int(self.version) if BUILD.fullmatch(self.version) else None

    @property
    def url(self) -> str | None:
        """The first download."""
        return self.downloads[0] if self.downloads else None


def items(feed: str) -> list[Item]:
    """Every item of the feed's text, in the order it lists them. Raises
    `xml.etree.ElementTree.ParseError` for text that is not XML."""
    return [_item(element) for element in ElementTree.fromstring(feed).findall(".//item")]


def _item(element: ElementTree.Element) -> Item:
    def text(name: str) -> str:
        return (element.findtext(SPARKLE + name) or "").strip()

    in_deltas = [enclosure for deltas in element.iter(SPARKLE + "deltas") for enclosure in deltas.iter("enclosure")]
    delta_ids = {id(enclosure) for enclosure in in_deltas}
    full = [enclosure for enclosure in element.iter("enclosure")
            if id(enclosure) not in delta_ids and enclosure.get("url")]
    return Item(
        version=text("version"),
        short_version=text("shortVersionString"),
        minimum_system_version=text("minimumSystemVersion"),
        channel=text("channel"),
        downloads=tuple(enclosure.get("url", "") for enclosure in full),
        signature=full[0].get(SPARKLE + "edSignature") if full else None,
        deltas=tuple(enclosure.get("url", "") for enclosure in in_deltas if enclosure.get("url")),
        release_notes=tuple(link.text.strip() for link in element.iter()
                            if link.tag in RELEASE_NOTES and link.text and link.text.strip()),
    )
