#!/bin/zsh
set -euo pipefail

# Builds Ode for direct distribution without anyone at the keyboard: fetches
# the Developer ID provisioning profile through the App Store Connect API
# (registering the bundle identifier and creating the profile on first use),
# packages the Chromium product with that profile, notarizes and staples the
# app and its disk image, and writes a signed Sparkle appcast. It uploads and
# publishes nothing; the output folder is handed to whoever publishes.
#
# A release on the published feed checks for, downloads and installs updates
# automatically, so fixes reach people who never ask. Stable releases reach
# everyone over 7 days in Sparkle's phased groups; a release that fixes a
# crash at launch is critical and skips the phasing for every older version.
#
# The feed keeps the newest releases, ODE_FEED_VERSIONS of them (5, about a
# month of weekly releases), with their disk images, so Ode can offer to go
# back to an earlier version. Each release starts from the previous one's
# updates folder (ODE_PREVIOUS_UPDATES) and adds itself; Sparkle's
# generate_appcast drops the oldest item and moves its disk image to
# updates/old_updates/, which is not published.
#
# Pulling a bad release: remove its <item> from appcast.xml and its disk image
# from updates/, publish the next build with ODE_CRITICAL_UPDATE=1, and never
# leave the bad build downloadable. A phased rollout halts the same way:
# publishing the appcast without the item stops every group that has not
# installed it yet. The next release then carries the feed without it.
#
# Usage: Scripts/release-ode.sh [--check] <absolute output folder>
#
# Environment:
#   ODE_ASC_KEY_ID      App Store Connect API key id (required; Admin or App
#                       Manager role, so it may register the bundle identifier)
#   ODE_ASC_ISSUER_ID   App Store Connect issuer id (required for a team key)
#   ODE_ASC_KEY_PATH    the key's .p8 file (default ~/.appstoreconnect/AuthKey.p8)
#   ODE_BUILD_NUMBER    CFBundleVersion (default: UTC date and time, YYYYMMDDHHMM)
#   ODE_CHROMIUM_APP    a Chromium.app to package instead of the published engine
#   ODE_SPARKLE_BIN     folder holding Sparkle's generate_appcast
#   ODE_DMGBUILD        dmgbuild executable; when set, the disk image gets the
#                       themed window from Scripts/disk-image (otherwise a plain
#                       hdiutil image)
#   ODE_PHASED_ROLLOUT_INTERVAL  seconds between Sparkle's seven rollout groups
#                       (default 86400, a week in all; 0 releases to everyone)
#   ODE_CRITICAL_UPDATE set to 1 for a release that fixes a crash at launch:
#                       critical for every older version, never phased
#   ODE_PRIVATE_RELEASE set to 1 to turn automatic updates off, for a build that
#                       is not on the published feed
#   ODE_SECURITY_ONLY   set to 1 for a release with security fixes only, which
#                       Ode's update card says can wait for a convenient restart
#   ODE_PREVIOUS_UPDATES the previous release's updates folder (its appcast.xml
#                       and disk images), carried into this release's feed;
#                       without it the feed holds this release alone
#   ODE_FEED_VERSIONS   how many releases the feed keeps (default 5)
#
# --check checks local prerequisites only, not publication, packaged runtime or security freshness.

repository_root="${0:A:h:h}"
cd "$repository_root"

team_id="WUMLCL8SAZ"
bundle_identifier="com.odebrowser.ode"
entitlements_source="OdeMac/Configuration/Ode-Direct.entitlements"
engine_repository="pauljoda/Crest"
feed_prefix="https://odebrowser.com/updates/"

