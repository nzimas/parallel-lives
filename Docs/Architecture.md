# Architecture

ParallelLives has four boundaries:

```text
Trackpad / keyboard / Launchpad
              |
       semantic commands
              v
       VascularCore model
       (pads, tracks, seeds)
              |
       immutable graph plan
              v
       audio-engine adapter
              |
       bundled Csound runtime
```

`VascularCore` retains the prototype's historical internal name and has no
dependency on SwiftUI, CoreMIDI, or Csound. It is the portable contract for
sessions and graph generation. Platform controllers emit commands such as
create, extend, trim, clear, select, and panic. The audio adapter
prepares graphs away from the real-time thread, then submits bounded parameter
messages to Csound.

The macOS host loads the bundled Csound dynamic library in-process. Csound owns
the synthesis graph and renders one `ksmps` block at a time; `AVAudioEngine`
owns the CoreAudio device, its clock, and hardware format conversion. Graph
edits use `csoundInputMessageAsync`, so they neither rebuild the orchestra nor
cross a pipe into a command-line process. On Raspberry Pi the same adapter
boundary can use a native ALSA/JACK host. Neither build may silently resolve
Csound from the host system.

The pinned macOS 6.18.1 runtime is a private closure containing `CsoundLib64`,
its opcode libraries, `libsndfile`, and bundled codec dependencies. Apple system
frameworks and `/usr/lib/libSystem` are the only host-provided runtime
dependencies. The application resolves the framework by absolute bundle URL
and points `OPCODE6DIR64` only at its private opcode directory. No Csound child
process is created.

The live routing graph uses 256 Zak audio buses, not Csound's maximum address
space. Removed nodes return their buses to a delayed free list after their
crossfade tails finish. Once started, the embedded engine and its master-return
instruments remain alive even when the matrix becomes empty, allowing reverb and
delay memory to decay independently of every track graph. Only Panic or
application termination clears that state. Each processor is one Csound voice
that reads its upstream bus directly; there is no redundant routing voice per
cell.

## Transactional graph transitions

Structural edits obey one transition contract. A newly inserted processor first
acts as a bounded dry wire, then morphs toward its processed result over a
family-appropriate interval. RMS matching has an explicit 2.5× ceiling rather
than using unconstrained startup normalization. Sources, processor lifetimes,
and terminal outputs use zero-slope envelopes. Replacement terminals start only
after their paths are alive; obsolete terminals begin their complementary fade
at the same scheduled time, and upstream voices remain available until that fade
has completed. Scene mixer values enter after the replacement path is active and
stale delayed recalls are rejected by a per-track generation counter.

The per-track rhythmic gates run as persistent control instruments rather than
rebuilding the audio graph. Their independent random decisions occur on exact
divisions or multiplications of a shared 90 BPM placeholder clock; project
management will later replace that constant with the project's master tempo.

`Scripts/audit-transitions.py` renders these transactions directly through the
bundled Csound API and rejects clipping, non-finite output, or adjacent-sample
discontinuities above the defined threshold. Its matrix covers every processor
family in insertion and removal directions and full seven-processor scene swaps
across every source family.

Generated graphs bound local feedback and amplitude. Each of the eight tracks
has one generator and up to seven processor cells. Random decisions are made
from a stored seed so a session is repeatable across interfaces.

The first generator locked by the performer establishes a session-level
`HarmonicAnchor`. Later root graphs store a fundamental selected from a compact
just-intonation ratio field and normalized into the 29–220 Hz source register.
That frequency travels with the immutable root identity through extension and
trim operations and is supplied to pitch-selective Csound processors as well as
the source opcode. Timbral seeds therefore remain diverse without creating an
unrelated tuning system on each track.

## Persistent project state

`ProjectState` is a versioned, platform-neutral snapshot of the entire musical
machine. It includes `VascularSession` (and therefore its next random seed), all
eight track controls, global master-return parameters, the complete scene bank,
active scene indicators, and the 32-slot global-scene bank. A
32-slot `ProjectBank` is atomically encoded as JSON under macOS Application
Support. The storage adapter remains outside `VascularCore`, allowing iOS and
Raspberry Pi hosts to supply their own durable filesystem location without
changing the archive format.

Project recall submits one whole graph synchronization, waits for replacement
terminals to become live, and then restores all mixer and gate controls through
their existing de-zippered channels. A generation token rejects stale delayed
parameter recalls when projects are selected rapidly.

`GlobalSceneState` is the non-recursive playable subset of project state. Global
scene recall uses the same graph transaction and delayed, generation-guarded
parameter restoration as project recall, preserving graph crossfades and
de-zippering while rejecting stale rapid recalls.

`TrackChainLock` is an immutable snapshot of one complete linear prefix plus the
`GeneratorLock` to which it belongs. The endpoint coordinate is stored alongside
the exact `VesselGraph` segments so clearing the live graph does not alter the
snapshot. Recall reuses those identities verbatim; if the requested endpoint is
farther right, only the additional suffix is generated from a new seed. Session,
scene, and project coders preserve chain locks, while legacy archives decode with
an empty lock map.

The Reverb/Delay editor writes eight normalized macros to persistent Csound
control channels. Reverb maps Size, Decay, Tone, and Motion onto four
decorrelated modulated pre-diffusion paths, a primary stereo tank, a cascaded
bloom tank, damping, and stereo-space behavior. Its nonlinear Decay mapping
approaches 0.997/0.999 feedback only at the maximum setting. Delay maps Time,
Feedback, Tone, and Width onto two continuously variable delay lines. All macros
use de-zippering ramps, and neither editing nor project recall clears return
memory or reconstructs the orchestra.

The Saturation/Decimation editor follows the same persistent-control contract.
Its saturation return provides smoothed drive, curve, tone, and body stages with
drive compensation. Its crusher quantizes to a variable bit depth after genuine
audio-rate stereo sample-and-hold decimation; independent random clock drift
provides the Jitter macro. A rate-aware reconstruction filter constrains
single-sample discontinuities without disguising the destructive processing.

## Audible graph execution

The generated processor list is executed in order, rather than collapsed into
one generic complexity control. The transformation vocabulary contains
filter-bank decomposition, micro-delay granulation, continuously warped delay,
phase-vocoder freezing, nonlinear waveshaping, partitioned convolution,
resonator banks, ring modulation, diffusion, and bounded feedback.

Each track owns one source and one strictly ordered left-to-right processor path.
Every occupied grid cell after the generator has a private Zak output bus, and
the next cell reads only that upstream bus. Tracks never intersect, branch, or
exchange audio. Extending or trimming a chain replaces its terminal output with
a complementary crossfade while preserving the root synthesis identity and all
retained processor identities.

Root synthesis and processor variation use separate deterministic seeds. The
root seed preserves a coherent spectral identity when a chain changes length,
while new cell seeds alter modulation, processor ordering, spatial placement,
and depth. A saturating master stage prevents out-of-range samples while
listening tests determine practical platform limits.
