#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
derived_data="${ODE_DERIVED_DATA_PATH:-}"
owns_derived_data=0
if [[ -z "$derived_data" ]]; then
  derived_data="$(mktemp -d /private/tmp/crest-validation.XXXXXX)"
  owns_derived_data=1
else
  mkdir -p "$derived_data"
fi

# Xcode registers the apps it builds with LaunchServices; unregister them
# before deleting the Derived Data this script created.
cleanup() {
  if (( owns_derived_data )) && [[ -n "${derived_data:-}" && -d "$derived_data" ]]; then
    "$repository_root/Scripts/control-plane/unregister-apps.sh" "$derived_data" || true
    find "$derived_data" -depth -delete
  fi
}
trap cleanup EXIT INT TERM HUP

cd "$repository_root"
python3 -m unittest discover -s Scripts/Tests
Scripts/bootstrap.sh

xcodebuild \
  -project Ode.xcodeproj \
  -scheme Ode \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  test

ios_destination="${ODE_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
xcodebuild \
  -project Ode.xcodeproj \
  -scheme OdeMobile \
  -destination "$ios_destination" \
  -derivedDataPath "$derived_data" \
  -only-testing:OdeMobileTests \
  test
