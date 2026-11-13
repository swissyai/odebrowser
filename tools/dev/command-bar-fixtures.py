#!/usr/bin/env python3
"""Serves the Command Bar's live services from this Mac for test and harness runs.

A Debug or review build launched with ODE_NETWORK_FIXTURE=http://127.0.0.1:PORT
sends its search suggestion and Wikipedia requests here, under the host they
were for, so a run never reaches a live service. Every request is printed with
its User-Agent, which lets a run show what the app sent.

Usage:
  tools/dev/command-bar-fixtures.py [--port 8765]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import urllib.parse
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Topics the fixture Wikipedia knows, with text written for these fixtures.
ARTICLES = {
    "Marie Curie": {
        "description": "Physicist and chemist",
        "extract": "Marie Curie was a physicist and chemist who studied radioactivity. "
        "She won Nobel Prizes in two sciences.",
        "file": "Fixture_portrait.png",
        "artist": "Fixture Photographer",
        "license": "Public domain",
    },
    "Lisbon": {
        "description": "Capital of Portugal",
        "extract": "Lisbon is the capital and largest city of Portugal.",
        "file": None,
    },
}


def png(width: int = 64, height: int = 64) -> bytes:
    """A small warm gradient, as a picture the cards can show."""
    rows = b"".join(
        b"\x00" + b"".join(bytes((200, 120 + x, 90 + y)) for x in range(width)) for y in range(height)
    )

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def key_of(title: str) -> str:
    return title.replace(" ", "_")


def article_for_key(key: str) -> tuple[str, dict] | None:
    for title, article in ARTICLES.items():
        if key_of(title) == key:
            return title, article
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass

    def do_GET(self) -> None:  # noqa: N802 - the server's method name
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        host, _, path = parsed.path.lstrip("/").partition("/")
        path = "/" + path
        print(f"GET {host}{path}?{parsed.query} UA={self.headers.get('User-Agent', '')}", flush=True)
        if host.endswith("wikipedia.org") and path == "/w/rest.php/v1/search/title":
            asked = query.get("q", [""])[0].strip().lower()
            pages = [{"key": key_of(title), "title": title} for title in ARTICLES if title.lower() == asked]
            return self.json({"pages": pages})
        if host.endswith("wikipedia.org") and path.startswith("/api/rest_v1/page/summary/"):
            found = article_for_key(urllib.parse.unquote(path.rsplit("/", 1)[1]))
            if not found:
                return self.json({"type": "not_found"}, status=404)
            title, article = found
            summary = {
                "type": "standard", "title": title, "description": article["description"], "extract": article["extract"],
                "content_urls": {"desktop": {"page": f"https://{host}/wiki/{key_of(title)}"}},
            }
            if article["file"]:
                summary["thumbnail"] = {
                    "source": f"https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/{article['file']}/320px-{article['file']}"
                }
            return self.json(summary)
        if host == "commons.wikimedia.org" and path == "/w/api.php":
            name = query.get("titles", [""])[0].removeprefix("File:")
            article = next((article for article in ARTICLES.values() if article["file"] == name), None)
            metadata = {} if article is None else {
                "Artist": {"value": f"<a href=\"https://commons.wikimedia.org\">{article['artist']}</a>"},
                "LicenseShortName": {"value": article["license"]},
            }
            return self.json({"query": {"pages": [{"imageinfo": [{"extmetadata": metadata}]}]}})
        if host == "upload.wikimedia.org":
            return self.send(png(), "image/png")
        if path in ("/complete/search", "/ac/", "/osjson.aspx", "/api/suggest", "/api/autosuggest"):
            typed = (query.get("q") or query.get("query") or [""])[0]
            return self.json([typed, [f"{typed} fixture one", f"{typed} fixture two", f"{typed} fixture three"]])
        self.json({"error": "no fixture"}, status=404)

    def json(self, value: object, status: int = 200) -> None:
        self.send(json.dumps(value).encode(), "application/json", status)

    def send(self, body: bytes, kind: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8765)
    arguments = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), Handler)
    print(f"Serving Command Bar fixtures on http://127.0.0.1:{arguments.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
