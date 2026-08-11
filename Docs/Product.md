# ParallelLives product definition

## Instrument premise

ParallelLives is played by building parallel modular tracks across a matrix rather than by selecting
notes. Every row is an independent modular track containing one generator and
an ordered left-to-right chain of processors. The musical target is variation
in texture, spectrum, density, and spatial behavior rather than melody.

## Primary gesture

1. Hold the leftmost pad of a track and select a pad to its right.
2. The leftmost pad creates one seeded generator for that track.
3. Every traversed pad to its right creates one ordered processor stage.
4. Repeating the gesture at the current endpoint clears the track; choosing a
   nearer or farther endpoint trims or extends it.
5. The eight tracks remain parallel and never intersect or exchange audio.

The top-right button above the Launchpad matrix (programmer address 98) is
Shift. Holding Shift and pressing a track's leftmost pad toggles a generator
assignment. A locked assignment stores the source family and source seed, not
the processor chain. Clearing the track therefore removes all visible and
audible output, while the next chain on that row restores the identical generator
with a newly generated processor sequence.

Holding Shift and pressing the track's current endpoint creates the complementary
chain lock. It snapshots every processor from the generator through that endpoint,
including identity, family, seed, intensity, modulation parameters, and order.
Both left and right locks are required for exact recall. After clearing a track,
recreating it at the locked endpoint restores that chain exactly; selecting a pad
farther right restores the exact prefix and generates new processors afterward.
Shift-pressing a farther current endpoint moves the lock. Repeating the gesture
on an unchanged locked endpoint unlocks it, and unlocking the generator clears
its dependent chain lock.

A dim variation of the track colour marks every locked cell, including while the
audible chain is absent. The locked endpoint bears a lock indicator and turns
white while Shift is held. This trail remains distinguishable from any unlocked
processors added to its right.

The first generator assignment also establishes the session's harmonic anchor.
Every generator created afterward receives a deterministic octave-normalized
just-intonation relationship to that fundamental. Source families retain their
independent timbral and temporal behavior, but pitched oscillators, physical
models, resonant noise bands, resonator processors, ring modulation, phasing,
and flanging all derive their frequency-bearing parameters from the track's
assigned fundamental. This harmonic field remains stable if its visible track
is cleared or its generator assignment is later removed.

The macOS prototype uses a trackpad and keyboard. The performance interface is
a Novation Launchpad Mk3. Controller input is translated to the same semantic
commands as trackpad input; it does not contain audio or graph logic.

The currently connected controller is a Launchpad Mini MK3. ParallelLives selects
its non-DAW `LPMiniMK3 MIDI` port pair, enters Programmer mode over SysEx, and
owns the full 8×8 LED surface while connected. Idle cells, awakened sources,
chain routes and selected endpoints receive distinct palette colours. Holding
Shift reveals stored generator assignments in white; a cleared track otherwise
looks fully empty.

## Projects

A short press on the top-left button above the matrix (Programmer address 91)
toggles the project view. The lower four physical rows provide 32 persistent
project slots, ordered from the bottom-left: notes 11–18 are projects 1–8,
21–28 are 9–16, 31–38 are 17–24, and 41–48 are 25–32. The upper four rows are
reserved for future project parameters.

A long press saves to a slot; a short press loads an occupied slot. Projects
capture the complete machine state: the session graph and random seed stream,
all track mixer/send/gate values, master-return parameters, generator assignments,
harmonic anchor, track scenes, and the global-scene bank. Empty slots are dim cyan,
occupied slots are brighter, and the currently loaded project is saturated red.
A successful long-press save flashes the slot white/red three times. Unlike scenes, projects are
stored in the user's Application Support directory and survive relaunches and
application updates.

## Global scenes

A short press on the fourth top-row button (Programmer address 94) opens the
global-scene page. Its lower four physical rows provide 32 slots in the same
bottom-left-first order as projects; the upper four rows remain reserved. A long
press saves the current playable machine state and flashes the slot three times;
a short press recalls an occupied slot.

Each global scene contains every track graph and lock, mixer/send/gate values,
active track-scene references, and all shared-return parameters. It deliberately
does not contain another scene bank. Global scenes belong to the active project
and are persisted into it immediately without replacing that project's main
recall snapshot. With no active project they remain session-local until a project
is saved. This makes projects the higher-level container and global scenes the
performance states within it.

## Track editor

A short press on a track's right-side auxiliary button opens its eight-row edit
surface. From the physical top row downward, the first four rows are unipolar
post-fader/post-pan sends to shared Reverb, Delay, Saturation + Overdrive, and
Bit Crusher + Decimator returns. Physical row 4 (Programmer notes 41–48) is a
bipolar rhythmic gate, physical row 3 (notes 31–38) holds scene slots 1–8, row 2
is bipolar Pan, and the bottom row is unipolar Volume. Every send and rhythmic
gate defaults to zero/off.

