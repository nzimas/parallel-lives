# Changelog

## Unreleased

- Added track-button + processor-pad parameter randomization while preserving
  opcode family and position
- Protected every processor inside a chain-locked prefix from randomization
- Added one-shot long-press trackpad access and targeted processor replacement
  without rebuilding the downstream graph
- Extended the gesture to unlocked generators while preserving synthesis family,
  harmonic fundamental, and the existing processor chain
- Added compact readable generator and processor names to active macOS matrix pads

## 2026.8.11

- Adopted calendar versioning to reflect ParallelLives as stable software rather
  than an early pre-1.0 prototype
- Consolidates the complete trackpad control surface, immediate physical-model
  onsets, bundled Csound runtime, project and scene handling, locks, mixer, and
  parameterized shared effects
- Supersedes the earlier `0.1.x` release labels; those tags remain as historical
  records only

## 0.1.2 — 2026-08-11

- Guaranteed an immediate onset excitation for sparse stochastic, Karplus–Strong,
  and struck physical-model sources
- Preserved each model's irregular clock after the one-time onset
- Reduced terminal warm-up for newly created tracks from 260 ms to 20 ms while
  retaining the longer click-safe handoff for chain edits
- Added physical-source onset regression measurements to the transition audit

## 0.1.1 — 2026-08-11

- Added the complete trackpad-operated control surface
- Added aligned top-row project, effects, scene, and latching Shift buttons
- Added coloured right-side track buttons for all eight track editors
- Routed software and Launchpad gestures through the same track and lock logic
- Improved responsive sizing so status and safety controls remain reachable
- Documented every standalone trackpad gesture

## 0.1.0 — 2026-08-11

Initial public macOS release.

- Eight parallel generator/processor tracks on an 8×8 matrix
- Bundled Csound 6.18.1 runtime
- Twenty synthesis archetypes and fifteen processor families
- Generator and chain-prefix locking
- Harmonic anchoring across tracks
- Track mixer, random rhythmic gate, and four shared-effect sends
- Thirty-two-position Launchpad faders
- Track scenes, global scenes, and persistent projects
- Parameterized reverb, delay, saturation/overdrive, and decimation returns
- Click-safe graph transitions and persistent ambient tails
- Novation Launchpad Mini Mk3 Programmer-mode integration
