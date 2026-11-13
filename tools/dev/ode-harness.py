#!/usr/bin/env python3
"""Drives a harnessed Ode launch, so acceptance and latency runs never need
the screen or the keyboard.

A launch with ODE_TEST_HARNESS=1 and an isolated session never activates,
keeps its windows off the screens, answers JSON commands on a socket beside
its isolated session and appends each launch phase to a log there. This
client launches such an app, waits for phases, sends commands and reads the
launch record.

Usage:
  ode-harness.py --profile ID store
  ode-harness.py --profile ID launch /absolute/path/Ode.app [--env KEY=VALUE ...]
  ode-harness.py --profile ID wait-phase PHASE [--timeout SECONDS]
  ode-harness.py --profile ID send COMMAND ['{"json": "arguments"}'] [--timeout SECONDS]
  ode-harness.py --profile ID snapshot NAME DESTINATION.png [WINDOW TITLE]
  ode-harness.py --profile ID moments DESTINATION.json [--reset]
  ode-harness.py --profile ID streak
  ode-harness.py --profile ID age-launches HOURS
  ode-harness.py frontmost
  ode-harness.py wait-exit PID [--timeout SECONDS]

`launch` prints the process id and returns at once; the phase log is cleared
first, so it holds only this launch's phases. Commands print their JSON reply
and exit non-zero when the reply is not ok. `moments` writes the launch's
moments summary to DESTINATION.json and a table of it beside it as
DESTINATION.txt, prints the table, and with --reset starts the ledger again;
`Scripts/check_moment_budgets.py` checks the JSON against the release gates.
"""

import argparse
import datetime
import glob
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import time

PHASE_LOG = "harness-phases.log"
SOCKET = "harness.sock"


def stores(profile):
    """Where an isolated session for `profile` can live: a sandboxed build
    keeps it in its container, an unsandboxed one in Application Support.
    Harnessed builds are development builds, whose data folder is `Ode Dev`;
    the released app's `Ode` folder is never looked in."""
    folder = os.environ.get("ODE_PRODUCT_FOLDER", "Ode Dev")
    namespace = hashlib.sha256(profile.encode()).hexdigest()
    tail = os.path.join("Library", "Application Support", folder, "ControlPlane", "Isolated", namespace)
    containers = sorted(glob.glob(os.path.expanduser(os.path.join("~", "Library", "Containers", "*", "Data", tail))))
    return containers + [os.path.join(os.path.expanduser("~"), tail)]


def store(profile):
    """The isolated session folder in use: the one holding the harness's
    socket or launch record, else the most recently changed one."""
    found = [path for path in stores(profile) if os.path.isdir(path)]
    for name in (SOCKET, "launches.json", PHASE_LOG):
        for path in found:
            if os.path.exists(os.path.join(path, name)):
                return path
    return max(found, key=os.path.getmtime) if found else stores(profile)[-1]


def frontmost():
    """The bundle identifier of the app in front, without asking any app."""
    asn = subprocess.run(["lsappinfo", "front"], capture_output=True, text=True).stdout.strip()
    info = subprocess.run(["lsappinfo", "info", "-only", "bundleid", asn], capture_output=True, text=True).stdout
    return info.split("=")[-1].strip().strip('"') if "=" in info else asn