Every slider uses four intensity levels per pad, providing 32 positions across
its eight cells while retaining Programmer mode and the mixed scene/slider page.
Repeated presses on the current cell cycle through its four sublevels; the
cell's brightness reports that finer position. This applies to track controls
and to all shared-return editor macros.

The gate's two centre pads are off. Moving left selects increasingly deep random
gates at master-clock divisions ÷2, ÷4, and ÷8; moving right selects increasingly
deep random gates at ×2, ×4, and ×8. Each track makes independent aleatoric open,
closed, and accent decisions on those clock boundaries. Until project tempo is
implemented, the session master clock is 90 BPM.

Scenes are session-local. A long press stores the track's graph, generator and
processor identities, mixer values, sends, rhythmic gate, generator lock, and harmonic context
in that slot; a short press loads an occupied slot. Empty slots are dim, occupied
slots use a shifted brighter track colour, and the most recently saved or loaded
slot is white. Scene banks are discarded when the application quits unless they
are captured inside a saved project.

## Reverb and delay returns

A short press on the second button from the left above the matrix (Programmer
address 92) toggles the shared-return editor. Every row is a 32-position unipolar
macro. From the physical top downward, rows 8–5 control Reverb Size, Decay, Tone,
and Motion; rows 4–1 control Delay Time, Feedback, Tone, and Stereo Width.

Size combines reverb pre-delay and stereo field, while Motion applies slow
decorrelated modulation to that space. The upper Decay range is deliberately
nonlinear: decorrelated diffusion paths feed a primary tank and then a slower
bloom tank, with maximum feedback held just below unity. At maximum Size and
Decay the result is intended as a massive, slow-building ambient instrument,
while lower values retain controlled room and hall behavior. Delay Width combines right-channel time
offset and return-side stereo expansion. Every parameter is smoothed inside the
persistent Csound return instrument, so editing preserves reverb and delay memory
and does not rebuild the signal graph. Deleting or replacing any track removes
only that track's input to the returns: accumulated reverb and delay tails keep
decaying, including when the final track is deleted. Only Panic or quitting the
application clears return memory. These values are global, shared by all track
sends, and are stored in projects.

## Saturation and decimation returns

A short press on the third button from the left above the matrix (Programmer
address 93) toggles the second shared-return editor. The upper four rows control
Saturation Drive, Curve, Tone, and Body. The lower four control Crusher Bit
Depth, Decimator Sample Rate, Clock Jitter, and Crusher Tone. Every row is a
32-position unipolar control.

Curve moves between smooth `tanh` saturation and a denser overdrive response;
Body adds a parallel low-frequency component after the tone stages. The crusher
uses independent stereo audio-rate sample-and-hold clocks rather than a fixed
control-rate approximation. Jitter continuously destabilizes those clocks, and
rate-aware two-pole reconstruction prevents isolated full-scale clicks while
retaining obvious bit and sample-rate degradation. These shared settings are
stored in projects and older projects receive the established defaults.

Repeating the source-to-destination gesture on an existing endpoint clears it.
Chain limits are not imposed speculatively: clicks, dropouts, or other audible
evidence will determine whether platform-specific safeguards are needed.

## Initial musical families

Every new network begins with one of twenty self-generating synthesis sources:
granular cloud, spectral residue, stochastic impulses, resonant body, feedback
exciter, recursive oscillator, pulsar train, frequency modulation, wave terrain,
additive cluster, noise bands, resonant swarm, Karplus–Strong, prepared string,
struck plate, struck membrane, bowed body, reed/bore, glass bowl, or wooden body.
Audio-input-dependent opcodes
are eligible only as downstream transformations after that source exists.

Processes are executed in graph order: filtering, micro-delay granulation,
variable-rate delay, phase-vocoder freezing, waveshaping, partitioned
convolution, resonator banks, ring modulation, diffusion, and controlled
feedback.

## First milestone

- Interactive 8×8 macOS matrix
- Long-press/source and tap/destination gesture
- Deterministic distance-based processor chains
- No speculative processor limit; practical polyphony is evaluated by listening
- Selection, drain, and panic semantics
- Launchpad input/output adapter
- Bundled Csound runtime and opcode assets
- Stereo output with conservative gain and feedback protection
- Portable session representation

## Distribution rule

ParallelLives distributions are self-contained. A user must not need to install
Csound, Homebrew, opcode plug-ins, or orchestra assets. Platform-specific Csound
runtimes are embedded during packaging and audited for unresolved external
dependencies. Apple and Linux ARM64 runtimes are separate artifacts built from
the same source and graph definitions.
