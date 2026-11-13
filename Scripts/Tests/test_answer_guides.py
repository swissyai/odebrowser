#!/usr/bin/env python3
"""Every written answer links a guide section that says the same thing.

The Command Bar's answers and Ode Help are written from the same cards: a live
card's `help` path names a guide page and a heading whose id is the card's id,
and that section holds the card's steps and note word for word. A pending card
links only the page its section will join.
"""

from __future__ import annotations

import json
import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
ANSWERS = REPOSITORY_ROOT / "OdeCore" / "src" / "OdeCore" / "Domain" / "Answers" / "answers.json"
GUIDES = REPOSITORY_ROOT / "HelpCenter" / "docs"
HEADING = re.compile(r"^(#{1,6}) .*\{#([a-z0-9-]+)\}\s*$")


def guide_pages() -> dict[str, str]:
    """Each guide's text by its slug, written as `/slug/`."""
    pages = {}
    for path in GUIDES.rglob("*.md*"):
        text = path.read_text()
        slug = re.search(r"^slug: (\S+)$", text, re.MULTILINE)
        if slug:
            name = slug.group(1).strip("/")
            pages["/" if not name else f"/{name}/"] = text
    return pages


def section(text: str, anchor: str) -> str | None:
    """The lines under the heading `anchor` names, up to the next heading of
    the same or a higher level, or None when the page has no such heading."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = HEADING.match(line)
        if match and match.group(2) == anchor:
            level = len(match.group(1))
            body = []
            for following in lines[index + 1:]:
                if re.match(rf"^#{{1,{level}}} ", following):
                    break
                body.append(following)
            return "\n".join(body)
    return None


class AnswerGuideTests(unittest.TestCase):
    def setUp(self) -> None:
        self.answers = json.loads(ANSWERS.read_text())
        self.pages = guide_pages()

    def test_every_live_answer_links_a_section_that_holds_its_steps(self) -> None:
        live = [card for card in self.answers["cards"] if card["status"] == "live"]
        self.assertGreaterEqual(len(live), 200)
        for card in live:
            with self.subTest(card=card["id"]):
                page, _, anchor = card["help"].partition("#")
                self.assertIn(page, self.pages, f"no guide is at {page}")
                self.assertEqual(anchor, card["id"], "a live answer links its own section")
                body = section(self.pages[page], anchor)
                self.assertIsNotNone(body, f"{page} has no heading {{#{anchor}}}")
                for step in card["steps"]:
                    self.assertIn(step, body)
                if "note" in card:
                    self.assertIn(card["note"], body)

    def test_every_pending_answer_links_a_guide_that_exists(self) -> None:
        for card in self.answers["cards"]:
            if card["status"] == "pending":
                with self.subTest(card=card["id"]):
                    self.assertIn(card["help"].partition("#")[0], self.pages)


if __name__ == "__main__":
    unittest.main()
