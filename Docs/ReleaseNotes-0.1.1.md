# ParallelLives 0.1.1

This point release makes the macOS window a complete standalone performance
surface. A Novation Launchpad Mini Mk3 remains fully supported but is no longer
required to reach any current instrument feature.

## New

- Eight top-row controls mirror Projects, Reverb/Delay, Texture,
  Global Scenes, three reserved buttons, and Shift.
- Eight coloured T1–T8 buttons open the corresponding track editors.
- On-screen Shift latches for trackpad use; generator and chain-prefix locks use
  the same operations as the hardware controller.
- The control surface scales as one aligned unit when the window is resized.

## Trackpad essentials

- Click a pad for a short press.
- Hold a pad for about half a second for a long press.
- Long-press a leftmost generator, then click an endpoint to create, trim,
  extend, or clear a track.
- Long-press scene and project slots to save; click occupied slots to load.
- Click Shift, click a generator or current endpoint, then click Shift again.

Csound 6.18.1 and its runtime dependencies remain bundled in the application.
The release is for Apple Silicon Macs running macOS 14 or newer and is ad-hoc
signed pending a Developer ID certificate.
