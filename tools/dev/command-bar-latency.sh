#!/bin/zsh
set -euo pipefail

# Times the Command Bar's open through New Tab with the test harness: one
# cold open first, then rounds of warm opens, each from the command to the
# rows, the field entering the window, the field taking the keyboard and the
# commit of the frame that first shows it. The app never activates and keeps
# its windows off the screens.
#
# Usage: tools/dev/command-bar-latency.sh /absolute/path/Ode.app [rounds] [opens per round]
#
# Prints median, 95th percentile, first and fastest in ms per timing.

if [[ $# -lt 1 || "$1" != /*.app ]]; then
  print -u2 "Usage: $0 /absolute/path/Ode.app [rounds] [opens per round]"
  exit 64
fi
app="$1"
rounds="${2:-3}"
opens="${3:-30}"
harness=(python3 -I "${0:A:h}/ode-harness.py" --profile "command-bar-latency-$$")
# A sandboxed build keeps its session in its container, which exists only
# once it launched, so the folder is looked up each time it is needed.
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
front_before="$("${harness[@]}" frontmost)"

pid="$("${harness[@]}" launch "$app")"
"${harness[@]}" wait-phase finished --timeout 90 || { print -u2 "The launch never finished"; exit 1; }
results="$(mktemp -d "${TMPDIR%/}/ode-latency.XXXXXX")"
"${harness[@]}" send measureCommandBar '{"runs": 1}' --timeout 60 > "$results/cold.json"
for round in $(seq 1 "$rounds"); do
  "${harness[@]}" send measureCommandBar "{\"runs\": $opens}" --timeout 600 > "$results/round-$round.json"
done
"${harness[@]}" send quit '{"clean": true}' > /dev/null || true
wait "$pid" 2>/dev/null || true; pid=""

python3 -I - "$results" <<'PY'
import glob, json, os, sys
folder = sys.argv[1]
cold = json.load(open(os.path.join(folder, "cold.json")))["runs"][0]
warm = [run for path in sorted(glob.glob(os.path.join(folder, "round-*.json"))) for run in json.load(open(path))["runs"]]
print(f"{'timing':<16}{'cold':>8}{'median':>9}{'p95':>8}{'min':>8}{'opens':>7}")
for key in ["modelReady", "fieldInWindow", "focused", "frameCommitted"]:
    values = sorted(run[key] for run in warm if key in run)
    if not values:
        print(f"{key:<16}{'-':>8}"); continue
    p95 = values[min(len(values) - 1, max(0, int(len(values) * 0.95 + 0.999) - 1))]
    print(f"{key:<16}{cold.get(key, float('nan')):>8.1f}{values[len(values) // 2]:>9.1f}{p95:>8.1f}{values[0]:>8.1f}{len(values):>7}")
PY
rm -rf -- "${results:?}"
[[ "$("${harness[@]}" frontmost)" == "$front_before" ]] || { print -u2 "The app in front changed during the run"; exit 1; }
