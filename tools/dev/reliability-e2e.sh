#!/bin/zsh
set -euo pipefail
zmodload zsh/datetime

# Drives a built Ode app through the acceptance runs for restoring an earlier
# copy, the report after an unclean exit, frozen pages and the quit's cap,
# with the test harness: the app never activates and keeps its windows off
# the screens, and every step goes through the harness's commands. It uses an
# isolated, persistent profile of its own and never touches the installed one.
#
# Usage: tools/dev/reliability-e2e.sh /absolute/path/Ode.app [snapshot folder]
#
# The app must be a Debug or review build. Results print as PASS or FAIL
# lines; the script exits non-zero on any FAIL. With a snapshot folder, the
# frozen page's bar and the report notice are saved there as PNGs.

if [[ $# -lt 1 || "$1" != /*.app ]]; then
  print -u2 "Usage: $0 /absolute/path/Ode.app [snapshot folder]"
  exit 64
fi
app="$1"
shots="${2:-}"
harness=(python3 -I "${0:A:h}/ode-harness.py" --profile "reliability-e2e-$$")
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

pass() { print "PASS $1"; }
fail() { print "FAIL $1"; failures=$((failures + 1)); }
field() { python3 -I -c "import json,sys; v=json.load(sys.stdin); print(eval(sys.argv[1], {}, {'v': v}))" "$1"; }
launch() { pid="$("${harness[@]}" launch "$app")"; }
ready() { "${harness[@]}" wait-phase "${1:-firstWindow}" --timeout 90 || fail "the launch never reached ${1:-firstWindow}"; }
quit_cleanly() {
  "${harness[@]}" send quit '{"clean": true}' > /dev/null || true
  # The app is not this shell's child, so `wait` would return at once.
  "${harness[@]}" wait-exit "$pid" --timeout 30 || fail "the app did not quit"
  pid=""
}
snap() { [[ -n "$shots" ]] && "${harness[@]}" snapshot "$1" "$shots/$1.png" > /dev/null || true; }

# Each launch that opens a kept session keeps a dated copy of it first; the
# first launch of a new profile has no session to copy yet.
for i in 1 2 3; do launch; ready finished; quit_cleanly; done
copies=("$(store)"/Checkpoints/session-*.sqlite(N))
(( ${#copies} >= 2 )) && pass "each launch keeps a dated copy (${#copies})" || fail "dated copies: ${#copies}"

# A restore asked for while running happens at the next launch, which keeps
# the session it replaces as a copy first.
launch; ready
oldest="$("${harness[@]}" send listRecoveryCopies | field 'v["copies"][-1]["name"]')"
"${harness[@]}" send restoreCopy "{\"name\": \"$oldest\"}" > /dev/null || fail "the restore request was refused"
wait "$pid" 2>/dev/null || true; pid=""
launch; ready
[[ ! -e "$(store)/restore-request" ]] && pass "the next launch takes the restore request" || fail "the restore request is still there"
before="$("${harness[@]}" send listRecoveryCopies | field 'sum(1 for c in v["copies"] if c["beforeRestore"])')"
(( before >= 1 )) && pass "the replaced session is kept as a before-restore copy" || fail "no before-restore copy"
quit_cleanly

# A launch killed after it finished starting is reported at the next launch,
# and windows open on their start page rather than the last page.
launch; ready finished
kill -9 "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; pid=""
launch; ready
sleep 2
state="$("${harness[@]}" send state)"
reports="$("${harness[@]}" send reports | field 'len(v["reports"])')"
(( reports >= 1 )) && pass "a launch that ended uncleanly is kept as a report ($reports)" || fail "no report"
[[ "$(print -r -- "$state" | field 'v.get("reportNotice")')" == True ]] && pass "the report notice shows" || fail "no report notice"
[[ "$(print -r -- "$state" | field 'v["tab"]["startPage"]')" == True ]] && pass "the window opened on its start page" || fail "the window opened on a page"
snap report-notice

# A frozen page: the bar appears about ten seconds after an interaction.
"${harness[@]}" send freezeVisiblePage > /dev/null || fail "the frozen page did not open"
frozen=False
for i in {1..30}; do
  frozen="$("${harness[@]}" send frozenBarState | field 'v["frozen"]')"
  [[ "$frozen" == True ]] && break
  sleep 0.5
done
[[ "$frozen" == True ]] && pass "a frozen page shows its bar" || fail "the frozen page never showed its bar"
snap frozen-bar
"${harness[@]}" send stopFrozenPage > /dev/null || fail "Stop page failed"
sleep 1
[[ "$("${harness[@]}" send frozenBarState | field 'v["frozen"]')" == False ]] && pass "Stop page takes the bar away" || fail "the bar stayed after Stop page"
if /usr/bin/log show --last 2m --style compact --predicate 'category == "Pages"' 2>/dev/null | grep -q "the person stopped its page"; then
  pass "Stop page stopped the frozen tab's page"
else
  fail "the log does not show Stop page"
fi

# The quit's cap: with a page frozen, quitting takes at most about 3 seconds.
"${harness[@]}" send freezeVisiblePage > /dev/null || fail "the frozen page did not open again"
sleep 1
started=$EPOCHREALTIME
quit_cleanly
elapsed=$(( EPOCHREALTIME - started ))
(( elapsed <= 4.0 )) && pass "a frozen page held the quit ${elapsed}s" || fail "the quit took ${elapsed}s with a frozen page"

[[ "$("${harness[@]}" frontmost)" == "$front_before" ]] && pass "the app in front is unchanged" || fail "the app in front changed"
(( failures == 0 )) || { print -u2 "$failures acceptance checks failed"; exit 1; }
print "Every reliability acceptance check passed."
