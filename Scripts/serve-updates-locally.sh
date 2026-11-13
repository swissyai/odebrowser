#!/bin/zsh
set -euo pipefail

# Serves a release's update feed on this Mac only, so an installed Ode can be
# updated from it before anything is published. It binds to 127.0.0.1, never
# uploads anything, and leaves the release folder as it is: the feed it
# serves is a signed copy whose downloads point at this server.
#
# Usage: Scripts/serve-updates-locally.sh [--port PORT] [--ed-key-file FILE] /absolute/release/output
#
# The release folder is what Scripts/release-ode.sh wrote (or its updates/
# folder). The copy of the feed is signed with the same EdDSA key as the
# release, read from the Keychain like generate_appcast reads it, or from
# --ed-key-file. Ode accepts the feed only with that key's signature, and an
# update only when its version is newer than the running one, both as a build
# number and as a marketing version.
#
# The script prints the command that points the installed Ode at this feed
# and the command that undoes it. It runs neither: changing the installed
# app's preferences is the person's decision.
#
# Environment:
#   ODE_SPARKLE_BIN   folder holding Sparkle's sign_update (found in
#                     DerivedData when unset)

port=8787
key_file=""
while [[ $# -gt 1 ]]; do
  case "$1" in
    --port) port="$2"; shift 2 ;;
    --ed-key-file) key_file="$2"; shift 2 ;;
    *) break ;;
  esac
done
if [[ $# -ne 1 || "$1" != /* ]]; then
  print -u2 "Usage: $0 [--port PORT] [--ed-key-file FILE] /absolute/release/output"
  exit 64
fi
[[ "$port" =~ '^[0-9]+$' ]] && (( port > 1023 && port < 65536 )) || { print -u2 "Invalid port: $port"; exit 64; }
updates="$1"
[[ -f "$updates/appcast.xml" ]] || updates="$1/updates"
[[ -f "$updates/appcast.xml" ]] || { print -u2 "No appcast.xml in $1 or $1/updates."; exit 1; }
[[ -z "$key_file" || -f "$key_file" ]] || { print -u2 "No key file at $key_file."; exit 1; }

repository_root="${0:A:h:h}"
sparkle_bin="${ODE_SPARKLE_BIN:-}"
if [[ -z "$sparkle_bin" ]]; then
  for candidate in "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin(N); do
    if [[ -x "$candidate/sign_update" ]]; then sparkle_bin="$candidate"; break; fi
  done
fi
[[ -x "$sparkle_bin/sign_update" ]] || { print -u2 "Sparkle's sign_update was not found; set ODE_SPARKLE_BIN."; exit 1; }
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 "Port $port is in use; pass --port."
  exit 1
fi

served="$(mktemp -d "${TMPDIR%/}/ode-local-updates.XXXXXX")"
# The served copy holds links and a rewritten feed this script made; nothing
# from the release folder is ever removed.
cleanup() { rm -rf -- "${served:?}"; }
trap cleanup EXIT INT TERM HUP
feed_root="$served/feed"
prefix="http://127.0.0.1:$port/"

python3 -I "$repository_root/Scripts/control-plane/update-feed.py" localize "$updates" "$feed_root" "$prefix"
sign=("$sparkle_bin/sign_update")
[[ -n "$key_file" ]] && sign+=(--ed-key-file "$key_file")
"${sign[@]}" "$feed_root/appcast.xml"

print
# Reads the installed app's Info.plist only, to say which items it would take.
python3 -I "$repository_root/Scripts/control-plane/update-feed.py" describe "$feed_root/appcast.xml" \
  /Applications/Ode.app/Contents/Info.plist
print
print "Point the installed Ode at this feed (it reads the setting at its next check):"
print "  defaults write com.odebrowser.ode SUFeedURL ${prefix}appcast.xml"
print "Then choose Check for Updates… in Ode. It downloads the update, and installs it when you"
print "restart or quit. Undo when done, before stopping this server:"
print "  defaults delete com.odebrowser.ode SUFeedURL"
print
print "Serving $updates at $prefix until you press Control-C."
python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$feed_root"
