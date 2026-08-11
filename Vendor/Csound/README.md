# Bundled Csound runtime

The macOS runtime closure is pinned at Csound 6.18.1 and committed under
`Sources/VascularMac/Resources/Runtime`. It contains the framework, the curated
opcode library, `libsndfile`, and the codec libraries required by that build.

Release builds must fail when the embedded runtime is missing and must audit
its loader paths so the application cannot accidentally depend on a system-wide
Csound installation.

The checked-in runtime currently targets Apple Silicon. iOS, Android, and Linux
ARM64 releases require separate platform artifacts and must not reuse these
Mach-O binaries.
