# ParallelLives 0.1.0

The first public macOS release of ParallelLives, an 8×8 modular
electroacoustic instrument driven by Csound and designed around the Novation
Launchpad Mini Mk3.

## Highlights

- Eight parallel left-to-right synthesis and processing tracks
- Twenty source archetypes, including Karplus–Strong and physical models
- Fifteen animated processor families
- Harmonic anchoring across independently generated tracks
- Exact generator and chain-prefix locking
- Thirty-two-position volume, pan, gate, send, and effect controls
- Track scenes, 32 global scenes per project, and 32 project slots
- Massive decoupled reverb, stereo delay, saturation/overdrive, and decimation
- Self-contained Csound 6.18.1 runtime

## Download

Download `ParallelLives-0.1.0-macOS-arm64.zip`, extract it, and move
`ParallelLives.app` to `/Applications` or `~/Applications`.

Requirements: Apple Silicon and macOS 14 Sonoma or newer.

This release is ad-hoc signed, not Apple-notarized. If Gatekeeper blocks the
first launch, Control-click the app, select **Open**, and confirm once. See the
[User Guide](https://github.com/nzimas/parallel-lives/blob/main/Docs/UserGuide.md)
for controller setup and complete operation.

## Integrity

SHA-256:

```text
bc94284313c785a96d57e2fb1ec107bd9318b808cf44939e0dc730366e4f37bb
```

The archive contains the application and all required Csound libraries; users
do not need Homebrew or a separate Csound installation.
