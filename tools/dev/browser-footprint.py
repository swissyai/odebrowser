#!/usr/bin/env python3
"""Physical memory footprint of a running Chromium-based browser, by process.

Measures every process whose command line contains PATTERN with macOS
`footprint` (the figure Activity Monitor shows as Memory, compressed pages at
their compressed size), one process at a time because `footprint -j` records
only the first target it is given. Groups processes by Chromium `--type` and
splits each into the regions Chromium tags: V8's JavaScript heap,
PartitionAlloc (Chromium's malloc), Blink's garbage-collected heap, and
IOSurface (window and tile surfaces).

Chromium tags its mappings with PageTag values 252 to 255 above
VM_MEMORY_APPLICATION_SPECIFIC_1 (240), which `footprint` reports as
"app-specific tag 13" to "app-specific tag 16".

Usage:
  tools/dev/browser-footprint.py /Arc.app/ [/Ode.app/ ...] [--json OUT]
"""

import argparse
import collections
import json
import os
import re
import subprocess
import tempfile

TAGS = {
    "app-specific tag 16": "v8",
    "app-specific tag 14": "partition_alloc",
    "app-specific tag 13": "blink_gc",
    "IOSurface": "iosurface",
}
MIB = 2**20


def processes(pattern):
    table = subprocess.check_output(["ps", "-axo", "pid=,args="], text=True)
    found = []
    for line in table.splitlines():
        pid, _, command = line.strip().partition(" ")
        if pattern in command:
            found.append((int(pid), command))
    return found


def kind(command):
    match = re.search(r"--type=([a-z-]+)", command)
    name = match.group(1) if match else "browser"
    if name == "utility":
        sub = re.search(r"--utility-sub-type=([\w.]+)", command)
        name += ":" + (sub.group(1).split(".")[-1] if sub else "unknown")
    if name == "renderer" and "--extension-process" in command:
        name = "renderer:extension"
    return name


def measure(pid):
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "footprint.json")
        done = subprocess.run(["footprint", "-j", path, "-p", str(pid)], capture_output=True)
        if done.returncode != 0 or not os.path.exists(path):
            return None
        with open(path) as stream:
            measured = json.load(stream)["processes"]
    return measured[0] if measured else None


def summary(pattern):
    rows = []
    for pid, command in processes(pattern):
        process = measure(pid)
        if process is None:
            continue
        regions = {label: 0 for label in TAGS.values()}
        for category, values in process["categories"].items():
            if category in TAGS:
                regions[TAGS[category]] += values.get("dirty", 0) + values.get("swapped", 0)
        rows.append({"pid": pid, "kind": kind(command), "footprint": process["footprint"], **regions})
    return rows


def report(pattern, rows):
    total = sum(row["footprint"] for row in rows)
    print(f"{pattern}: {total / MIB:.0f} MiB footprint in {len(rows)} processes")
    groups = collections.defaultdict(lambda: collections.Counter())
    for row in rows:
        group = groups[row["kind"]]
        group["count"] += 1
        for key in ("footprint", *TAGS.values()):
            group[key] += row[key]
    header = f"  {'type':28s} {'n':>3s} {'footprint':>10s} {'v8':>7s} {'alloc':>7s} {'blinkgc':>7s} {'surface':>7s}"
    print(header)
    for name, group in sorted(groups.items(), key=lambda item: -item[1]["footprint"]):
        print(f"  {name:28s} {group['count']:3d} {group['footprint'] / MIB:10.0f} {group['v8'] / MIB:7.0f} "
              f"{group['partition_alloc'] / MIB:7.0f} {group['blink_gc'] / MIB:7.0f} {group['iosurface'] / MIB:7.0f}")
    print("  region columns count dirty and swapped pages, so they can exceed the footprint")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("patterns", nargs="+", help="Text each process's command line contains, such as /Arc.app/")
    parser.add_argument("--json", help="Also write every measured process to this file")
    args = parser.parse_args()
    measured = {}
    for pattern in args.patterns:
        measured[pattern] = summary(pattern)
        report(pattern, measured[pattern])
    if args.json:
        with open(args.json, "w") as stream:
            json.dump(measured, stream, indent=2)


if __name__ == "__main__":
    main()