def launch(profile, app, extra_env):
    for folder in stores(profile):
        log = os.path.join(folder, PHASE_LOG)
        if os.path.exists(log):
            os.remove(log)
    info = subprocess.run(["defaults", "read", os.path.join(app, "Contents", "Info"), "CFBundleExecutable"],
                          capture_output=True, text=True, check=True).stdout.strip()
    env = dict(os.environ, ODE_ISOLATED_SESSION="1", ODE_ISOLATED_PERSISTENCE_ID=profile, ODE_TEST_HARNESS="1")
    for pair in extra_env:
        key, _, value = pair.partition("=")
        env[key] = value
    process = subprocess.Popen([os.path.join(app, "Contents", "MacOS", info)], env=env,
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    return process.pid


def phases(profile):
    try:
        with open(os.path.join(store(profile), PHASE_LOG)) as stream:
            return [line.split()[0] for line in stream if line.strip()]
    except FileNotFoundError:
        return []


def wait_phase(profile, phase, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if phase in phases(profile):
            return True
        time.sleep(0.02)
    return False


def send(profile, command, arguments=None, timeout=120):
    folder = store(profile)
    request = dict(arguments or {}, command=command)
    deadline = time.monotonic() + 30
    while True:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.settimeout(timeout)
            previous = os.getcwd()
            os.chdir(folder)
            try:
                client.connect(SOCKET)
            finally:
                os.chdir(previous)
            break
        except (FileNotFoundError, ConnectionRefusedError):
            client.close()
            if time.monotonic() > deadline:
                raise
            time.sleep(0.1)
    with client:
        client.sendall((json.dumps(request) + "\n").encode())
        reply = b""
        while not reply.endswith(b"\n"):
            chunk = client.recv(65536)
            if not chunk:
                break
            reply += chunk
    return json.loads(reply or b'{"ok": false, "error": "no reply"}')


def moments_table(summary):
    """One screen of a moments summary: per moment, every moment counted and
    the recent ones' median, 95th percentile and longest in milliseconds,
    then the same for each tag over the recent ones, and the counters."""
    def milliseconds(value):
        return "-" if value is None else f"{value:.1f}"

    rows = [("moment", "tag", "n", "median", "p95", "max", "counters")]
    for name in sorted(summary.get("moments", {})):
        moment = summary["moments"][name]
        counters = " ".join(f"{key}={value}" for key, value in sorted(moment.get("counters", {}).items()))
        rows.append((name, "all", str(moment.get("count", 0)), milliseconds(moment.get("median")),
                     milliseconds(moment.get("p95")), milliseconds(moment.get("max")), counters))
        for tag in sorted(moment.get("tags", {})):
            values = moment["tags"][tag]
            rows.append(("", tag, str(values["count"]), milliseconds(values["median"]),
                         milliseconds(values["p95"]), milliseconds(values["max"]), ""))
    widths = [max(len(row[column]) for row in rows) for column in range(6)]
    lines = []
    for row in rows:
        cells = [cell.ljust(widths[column]) if column < 2 else cell.rjust(widths[column])
                 for column, cell in enumerate(row[:6])]
        lines.append(("  ".join(cells) + ("  " + row[6] if row[6] else "")).rstrip())
    return "\n".join(lines) + "\n"


def write_moments(profile, destination, reset, timeout):
    """Asks the launch for its moments summary and writes it, and its table,
    where the caller named."""
    reply = send(profile, "moments", {"reset": reset}, timeout=timeout)
    if not reply.get("ok"):
        print(json.dumps(reply, sort_keys=True))
        return 1
    summary = reply["summary"]
    table = moments_table(summary)
    with open(destination, "w") as stream:
        json.dump(summary, stream, indent=2, sort_keys=True)
        stream.write("\n")
    with open(os.path.splitext(destination)[0] + ".txt", "w") as stream:
        stream.write(table)
    print(table, end="")
    return 0


def launches(profile):
    with open(os.path.join(store(profile), "launches.json")) as stream:
        return json.load(stream)["launches"]


def streak(profile):
    parse = lambda text: datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    count, reference = 0, datetime.datetime.now(datetime.timezone.utc)
    for entry in reversed(launches(profile)):
        started = parse(entry["startedAt"])
        if (reference - started).total_seconds() > 6 * 3600:
            break
        if entry["outcome"] != "started":
            count += 1 if entry.get("safeMode") else 0
            break
        count += 1
        reference = started
    return count


def age_launches(profile, hours):
    path = os.path.join(store(profile), "launches.json")
    with open(path) as stream:
        data = json.load(stream)
    for entry in data["launches"]:
        started = datetime.datetime.fromisoformat(entry["startedAt"].replace("Z", "+00:00"))
        entry["startedAt"] = (started - datetime.timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(path, "w") as stream:
        json.dump(data, stream)


def wait_exit(pid, timeout):
    """Waits for a launched app, which is not this shell's child, to exit."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(0.05)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profile")
    parser.add_argument("action")
    parser.add_argument("rest", nargs="*")
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("--reset", action="store_true")
    args = parser.parse_args()
    if args.action == "frontmost":
        print(frontmost())
        return 0
    if args.action == "wait-exit":
        return 0 if wait_exit(int(args.rest[0]), args.timeout) else 1
    if not args.profile:
        parser.error("--profile is required")
    if args.action == "store":
        print(store(args.profile))
    elif args.action == "launch":
        print(launch(args.profile, args.rest[0], args.env))
    elif args.action == "wait-phase":
        return 0 if wait_phase(args.profile, args.rest[0], args.timeout) else 1
    elif args.action == "send":
        arguments = json.loads(args.rest[1]) if len(args.rest) > 1 else {}
        reply = send(args.profile, args.rest[0], arguments, timeout=args.timeout)
        print(json.dumps(reply, sort_keys=True))
        return 0 if reply.get("ok") else 1
    elif args.action == "snapshot":
        arguments = {"name": args.rest[0]}
        if len(args.rest) > 2:
            arguments["window"] = args.rest[2]
        reply = send(args.profile, "snapshotWindow", arguments, timeout=args.timeout)
        if not reply.get("ok"):
            print(json.dumps(reply, sort_keys=True))
            return 1
        shutil.copyfile(reply["path"], args.rest[1])
        print(args.rest[1])
    elif args.action == "moments":
        return write_moments(args.profile, args.rest[0], args.reset, args.timeout)
    elif args.action == "streak":
        print(streak(args.profile))
    elif args.action == "age-launches":
        age_launches(args.profile, float(args.rest[0]))
    else:
        parser.error(f"unknown action {args.action}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
