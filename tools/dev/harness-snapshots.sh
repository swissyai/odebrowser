#!/bin/zsh
set -euo pipefail

# Saves snapshots of a built Ode app's main surfaces with the test harness,
# for visual checks without the screen: the sidebar, the Command Bar, the
# Advanced settings with import, export and the automatic export, the import
# step of setup, the restore window, the start page with the report notice
# after an unclean exit, a frozen page's bar and a stopped page. The app never activates; its
# windows stay where they open at zero opacity, passing clicks through,
# because a window off every display skips drawing some AppKit lists.
#
# Usage: tools/dev/harness-snapshots.sh /absolute/path/Ode.app /absolute/output/folder

if [[ $# -ne 2 || "$1" != /*.app || "$2" != /* ]]; then
  print -u2 "Usage: $0 /absolute/path/Ode.app /absolute/output/folder"
  exit 64
fi
app="$1"
out="$2"
mkdir -p "$out"
harness=(python3 -I "${0:A:h}/ode-harness.py" --profile "harness-snapshots-$$")
store() { "${harness[@]}" store; }
pid=""
cleanup() {
  [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
  local folder
  folder="$(store)"
  [[ "$folder" == */ControlPlane/Isolated/* ]] && rm -rf -- "${folder:?}"
  return 0
}
trap cleanup EXIT INT TERM HUP
shot() { "${harness[@]}" snapshot "$1" "$out/$1.png" "${@:2}" > /dev/null && print "saved $out/$1.png"; }

launch() { pid="$("${harness[@]}" launch "$app" --env ODE_TEST_HARNESS_WINDOWS=transparent)"; }
launch
"${harness[@]}" wait-phase finished --timeout 90
shot sidebar
"${harness[@]}" send openNewTab > /dev/null; sleep 0.6
shot command-bar
"${harness[@]}" send closeCommandBar > /dev/null
"${harness[@]}" send openSettings '{"pane": "advanced"}' > /dev/null; sleep 1
shot advanced-settings
"${harness[@]}" send openImportSetup > /dev/null; sleep 2
shot import-setup "Ode Setup"
"${harness[@]}" send showRestoreWindow > /dev/null; sleep 0.8
shot restore-window "Restore from an earlier copy"
kill -9 "$pid"; wait "$pid" 2>/dev/null || true

launch
"${harness[@]}" wait-phase firstWindow --timeout 90; sleep 3
shot start-page-after-unclean-exit
"${harness[@]}" send freezeVisiblePage > /dev/null
for i in {1..30}; do
  "${harness[@]}" send frozenBarState | grep -q '"frozen": true' && break
  sleep 0.5
done
shot frozen-bar
"${harness[@]}" send stopFrozenPage > /dev/null; sleep 1
shot stopped-page
"${harness[@]}" send quit '{"clean": true}' > /dev/null || true
wait "$pid" 2>/dev/null || true; pid=""
