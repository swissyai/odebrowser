#!/usr/bin/env python3
"""Generate the emoji keywords Ode's icon search and suggestions read.

The keywords come from Unicode CLDR's English annotations: the short name
each emoji is spoken as, and the words people search it by (airplane gives
aeroplane, fly, flying, jet, plane and travel). Both the annotations and the
derived annotations, which cover skin-tone, gender and family sequences, are
read from the cldr-json release named by --cldr-version. Keys drop the
variation selector U+FE0F so they match however a sequence is written.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from urllib.request import Request, urlopen


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CLDR_VERSION = "48.2.0"
DEFAULT_LOCALE = "en"
SOURCES = (
    "cldr-json/cldr-annotations-full/annotations/{locale}/annotations.json",
    "cldr-json/cldr-annotations-derived-full/annotationsDerived/{locale}/annotations.json",
)
DEFAULT_OUTPUT = REPOSITORY_ROOT / "OdeShared" / "Resources" / "EmojiKeywords.json"
VARIATION_SELECTOR = "\ufe0f"


def source_urls(version: str, locale: str) -> list[str]:
    return [
        f"https://raw.githubusercontent.com/unicode-org/cldr-json/{version}/{path.format(locale=locale)}"
        for path in SOURCES
    ]


def download(url: str) -> str:
    request = Request(url, headers={"User-Agent": "Ode emoji keyword generator"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8")


def annotations(document: dict) -> dict:
    root = document.get("annotations") or document.get("annotationsDerived")
    if not isinstance(root, dict) or "annotations" not in root:
        raise ValueError("The CLDR document has no annotations.")
    return root["annotations"]


def build(documents: list[tuple[str, str]], version: str, locale: str) -> dict[str, object]:
    keywords: dict[str, str] = {}
    for _, text in documents:
        for key, value in annotations(json.loads(text)).items():
            words: list[str] = []
            for word in value.get("tts", []) + value.get("default", []):
                word = word.strip().lower()
                if word and word not in words:
                    words.append(word)
            if words:
                keywords[key.replace(VARIATION_SELECTOR, "")] = " | ".join(words)
    if not keywords:
        raise ValueError("The CLDR sources contained no emoji keywords.")
    return {
        "metadata": {
            "cldrVersion": version,
            "locale": locale,
            "sources": [
                {"url": url, "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()}
                for url, text in documents
            ],
            "count": len(keywords),
        },
        "keywords": dict(sorted(keywords.items())),
    }


def render(catalog: dict[str, object]) -> str:
    return json.dumps(catalog, ensure_ascii=False, separators=(",", ":"), sort_keys=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cldr-version", default=DEFAULT_CLDR_VERSION)
    parser.add_argument("--locale", default=DEFAULT_LOCALE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the generated file differs instead of rewriting it.",
    )
    arguments = parser.parse_args()
    documents = [(url, download(url)) for url in source_urls(arguments.cldr_version, arguments.locale)]
    rendered = render(build(documents, arguments.cldr_version, arguments.locale))
    if arguments.check:
        current = arguments.output.read_text(encoding="utf-8") if arguments.output.exists() else ""
        if current != rendered:
            print(f"{arguments.output} is out of date; run {Path(__file__).name}.", file=sys.stderr)
            return 1
        return 0
    arguments.output.write_text(rendered, encoding="utf-8")
    print(f"Wrote {arguments.output.relative_to(REPOSITORY_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
