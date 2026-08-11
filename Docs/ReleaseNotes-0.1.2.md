# ParallelLives 0.1.2

This release removes long silent waits when creating Karplus–Strong and sparse
physical-model tracks.

- Every sparse model now receives one short, material-specific onset excitation.
- The existing unstable stochastic clock continues to control later retriggers;
  the new onset does not create a repeating rhythm.
- A brand-new track reaches its output after 20 ms instead of waiting through
  the 260 ms graph-edit handoff. Expanding, trimming, and recalling chains retain
  the longer crossfade used for click safety.
- The offline transition audit now fails if a physical source misses its first
  audible window.

Csound 6.18.1 and its dependencies remain bundled. The release supports Apple
Silicon Macs running macOS 14 or newer and is ad-hoc signed pending a Developer
ID certificate.
