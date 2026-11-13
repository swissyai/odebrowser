# Third-party notices

Ode is built on Crest (see [NOTICE](NOTICE)) and ships these third-party runtime components:

| Component | Version | Use | License |
| --- | --- | --- | --- |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.5 | Signed software updates on macOS | MIT-style license with bundled BSD, MIT, and zlib-style notices |
| [.NET runtime](https://github.com/dotnet/runtime) (Native AOT) | 10.0.14 | Ode's core, compiled ahead of time into every app | MIT, with bundled third-party notices |
| [adblock-rust](https://github.com/brave/adblock-rust), Brave's ad-block engine | 0.13.5 | Ode's content filter, compiled into the core | MPL-2.0, built from MIT, Apache-2.0, Unicode-3.0 and Unlicense Rust crates |
| [Chromium](https://www.chromium.org/), with patches, some adapted from [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium) | 156.0.8078.80 | The Chromium engine in Ode's Chromium build for macOS | BSD-3-Clause, with bundled third-party licenses |
| [Mozilla Readability](https://github.com/mozilla/readability) | 0.6.0 | Finds a page's main content when an agent reads it as Markdown on macOS | Apache-2.0 |
| [Turndown](https://github.com/mixmark-io/turndown) | 7.2.4 | Turns that content into Markdown | MIT |

The complete notices are preserved in
[`ThirdParty/Sparkle-LICENSE.txt`](ThirdParty/Sparkle-LICENSE.txt),
[`ThirdParty/DotNet-LICENSE.txt`](ThirdParty/DotNet-LICENSE.txt),
[`ThirdParty/Chromium-LICENSE.txt`](ThirdParty/Chromium-LICENSE.txt),
[`ThirdParty/ContentFilter-LICENSES.txt`](ThirdParty/ContentFilter-LICENSES.txt),
[`ThirdParty/Readability-LICENSE.txt`](ThirdParty/Readability-LICENSE.txt) and
[`ThirdParty/Turndown-LICENSE.txt`](ThirdParty/Turndown-LICENSE.txt).
Readability and Turndown are bundled unmodified, as `Readability.js` and
`turndown.browser.umd.js` in the macOS app's resources. The content filter's
notices cover adblock-rust and every Rust crate its lock file resolves, and the
license audit keeps that list in step with the lock.
Chromium includes many third-party components under their own licenses; the
Chromium build lists every one of them, with its license text, at
`chrome://credits`.

Ode's content filter downloads, as data and at runtime, the scriptlets and
redirect resources of [uBlock Origin](https://github.com/gorhill/uBlock), which
are licensed under the GNU General Public License v3.0. They are converted from
the uBlock Origin release `Scripts/control-plane/ublock-resources` pins and
published as a GitHub release with uBlock Origin's license; they are not
compiled into or shipped with Ode. Filter lists are downloaded the same way,
from their maintainers, under their own licenses.

Ode's emoji picker catalog is generated from the official
[Unicode Emoji 17.0 test data](https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt).
The icon picker's emoji keywords are generated from the English
[Unicode CLDR 48.2 annotations](https://github.com/unicode-org/cldr-json/tree/48.2.0/cldr-json/cldr-annotations-full)
by `Scripts/generate-emoji-keywords.py`. The Unicode data notice, which covers both, is preserved in
[`ThirdParty/Unicode-LICENSE.txt`](ThirdParty/Unicode-LICENSE.txt).

The Space identity editor's catalog of SF Symbol names,
`OdeShared/Resources/SFSymbolNames.txt`, is the symbol name list from
[SFSafeSymbols](https://github.com/SFSafeSymbols/SFSafeSymbols) at revision
`cb2e670a213ff42ae08528ee2c401bfb1d799675`, under the MIT license. Only the
names are included; the symbol artwork comes from the operating system. The
license is preserved in
[`OdeShared/Resources/SFSymbolCatalog-LICENSE.txt`](OdeShared/Resources/SFSymbolCatalog-LICENSE.txt).

The apps bundle the [EasyList](https://easylist.to/easylist/easylist.txt) and
[EasyPrivacy](https://easylist.to/easylist/easyprivacy.txt) filter lists
unmodified, and download newer versions of the same lists from easylist.to.
The lists are data: the app converts them to WebKit content rules on the
device. EasyList offers them under GPL-3.0-or-later or CC BY-SA 3.0 or later;
Ode uses them under CC BY-SA 3.0. Attribution: The EasyList authors,
<https://easylist.to/>. The licence statement is preserved in
[`ThirdParty/EasyList-LICENSE.txt`](ThirdParty/EasyList-LICENSE.txt).

Beyond these, the apps link only Apple platform frameworks supplied by the macOS
and iOS SDKs: AuthenticationServices, CloudKit, LocalAuthentication, Security,
SwiftUI, and WebKit.

## Development and release tooling

Ode's source tree is generated with MIT-licensed
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The optional dead-code audit
uses MIT-licensed [Periphery](https://github.com/peripheryapp/periphery). The
content filter is compiled with the MIT- and Apache-2.0-licensed
[Rust](https://www.rust-lang.org/) toolchain its crate pins; contributors and
release builds download the prebuilt library instead, and need the toolchain
only when the crate's sources differ from its published lock. These tools are
not linked into or redistributed with Ode.

The GitHub workflows use pinned MIT-licensed actions from `actions/*`:
`actions/checkout`, `actions/setup-dotnet` for the core and `actions/setup-node`
for the Help Center. The license audit keeps the exact workflow-action
repository inventory synchronized with `Config/ThirdPartyDependencies.json`.

## Help Center toolchain

The Help Center is built with Docusaurus 3.10.2, React 19.2.8, React DOM
19.2.8, MDX React 3.1.1, clsx 2.1.1, and prism-react-renderer 2.4.1. These direct
dependencies are MIT-licensed. Their exact transitive dependency versions and
declared licenses are recorded in `HelpCenter/package-lock.json`.

The build graph also includes the CC BY 4.0 `caniuse-lite` browser-support
dataset. It is used by the documentation build toolchain and is not linked into
the Ode application. Attribution: caniuse-lite contributors,
<https://github.com/browserslist/caniuse-lite>.

`eval` 0.1.8, `format` 0.2.2, and `require-like` 0.1.2 omit a machine-readable
license field in their package metadata; their distributed license files or
project documentation identify the MIT license. The repository license audit
records those exceptions explicitly.

## Logos and marks

The example-site logos in the Getting Started window, the search-provider
marks and the engine logos identify the sites, providers and engines they
belong to, and nothing else. Their sources and terms are recorded in
[`Documentation/GettingStartedLogos.md`](Documentation/GettingStartedLogos.md),
[`Documentation/SearchProviderLogos.md`](Documentation/SearchProviderLogos.md)
and [`Documentation/EngineLogos.md`](Documentation/EngineLogos.md).
Third-party names and logos remain the property of their respective owners.
