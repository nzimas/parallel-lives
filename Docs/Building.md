# Building and Releasing ParallelLives

## Supported build host

- Apple Silicon Mac
- macOS 14 or newer
- Apple Command Line Tools with Swift 6.2
- Bash-compatible shell and Python 3

The Swift package retains the historical product and target names `Vascular`
and `VascularMac`. The packaged executable and application are named
`ParallelLives`.

## Bundled runtime

`Sources/VascularMac/Resources/Runtime` contains the pinned Csound 6.18.1 runtime
closure used by the release. Do not replace individual libraries independently:
the framework, opcode library, `libsndfile`, codecs, loader paths, and notices are
validated as one unit.

No build or release may silently link against a Homebrew or system Csound.

## Debug build

```sh
swift build
.build/debug/VascularCoreChecks
```

Run the executable directly only for development:

```sh
swift run Vascular
```

## Application bundle

```sh
Scripts/build-macos-app.sh release
```

This creates `dist/ParallelLives.app`, copies the SwiftPM resource bundle, embeds
the complete Csound closure, applies an ad-hoc signature, and verifies the bundle.

## Required verification

```sh
.build/release/VascularCoreChecks
python3 Scripts/audit-transitions.py
Scripts/audit-csound-runtime.sh dist/ParallelLives.app
codesign --verify --deep --strict --verbose=2 dist/ParallelLives.app
```

The transition audit renders every source family and processor family through
the embedded Csound API. It rejects non-finite output, clipping, unsafe adjacent
sample jumps, silent source families, and truncated return tails.

## Create the downloadable archive

```sh
mkdir -p dist/releases
ditto -c -k --sequesterRsrc --keepParent \
  dist/ParallelLives.app \
  dist/releases/ParallelLives-0.1.0-macOS-arm64.zip
shasum -a 256 dist/releases/ParallelLives-0.1.0-macOS-arm64.zip
```

The ZIP, not the bare directory, is uploaded as the GitHub release asset. After
extraction, users receive the normal `ParallelLives.app` bundle.

## Signing and notarization

The current machine has no Developer ID Application identity, so local builds
are ad-hoc signed. For warning-free public distribution:

1. Install a valid Developer ID Application certificate in the build keychain.
2. Sign nested libraries, the executable, and the app with hardened runtime.
3. Submit the ZIP or DMG with `notarytool`.
4. Staple the notarization ticket to the app.
5. Re-run Gatekeeper assessment and code-signature verification.

Do not claim a release is notarized unless `spctl` and `stapler validate` succeed
on the final artifact.

## Versioning

The public version is set in `Packaging/Info.plist` through
`CFBundleShortVersionString` and `CFBundleVersion`. Release tags use `vX.Y.Z`.
Project archive format versions are independent and live in
`ProjectState.currentFormatVersion`.

## Third-party compliance

Keep `ThirdPartyNotices/Csound-6.18.1-License.rtf` and the matching notice inside
the app resources. Any runtime upgrade requires a new dependency audit and
updated notices before publication.
