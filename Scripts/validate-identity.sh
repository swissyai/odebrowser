#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

required_paths=(
  OdeShared
  OdeMac
  OdeMobile
  OdeTests
  OdeMobileTests
  OdeTestFixtures
  Documentation/ARCHITECTURE.md
  OdeShared/Resources/OdeIcon/Ode.icon
  project.yml
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    print -u2 "Missing required path: $required_path"
    exit 1
  fi
done

prototype_root="Bro""wser"
prototype_tests="${prototype_root}Tests"
prototype_ui_tests="${prototype_root}UITests"
prototype_project="${prototype_root}.xcodeproj"

if [[ -e "$prototype_root" || -e "$prototype_tests" || -e "$prototype_ui_tests" || -e "$prototype_project" ]]; then
  print -u2 "A prototype-named top-level project path still exists."
  exit 1
fi

prototype_product="cae""lura"
prototype_bundle="com.pauldavis.${prototype_root:l}"
prototype_environment="${prototype_root:u}_"
prototype_import="@testable import ${prototype_root}"

if rg -n -i \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  "${prototype_product}|${prototype_bundle}|${prototype_project}|${prototype_import}" \
  .; then
  print -u2 "Prototype product identity remains in the repository."
  exit 1
fi

if rg -n \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  "(^|[^[:alnum:]_])${prototype_environment}" \
  .; then
  print -u2 "Prototype launch environment remains in the repository."
  exit 1
fi

rg -q '^name: Ode$' project.yml
rg -q '^  Ode:$' project.yml
rg -q '^  OdeMobile:$' project.yml
rg -q 'ODE_MAC_BUNDLE_IDENTIFIER: com\.odebrowser\.ode$' project.yml
rg -q 'ODE_MOBILE_BUNDLE_IDENTIFIER: com\.odebrowser\.ode$' project.yml
# Debug, test and harness builds keep a development identity of their own.
rg -q 'ODE_BUNDLE_IDENTIFIER_PREFIX: com\.odebrowser\.ode\.dev$' project.yml
rg -q 'ODE_MAC_BUNDLE_IDENTIFIER: com\.odebrowser\.ode\.dev$' project.yml
rg -q 'ODE_MOBILE_BUNDLE_IDENTIFIER: com\.odebrowser\.ode\.dev$' project.yml
rg -q 'PRODUCT_MODULE_NAME: Ode$' project.yml
rg -q 'PRODUCT_MODULE_NAME: OdeMobile$' project.yml

upstream_identity_paths=(
  project.yml
  OdeMac/Configuration/Ode.entitlements
  OdeMobile/Configuration/OdeMobile.entitlements
  OdeMac/Configuration/Ode-Info.plist
  OdeShared/Application/ProductIdentity.swift
)

# The fork must not keep the upstream identifiers or trust the upstream
# update signing key (its public key value). rg exits 1 only when every file was read and none matched.
upstream_identity_status=0
rg -n 'com\.pauldavis|iCloud\.com\.pauldavis|x/dBoNAjtYIa\+JKUUHY48NYepidnElHTo3w2VMyqzLA=' "${upstream_identity_paths[@]}" \
  || upstream_identity_status=$?
if (( upstream_identity_status != 1 )); then
  print -u2 "Upstream product identity or update signing key remains."
  exit 1
fi

# Upstream's team and bundle identifiers may remain only in the prebuilt
# engine's inputs under CrestEngines/, in the tools that look for them, and
# as the export format id, which keeps Crest and Ode exports interchangeable.
upstream_identifiers="$(rg -n '3U2R97HLXF|com\.pauldavis\.crest' . \
  --glob '!CrestEngines/**' \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!tools/dev/rename-identifiers.py' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  | grep -v 'com\.pauldavis\.crest\.browser-data' || true)"
if [[ -n "$upstream_identifiers" ]]; then
  print -u2 "$upstream_identifiers"
  print -u2 "Upstream team or bundle identifiers remain outside the prebuilt engine's inputs."
  exit 1
fi

# Every string people and agents see names the product, and the app never
# sends anyone to the base product's sites. The rename tool lists anything
# it would still change; a merge from upstream reintroduces such strings.
if ! python3 -I tools/dev/rename-product-strings.py --check > /dev/null; then
  python3 -I tools/dev/rename-product-strings.py --check | tail -20 >&2
  print -u2 "Visible strings still name Crest; run tools/dev/rename-product-strings.py."
  exit 1
fi
if grep -rqw 'Crest' HelpCenter/docs HelpCenter/docusaurus.config.js HelpCenter/sidebars.js HelpCenter/src; then
  grep -rnw 'Crest' HelpCenter/docs HelpCenter/docusaurus.config.js HelpCenter/sidebars.js HelpCenter/src | head -10 >&2
  print -u2 "The Help Center still names Crest."
  exit 1
fi
if ! python3 -I tools/dev/check-docs-product-name.py > /dev/null; then
  python3 -I tools/dev/check-docs-product-name.py >&2 || true
  print -u2 "Developer documentation still names Crest in prose."
  exit 1
fi
if ! python3 -I tools/dev/check-ui-labels.py > /dev/null 2>&1; then
  python3 -I tools/dev/check-ui-labels.py >&2 || true
  print -u2 "The UI styles text as micro labels; use sentence case without letter spacing."
  exit 1
fi
if ! python3 -I tools/dev/check-corner-radii.py > /dev/null 2>&1; then
  python3 -I tools/dev/check-corner-radii.py >&2 || true
  print -u2 "The UI sets corners outside Ode's corner scale; use OdeCornerScale and continuous corners."
  exit 1
fi
# One link may stay: the core downloads its content filter's scriptlet
# resources from the base product's published release until Ode publishes its
# own (Documentation/Distribution.md, "Prebuilt Chromium engine").
scriptlet_resources_line='^OdeCore/src/OdeCore/Application/ContentBlocking/FilterLibrary\.cs:[0-9]+: +"https://github\.com/pauljoda/Crest/releases/download/" \+ ResourcesRelease \+ "/ublock-resources\.json";$'
upstream_links="$(rg -n 'github\.com/pauljoda|raw\.githubusercontent\.com/pauljoda|crestbrowser\.com|reddit\.com/r/CrestBrowser|apps\.apple\.com/[a-z/]*crest' \
  OdeMac OdeShared OdeMobile OdeAgentHelper OdeAgents CrestEngines/Chromium/Apple OdeCore/src \
  --glob '!**/Generated/**' | grep -E -v "$scriptlet_resources_line" || true)"
if [[ -n "$upstream_links" ]]; then
  print -u2 "$upstream_links"
  print -u2 "The app still links to the base product's sites."
  exit 1
fi

print "Ode identity validation passed."
