#!/bin/zsh
# Lists the functions over CCN 15 or 80 lines in the Swift, C# and Python
# files changed against a base, and fails only on new ones; the functions
# Scripts/complexity-baseline.json records are existing debt. Runs lizard
# through uvx and passes with a note when uvx is not installed.
#
#   Scripts/check-complexity.sh --base main    files changed since main
#   Scripts/check-complexity.sh -- PATH ...    these files
#   Scripts/check-complexity.sh --all          every measured file
#   Scripts/check-complexity.sh --write-baseline
set -euo pipefail

script_repository_root="${0:A:h:h}"
repository_root="${ODE_COMPLEXITY_REPOSITORY_ROOT:-$script_repository_root}"
lizard_version=1.24.0

if [[ -n "${ODE_LIZARD:-}" ]]; then
  lizard_command="$ODE_LIZARD"
elif command -v uvx >/dev/null 2>&1; then
  lizard_command="uvx --quiet lizard==$lizard_version"
else
  print "Complexity was not checked: the check runs lizard $lizard_version through uvx."
  print "Install uv to run it:"
  print "  brew install uv"
  exit 0
fi

exec python3 "$script_repository_root/Scripts/check_complexity.py" \
  --root "$repository_root" --lizard "$lizard_command" "$@"
