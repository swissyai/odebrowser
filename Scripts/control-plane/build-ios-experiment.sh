#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ $# -ne 1 || "$1" != /* || "$1" != *.app || -e "$1" ]]; then
    echo "Usage: $0 /absolute/new/path/OdeNativeCore.app" >&2
    exit 2
fi
output_app="$1"
source "$repo_root/Scripts/control-plane/dotnet-path.sh"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/crest-control-plane-ios.XXXXXX")"
# The build root is a private mktemp folder; delete it rather than filling the Trash.
cleanup() { if [[ -d "$build_root" ]]; then rm -rf -- "$build_root"; fi; }
trap cleanup EXIT INT TERM HUP

cd "$repo_root/OdeCore"
dotnet test tests/OdeCore.Tests --nologo
dotnet publish src/OdeCore.Native -c Release -r iossimulator-arm64 \
    -p:PublishAotUsingRuntimePack=true -o "$build_root/core" --nologo
cd "$repo_root"
python3 Scripts/control-plane/package-apple-core.py \
    --library "$build_root/core/OdeCore.Native.dylib" \
    --output "$build_root/frameworks/OdeCoreABI.framework" --platform iphonesimulator
xcodebuild -project Ode.xcodeproj -scheme OdeMobileNativeCore -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_root/DerivedData" \
    ODE_CORE_FRAMEWORK_DIR="$build_root/frameworks" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
mkdir -p "$(dirname "$output_app")"
ditto "$build_root/DerivedData/Build/Products/Debug-iphonesimulator/OdeNativeCore.app" "$output_app"
codesign --verify --deep --strict "$output_app"
echo "Built iOS Simulator app $output_app"