check_only=false
if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi
if [[ $# -ne 1 || "$1" != /* ]]; then
  print -u2 "Usage: $0 [--check] <absolute output folder>"
  exit 64
fi
output="$1"

problems=()
need() { problems+=("$1"); }

identity_hash="$(security find-identity -v -p codesigning \
  | awk "/Developer ID Application: .*\\(${team_id}\\)/ { print \$2; exit }")"
[[ -n "$identity_hash" ]] || need "No Developer ID Application identity for team $team_id in the keychain."

key_path="${ODE_ASC_KEY_PATH:-$HOME/.appstoreconnect/AuthKey.p8}"
[[ -f "$key_path" ]] || need "No App Store Connect API key at $key_path."
[[ -n "${ODE_ASC_KEY_ID:-}" ]] || need "Set ODE_ASC_KEY_ID to the key's id (App Store Connect > Users and Access > Integrations)."
[[ -n "${ODE_ASC_ISSUER_ID:-}" ]] || need "Set ODE_ASC_ISSUER_ID to the issuer id shown above the team keys."

dotnet=""
for candidate in "$(command -v dotnet || true)" "$HOME/.dotnet/dotnet" /usr/local/share/dotnet/dotnet; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then dotnet="$candidate"; break; fi
done
[[ -n "$dotnet" ]] || need "Install the .NET SDK named in OdeCore/global.json."

for tool in xcodebuild hdiutil ditto; do
  command -v "$tool" >/dev/null || need "Install $tool."
done
xcrun --find notarytool >/dev/null 2>&1 || need "Xcode's notarytool is missing."
xcrun --find stapler >/dev/null 2>&1 || need "Xcode's stapler is missing."

derived_data="${ODE_RELEASE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Ode-Release}"
feed_versions="${ODE_FEED_VERSIONS:-5}"
[[ "$feed_versions" =~ '^[1-9][0-9]*$' ]] || need "ODE_FEED_VERSIONS must be a positive number: $feed_versions"
if [[ -n "${ODE_PREVIOUS_UPDATES:-}" ]]; then
  [[ "$ODE_PREVIOUS_UPDATES" == /* && -f "$ODE_PREVIOUS_UPDATES/appcast.xml" ]] \
    || need "ODE_PREVIOUS_UPDATES must be an absolute folder holding the previous appcast.xml: $ODE_PREVIOUS_UPDATES"
fi
if [[ -n "${ODE_DMGBUILD:-}" ]]; then
  [[ -x "$ODE_DMGBUILD" ]] || need "ODE_DMGBUILD is not an executable: $ODE_DMGBUILD"
  [[ -f Scripts/disk-image/settings.py && -f Scripts/disk-image/background.tiff ]] || need "Scripts/disk-image is incomplete."
fi
sparkle_bin="${ODE_SPARKLE_BIN:-}"
if [[ -z "$sparkle_bin" ]]; then
  for candidate in "$derived_data"/SourcePackages/artifacts/sparkle/Sparkle/bin \
    "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin(N); do
    if [[ -x "$candidate/generate_appcast" ]]; then sparkle_bin="$candidate"; break; fi
  done
fi
if [[ -z "$sparkle_bin" ]]; then
  # Resolving the package downloads Sparkle's tools beside its framework.
  print "Sparkle's tools are not resolved yet; the build resolves them."
fi

engine_app="${ODE_CHROMIUM_APP:-}"
if [[ -z "$engine_app" ]]; then
  engine_tag="$(python3 Scripts/control-plane/chromium_engine.py tag)"
  engine_asset="$(python3 Scripts/control-plane/chromium_engine.py asset)"
  engine_cache="$HOME/Library/Caches/Ode-release/$engine_tag"
  engine_app="$engine_cache/Chromium.app"
  if [[ ! -d "$engine_app" ]]; then
    command -v gh >/dev/null || need "Install the GitHub CLI to download $engine_tag, or set ODE_CHROMIUM_APP."
  fi
elif [[ ! -f "$engine_app/Contents/Info.plist" ]]; then
  need "No Chromium.app at $engine_app."
fi

if (( ${#problems} )); then
  print -u2 "Ode cannot be released yet:"
  for problem in "${problems[@]}"; do print -u2 "  - $problem"; done
  exit 1
fi
if [[ "$check_only" == true ]]; then
  print "Local release prerequisites are in place. This is not release readiness."
  print "Inspect keyed publication separately: python3 Scripts/release-preflight.py --online"
  print "Packaged runtime, signatures, managed grants, security freshness and install/update/rollback remain separate gates."
  exit 0
fi

[[ ! -e "$output" ]] || { print -u2 "The output folder must not exist yet: $output"; exit 1; }
build_number="${ODE_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
[[ "$build_number" =~ '^[0-9]+$' ]] || { print -u2 "Invalid build number: $build_number"; exit 1; }
work="$(mktemp -d "${TMPDIR%/}/ode-release.XXXXXX")"
trap 'find "$work" -depth -delete 2>/dev/null || true' EXIT INT TERM HUP
auth=(-allowProvisioningUpdates
  -authenticationKeyPath "$key_path"
  -authenticationKeyID "$ODE_ASC_KEY_ID"
  -authenticationKeyIssuerID "$ODE_ASC_ISSUER_ID")
notary=(--key "$key_path" --key-id "$ODE_ASC_KEY_ID" --issuer "$ODE_ASC_ISSUER_ID")

if [[ ! -d "$engine_app" ]]; then
  print "Downloading Chromium engine $engine_tag..."
  gh release download "$engine_tag" --repo "$engine_repository" \
    --pattern "$engine_asset" --pattern "${engine_asset}.sha256" --dir "$work/engine"
  (cd "$work/engine" && shasum -a 256 -c "${engine_asset}.sha256")
  ditto -x -k "$work/engine/$engine_asset" "$work/engine/extracted"
  mkdir -p "${engine_cache:h}"
  mv "$work/engine/extracted" "$engine_cache"
fi

print "Fetching the Developer ID provisioning profile..."
# Registers the bundle identifier and creates the profile on first use; this
# needs an App Store Connect key with the Admin or App Manager role.
python3 -I Scripts/asc-developer-id-profile.py --key-id "$ODE_ASC_KEY_ID" --issuer "$ODE_ASC_ISSUER_ID" \
  --key "$key_path" --bundle-id "$bundle_identifier" --team "$team_id" --output "$work/profile.provisionprofile"
# The direct-distribution entitlements with the team's prefix written out.
sed "s/\$(AppIdentifierPrefix)/${team_id}./" "$entitlements_source" > "$work/entitlements.plist"
plutil -lint "$work/entitlements.plist" >/dev/null

print "Building the native core and the Chromium UI framework..."
(cd OdeCore && "$dotnet" publish src/OdeCore.Native -c Release -r osx-arm64 --nologo -v quiet)
core="$PWD/OdeCore/src/OdeCore.Native/bin/Release/net10.0/osx-arm64/publish/OdeCore.Native.dylib"
xcodebuild build -quiet \
  -project Ode.xcodeproj -scheme CrestChromiumUIProduct -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived_data" \
  CURRENT_PROJECT_VERSION="$build_number" CODE_SIGNING_ALLOWED=NO
ui="$derived_data/Build/Products/Release/CrestChromiumUIProduct.framework"
[[ -d "$ui" ]]

print "Packaging and signing the Chromium product..."
app="$work/product/Ode.app"
mkdir -p "${app:h}"
automatic_updates=(--automatic-updates)
[[ "${ODE_PRIVATE_RELEASE:-}" == 1 ]] && automatic_updates=()
ODE_DEFAULT_UPDATE_CHANNEL=stable python3 Scripts/control-plane/package-chromium-host.py \
  --browser "$engine_app" --product --distribution "${automatic_updates[@]}" \
  --ui "$ui" --core "$core" \
  --entitlements "$work/entitlements.plist" \
  --provisioning-profile "$work/profile.provisionprofile" --without-cloudkit \
  --signing-identity "$identity_hash" \
  --output "$app"
codesign --verify --deep --strict "$app"
[[ "$(defaults read "$app/Contents/Info" CFBundleIdentifier)" == "$bundle_identifier" ]]
[[ "$(defaults read "$app/Contents/Info" CFBundleVersion)" == "$build_number" ]]
version="$(defaults read "$app/Contents/Info" CFBundleShortVersionString)"

print "Notarizing the app..."
ditto -c -k --keepParent "$app" "$work/Ode.zip"
xcrun notarytool submit "$work/Ode.zip" "${notary[@]}" --wait
xcrun stapler staple "$app"
spctl --assess --type execute "$app"

print "Building and notarizing the disk image..."
mkdir -p "$work/image"
ditto "$app" "$work/image/Ode.app"
ln -s /Applications "$work/image/Applications"
mkdir -p "$output/updates"
dmg="$output/updates/Ode-$version-$build_number.dmg"
if [[ -n "${ODE_DMGBUILD:-}" ]]; then
  "$ODE_DMGBUILD" -s Scripts/disk-image/settings.py \
    -D app="$work/image/Ode.app" \
    -D background="$repository_root/Scripts/disk-image/background.tiff" \
    -D volume_icon="$work/image/Ode.app/Contents/Resources/Ode.icns" \
    Ode "$dmg"
else
  hdiutil create -quiet -volname Ode -srcfolder "$work/image" -ov -format UDZO "$dmg"
fi
codesign --force --timestamp --sign "$identity_hash" "$dmg"
xcrun notarytool submit "$dmg" "${notary[@]}" --wait
xcrun stapler staple "$dmg"
ditto "$app" "$output/Ode.app"

if [[ -z "$sparkle_bin" ]]; then
  sparkle_bin="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
fi
if [[ -n "${ODE_PREVIOUS_UPDATES:-}" ]]; then
  print "Carrying the previous feed and its disk images..."
  python3 -I Scripts/control-plane/update-feed.py carry "$ODE_PREVIOUS_UPDATES" "$output/updates"
fi
print "Writing the signed appcast..."
appcast_options=(--download-url-prefix "$feed_prefix" --maximum-versions "$feed_versions")
if [[ "${ODE_CRITICAL_UPDATE:-}" == 1 ]]; then
  # Critical for every older version; Sparkle installs it without phasing.
  appcast_options+=(--critical-update-version "")
else
  rollout_interval="${ODE_PHASED_ROLLOUT_INTERVAL:-86400}"
  [[ "$rollout_interval" =~ '^[0-9]+$' ]] || { print -u2 "Invalid ODE_PHASED_ROLLOUT_INTERVAL: $rollout_interval"; exit 1; }
  (( rollout_interval > 0 )) && appcast_options+=(--phased-rollout-interval "$rollout_interval")
fi
"$sparkle_bin/generate_appcast" "${appcast_options[@]}" "$output/updates"
if [[ "${ODE_SECURITY_ONLY:-}" == 1 ]]; then
  # The mark changes the feed, so it is signed again afterwards.
  python3 -I Scripts/control-plane/mark-security-update.py "$output/updates/appcast.xml" "$build_number"
  "$sparkle_bin/sign_update" "$output/updates/appcast.xml"
fi

# Files the feed no longer names, such as the disk image of the item it
# dropped, move to updates/old_updates/.
python3 -I Scripts/control-plane/update-feed.py prune "$output/updates"

print "Ode $version ($build_number) is ready in $output:"
print "  Ode.app, updates/$(basename "$dmg") and updates/appcast.xml"
print "The feed lists:"
python3 -I Scripts/control-plane/update-feed.py describe "$output/updates/appcast.xml"
print "Publish updates/ without updates/old_updates/. Publishing to odebrowser.com is a separate,"
print "deliberate step; Scripts/serve-updates-locally.sh tests it on this Mac first."
