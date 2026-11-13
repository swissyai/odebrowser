#!/bin/zsh
set -euo pipefail

# Drives a built Ode app through the launch-safety acceptance runs with the
# test harness: it stops launches with SIGKILL at the phases the harness
# reports, reads the launch record to check the startup streak, and checks
# that the third failed start asks how to start before the Chromium
# framework is loaded. The app never activates and keeps its windows off the
# screens, so the Mac stays free. It uses an isolated, persistent profile of
# its own and never touches the installed one.
#
# Usage: tools/dev/launch-safety-e2e.sh /absolute/path/Ode.app
#
# The app must be a Debug or review build, which include the harness. Results
# print as PASS or FAIL lines; the script exits non-zero on any FAIL.

if [[ $# -ne 1 || "$1" != /*.app ]]; then
  print -u2 "Usage: $0 /absolute/path/Ode.app"
  exit 64
fi
app="$1"
harness=(python3 -I "${0:A:h}/ode-harness.py" --profile "launch-safety-e2e-$$")
# A sandboxed build keeps its session in its container, which exists only
# once it launched, so the folder is looked up each time it is needed.
store() { "${harness[@]}" store; }
failures=0
pid=""
cleanup() {
  [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
  local folder
  folder="$(store)"
  [[ "$folder" == */ControlPlane/Isolated/* ]] && rm -rf -- "${folder:?}"
  return 0
}
trap cleanup EXIT INT TERM HUP
front_before="$("${harness[@]}" frontmost)"

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then print "PASS $name ($actual)"; else print "FAIL $name: expected $expected, got $actual"; failures=$((failures + 1)); fi
}
launch() { pid="$("${harness[@]}" launch "$app" "$@" --env ODE_LAUNCH_SAFETY_PROMPTS=1)"; }
kill_at() {
  local phase="$1"
  "${harness[@]}" wait-phase "$phase" --timeout 60 || print "FAIL the launch never reached $phase"
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pid=""
}

# A finished launch: the first window stays up past the 15 s mark.
launch; kill_at finished
check "a launch killed after it finished counts as finished" 0 "$("${harness[@]}" streak)"

# Launches killed while starting, and once the first window opened.
launch; kill_at native
check "a launch killed before the core opened counts" 1 "$("${harness[@]}" streak)"
launch; kill_at firstWindow
check "a launch killed after its first window opened counts" 2 "$("${harness[@]}" streak)"

# The third launch asks before any engine loads.
launch
if "${harness[@]}" wait-phase safeStart --timeout 30; then
  print "PASS the third launch asks how to start"
else
  print "FAIL the third launch did not ask how to start"; failures=$((failures + 1))
fi
asking="$("${harness[@]}" send state | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("askingHowToStart"))')"
check "the harness sees the safe start window" True "$asking"
if vmmap "$pid" 2>/dev/null | grep -q "Chromium Framework"; then
  print "FAIL the safe start window appeared after the Chromium framework loaded"; failures=$((failures + 1))
else
  print "PASS the Chromium framework is not loaded while the safe start window asks"
fi
kill -9 "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; pid=""

# Launches 7 hours apart do not add up: age the record instead of waiting.
"${harness[@]}" age-launches 7
check "launches 7 hours apart do not add up" 0 "$("${harness[@]}" streak)"

# A clean quit resets the streak.
launch; kill_at native
launch
"${harness[@]}" wait-phase firstWindow --timeout 60 || print "FAIL the launch never opened a window"
"${harness[@]}" send quit '{"clean": true}' > /dev/null
# The app is not this shell's child, so `wait` returns at once; the quit is
# recorded only once the process has exited.
"${harness[@]}" wait-exit "$pid" --timeout 30 || print "FAIL the app did not quit"
pid=""
check "a clean quit resets the streak" 0 "$("${harness[@]}" streak)"

# Silenced: no window even after many failed starts.
for i in 1 2 3; do launch; kill_at native; done
launch --env ODE_SUPPRESS_LAUNCH_PROMPTS=1
if "${harness[@]}" wait-phase firstWindow --timeout 60 && ! grep -q '^safeStart' "$(store)/harness-phases.log"; then
  print "PASS a silenced launch starts without asking"
else
  print "FAIL a silenced launch asked how to start or never opened"; failures=$((failures + 1))
fi
kill -9 "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; pid=""

front_after="$("${harness[@]}" frontmost)"
check "the app in front is unchanged" "$front_before" "$front_after"
(( failures == 0 )) || { print -u2 "$failures acceptance checks failed"; exit 1; }
print "Every launch-safety acceptance check passed."
