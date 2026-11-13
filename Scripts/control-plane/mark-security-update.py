#!/usr/bin/env python3
"""Marks the appcast item for one build as a security-only release, which Ode
shows on its update card as "Security fixes only. Restart when it suits you."

Adds `<ode:securityOnly>true</ode:securityOnly>` to the item whose
`sparkle:version` is BUILD, declares the `ode` namespace on `<rss>`, and
removes the feed's embedded signature, so the feed must be signed again with
Sparkle's sign_update before it is published.

Usage: Scripts/control-plane/mark-security-update.py <appcast.xml> <build>
"""

import re
import sys

NAMESPACE = "https://odebrowser.com/xml-namespaces/ode"
ELEMENT = "<ode:securityOnly>true</ode:securityOnly>"
SIGNATURE = re.compile(r"\n?<!--\s*sparkle-signatures:.*?-->\n?", re.DOTALL)


def mark(feed: str, build: str) -> str:
    feed = SIGNATURE.sub("\n", feed)
    if "xmlns:ode=" not in feed:
        feed, count = re.subn(r"<rss\b", f'<rss xmlns:ode="{NAMESPACE}"', feed, count=1)
        if count != 1:
            raise SystemExit("The feed has no <rss> element.")
    version = re.compile(r"<sparkle:version>\s*" + re.escape(build) + r"\s*</sparkle:version>")
    items = list(re.finditer(r"<item>.*?</item>", feed, re.DOTALL))
    marked = [item for item in items if version.search(item.group(0))]
    if len(marked) != 1:
        raise SystemExit(f"Expected one item for build {build}, found {len(marked)}.")
    item = marked[0]
    body = item.group(0)
    if ELEMENT not in body:
        body = body.replace("</item>", f"    {ELEMENT}\n        </item>")
    return feed[:item.start()] + body + feed[item.end():]


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    path, build = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as stream:
        feed = stream.read()
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(mark(feed, build))


if __name__ == "__main__":
    main()
