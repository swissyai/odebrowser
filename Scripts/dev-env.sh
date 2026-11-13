#!/bin/zsh
# Puts the pinned .NET SDK on PATH when sourced; prints the toolchain it finds
# and the shell commands to build, test and clean up this checkout when run.
#
#   source Scripts/dev-env.sh        put ~/.dotnet on PATH in this shell
#   Scripts/dev-env.sh               toolchain state and commands for this checkout
#   Scripts/dev-env.sh --registered  Ode app copies LaunchServices has registered

if [[ ${zsh_eval_context[-1]} == file ]]; then
  () {
    local directory="${ODE_DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
    if [[ -x "$directory/dotnet" && ":$PATH:" != *":$directory:"* ]]; then
      export PATH="$directory:$PATH"
    fi
  }
  return 0
fi

set -euo pipefail

repository_root="${0:A:h:h}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

case "${1:-}" in
  "") ;;
  --registered)
    # Each record of the dump names its bundle path before its identifier.
    "$lsregister" -dump | awk '
      /^-----/ { path = "" }
      /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
      /^identifier:/ && path ~ /\.app$/ && $2 ~ /^com\.odebrowser\.ode(\.dev.*)?$/ { print $2 "\t" path }
    ' | sort -u | while IFS=$'\t' read -r identifier app_path; do
      if [[ -e "$app_path" ]]; then state=present; else state=missing; fi
      print -r -- "$state  $identifier  $app_path"
    done
    exit 0
    ;;
  *)
    print -u2 "Usage: Scripts/dev-env.sh [--registered]"
    exit 64
    ;;
esac

dotnet_directory="${ODE_DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
sdk_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sdk"]["version"])' "$repository_root/OdeCore/global.json")"
derived_data="${ODE_DERIVED_DATA_PATH:-$repository_root/DerivedData}"
branch="$(git -C "$repository_root" branch --show-current 2>/dev/null || true)"
destination="platform=macOS,arch=arm64"
xcode_arguments="-project Ode.xcodeproj -scheme Ode -destination '$destination' -derivedDataPath $derived_data CODE_SIGNING_ALLOWED=NO"

found() {
  if command -v "$1" >/dev/null 2>&1; then print -r -- "$(command -v "$1")"; else print -r -- "missing ($2)"; fi
}

xcode_version="$(xcodebuild -version 2>/dev/null || true)"
print "Toolchain"
print -r -- "  Xcode:        ${${xcode_version%%$'\n'*}:-missing (install Xcode and select it with xcode-select)}"
print -r -- "  XcodeGen:     $(found xcodegen 'brew install xcodegen')"
print -r -- "  swift-format: $(xcrun --find swift-format 2>/dev/null || print 'missing (ships with Xcode)')"
print -r -- "  ripgrep:      $(found rg 'brew install ripgrep')"
print -r -- "  Python:       $(python3 --version 2>&1)"
if [[ -d "$dotnet_directory/sdk/$sdk_version" ]]; then
  print -r -- "  .NET SDK:     $sdk_version in $dotnet_directory"
else
  print -r -- "  .NET SDK:     $sdk_version missing from $dotnet_directory (Scripts/control-plane/install-dotnet.sh)"
fi
if command -v dotnet >/dev/null 2>&1; then
  print -r -- "  dotnet:       $(command -v dotnet)"
else
  print -r -- "  dotnet:       not on PATH; install-dotnet.sh leaves PATH alone"
fi

print
print ".NET on PATH for running dotnet directly (the scripts that run it find $dotnet_directory themselves)"
print -r -- "  export PATH=\"$dotnet_directory:\$PATH\"    (or: source Scripts/dev-env.sh)"

print
print "Swift tests without opening Xcode; repeat the second step until source or tests change"
print -r -- "  xcodebuild build-for-testing $xcode_arguments"
print -r -- "  xcodebuild test-without-building $xcode_arguments"

print
print "One class or one test, then the whole suites before committing"
print -r -- "  xcodebuild test-without-building $xcode_arguments -only-testing:OdeTests/<TestClass>[/<testMethod>]"
print -r -- "  (cd OdeCore && dotnet test tests/OdeCore.Tests --filter \"FullyQualifiedName~<TestClass>\")"
print -r -- "  python3 -m unittest discover -s Scripts/Tests -p 'test_<name>.py'"

print
print "Every compile error in one build (xcodebuild otherwise stops at the first failing compile)"
print -r -- "  xcodebuild build-for-testing $xcode_arguments -IDEBuildingContinueBuildingAfterErrors=YES 2>&1 | rg ' error: ' | sort -u"

print
print "Cleanup: unregister each built app before deleting it, or it stays registered"
print -r -- "  $lsregister -u $derived_data/Build/Products/Debug/Ode.app"
print -r -- "  rm -rf -- $derived_data"
print -r -- "  Scripts/dev-env.sh --registered"

print
print -r -- "When other checkouts build on this Mac, name logs and result bundles after the branch (${branch:-detached}-build.log) and wait on your own process, not on pgrep -f xcodebuild."
