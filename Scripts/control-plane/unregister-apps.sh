#!/bin/zsh
# Unregisters from LaunchServices every app bundle under a folder that is about
# to be deleted, embedded apps such as Sparkle's Updater.app included. Xcode
# registers each app it builds, and the registration outlives the folder, so
# macOS keeps offering links and later launches to a copy that is gone.
# It deletes nothing itself.
#
# Usage: Scripts/control-plane/unregister-apps.sh /absolute/folder
set -euo pipefail

lsregister="${ODE_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

if [[ $# -ne 1 || "$1" != /* ]]; then
  print -u2 "Usage: $0 /absolute/folder"
  exit 64
fi
[[ -d "$1" && -x "$lsregister" ]] || exit 0

for app in "$1"/**/*.app(ND/); do
  "$lsregister" -u "$app" || print -u2 "warning: could not unregister $app"
done
