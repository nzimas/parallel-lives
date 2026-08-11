# ParallelLives User Guide

## 1. Requirements and installation

The current release supports Apple Silicon Macs running macOS 14 Sonoma or
newer. A Novation Launchpad Mini Mk3 is the primary performance controller, but
the macOS matrix can be operated with a trackpad.

1. Download the latest `ParallelLives-…-macOS-arm64.zip` from
   [GitHub Releases](https://github.com/nzimas/parallel-lives/releases/latest).
2. Double-click the ZIP archive.
3. Move `ParallelLives.app` to `/Applications` or `~/Applications`.
4. Connect the Launchpad Mini Mk3 before opening ParallelLives.
5. Open ParallelLives normally.

The current public build is ad-hoc signed because the project does not yet have
an Apple Developer ID certificate. If macOS blocks the first launch, Control-click
`ParallelLives.app`, choose **Open**, then confirm **Open** once. This approval is
normally remembered. Do not disable Gatekeeper globally.

Csound is bundled inside the application. Do not install Csound, Homebrew audio
packages, or opcode plug-ins separately.

## 2. Trackpad control surface

The complete instrument can be operated from the macOS window without a
Launchpad. The large 8 × 8 matrix mirrors the hardware pads, the eight buttons
above it mirror the Launchpad's top row, and the coloured T1–T8 buttons at the
right mirror the track buttons.

- Click a matrix pad for a short press.
- Click and hold a pad for about half a second for a long press.
- Use **PROJ**, **SPACE**, **TEXT**, and **SCENE** for the four editing views.
- Click a coloured T1–T8 button to open or close that track's editor.
- Click **SHIFT** to latch Shift, click a generator or current endpoint to apply
  a lock operation, then click **SHIFT** again to unlatch it.

The three controls marked with a dash are reserved. Track buttons are disabled
while a master, project, global-scene, or Shift view is active. The status line
below the matrix describes the current gesture. **Remove** deletes the selected
chain and **Panic** immediately stops all audio and clears return tails.

## 3. Controller connection

ParallelLives selects the non-DAW `LPMiniMK3 MIDI` input and output ports and
places the controller in Programmer mode. The status area should read
`LAUNCHPAD · PROGRAMMER MODE`.

If the controller is not found:

1. Quit ParallelLives.
2. Disconnect and reconnect the Launchpad directly to the Mac.
3. Close Ableton Live, Components, or another application that may own its MIDI
   ports.
4. Reopen ParallelLives.

ParallelLives restores the controller to Live mode when the application quits
normally.

## 4. The track matrix

The eight physical rows are eight independent tracks. Audio and processor chains
always travel from left to right and never intersect.

To create a track:

1. Hold the leftmost pad in an empty row.
2. Press a pad to its right.
3. Release the pads.

The leftmost pad becomes the generator. Every intervening pad becomes one audio
processor, and the selected pad becomes the endpoint/output.

To manage an existing track, hold its leftmost generator pad and:

- press the current endpoint to clear the complete live track;
- press a pad before the endpoint to trim the chain there;
- press a pad after the endpoint to extend it with new processors.

No fixed processor limit is imposed beyond the seven processor cells available
on each row. Graph changes use complementary fades and staged processor startup
to avoid clicks and dropouts.

## 5. Generators and harmonic relationships

Each new root track selects one of twenty synthesis families. The palette
includes granular, spectral, stochastic, feedback, pulsar, FM, wave-terrain,
additive, resonant, Karplus–Strong, prepared-string, plate, membrane, bowed,
reed/bore, glass, and wooden-body materials.

Plucked and struck sources contain unstable internal clocks so they continue to
excite themselves without imposing a regular beat.

The first generator locked by the performer establishes a harmonic anchor.
Generators created afterward use related just-intonation fundamentals in a
curated low register. The relationship affects pitched sources and
frequency-aware processors without forcing the music into a melodic sequencer.

## 6. Shift and locks

The rightmost top button, Programmer address 98, is **Shift**.

### Generator lock

Hold Shift and press a track's generator pad. The synthesis identity and source
seed are assigned to that track. If the visible track is later cleared, its next
chain begins with the same generator.

Repeat Shift + generator to unlock it. Unlocking a generator also removes its
dependent chain lock.

### Chain-prefix lock

With a generator lock already present, hold Shift and press the current endpoint.
The complete chain from generator through that processor is stored exactly,
including processor kinds, order, intensities, seeds, and modulation identities.

The locked prefix appears as a dim track-colour trail. You may continue extending
the live chain to its right. Shift + the newer endpoint moves the lock forward.
Repeating Shift + an unchanged locked endpoint removes the chain lock.

After clearing the track, recreate it at the locked endpoint to restore the exact
prefix, or choose a farther endpoint to restore the prefix and generate a new
suffix.

### Processor parameter randomization

Hold the coloured track button beside a row, then short-press one processor pad
on that row. The opcode family and its position remain unchanged, while its
intensity, modulation identity, and internal parameter seed are regenerated.
You may randomize several processors before releasing the hardware track button.

The same gesture on an unlocked generator pad regenerates its internal voicing
parameters while preserving the synthesis family and harmonic fundamental. A
generator lock prevents this operation; a chain lock necessarily protects its
generator as well.

On the macOS trackpad surface, long-press T1–T8 to arm the corresponding track,
then click one processor pad. This software gesture is one-shot and disarms
after the pad is selected.

Pads inside a chain-locked prefix cannot be randomized. The status line reports
the rejection without altering the locked module. Empty pads and pads belonging
to another track are likewise ignored. A successful randomization changes the
current machine state and can subsequently be captured in a track scene, global
scene, or project.

### Matrix module labels

Every active generator and processor pad in the macOS track matrix displays a
compact module name. Labels such as **KARPLUS**, **PREP STR**, **FILTER**,
**V DELAY**, **FREEZE**, and **RING MOD** identify the synthesis or processing
family without requiring selection. Longer names use readable abbreviations or
two lines so they remain inside the pad. Editor pages continue to display their
control and slot labels instead.

## 7. Track editor

Short-press the right-side button beside a track to open its editor. The side
button uses the same fixed colour as that track.

The rows are listed from physical top to bottom:

| Physical row | Programmer notes | Control |
|---|---:|---|
| 8 | 81–88 | Reverb send |
| 7 | 71–78 | Delay send |
| 6 | 61–68 | Saturation + overdrive send |
| 5 | 51–58 | Bit crusher + decimator send |
| 4 | 41–48 | Bipolar random rhythmic gate |
| 3 | 31–38 | Track scene slots 1–8 |
| 2 | 21–28 | Bipolar pan |
| 1 | 11–18 | Volume |

All sends default to zero. Pan is applied after the stereo Csound chain, so a
centred track can still contain internal stereo movement.

### Thirty-two-position sliders

Every slider has four values per pad, for 32 positions across the row. Press the
current pad repeatedly to cycle through its four sublevels. Its brightness shows
the current sublevel. Moving to another pad enters that pad at the nearest value
in the direction of travel.

Pan and rhythmic gate are bipolar and retain two visually centred zero positions.
The gate becomes deeper as it moves away from centre. Left positions use slower
master-clock divisions; right positions use faster multiplications. Gate opening,
closing, and accents remain aleatoric.

### Track scenes

The third physical row contains eight scenes for the selected track.

- Long press: save or overwrite the track scene.
- Short press: load an occupied track scene.

A track scene stores that row's graph, locks, mixer values, sends, gate, and
harmonic context. Track scenes are included when their containing project is
saved.

## 8. Projects

Short-press the first top button from the left, address 91, to open Projects.
The lower four rows contain 32 persistent project slots, numbered from the
bottom-left across each row.

- Long press: save or overwrite a project.
- Short press: load an occupied project.

A successful save flashes the slot three times. The currently loaded project is
bright red; other occupied slots are cyan.

A project contains the complete machine state, track-scene banks, global-scene
bank, locks, harmonic anchor, random seed stream, track controls, and master
effects. Project data is stored at:

```text
~/Library/Application Support/Vascular/Projects.json
```

The historical directory name is retained for compatibility.

## 9. Global scenes

Short-press the fourth top button, address 94. The lower four rows contain 32
global scenes belonging to the active project.

- Long press: save or overwrite the current complete playable state.
- Short press: recall an occupied scene.

Successful saves blink three times. The active global scene is amber and other
occupied scenes are purple. Saving a global scene writes its bank into the active
project immediately without replacing the project's main recall snapshot.

If no project is active, global scenes remain available during the session; save
a project to retain them after quitting.

## 10. Reverb and delay editor

Short-press the second top button, address 92. All rows are 32-position unipolar
sliders.

| Physical rows | Controls |
|---|---|
| 8–5 | Reverb Size, Decay, Tone, Motion |
| 4–1 | Delay Time, Feedback, Tone, Stereo Width |

Track sends feed shared persistent returns. Clearing a track removes its new
input but does not cut existing reverb or delay tails. At high Size and Decay,
the reverb becomes a deliberately massive ambient instrument.

## 11. Saturation and decimation editor

Short-press the third top button, address 93.

| Physical rows | Controls |
|---|---|
| 8–5 | Saturation Drive, Curve, Tone, Body |
| 4–1 | Crusher Bits, Decimator Rate, Clock Jitter, Tone |

These are shared returns controlled by each track's sends. The decimator uses
audio-rate sample-and-hold clocks; Jitter destabilizes them independently across
the stereo field.

## 12. Panic, quitting, and audio safety

Use **Panic** in the macOS window to stop all tracks and clear master-return
memory. Quitting ParallelLives also stops the embedded Csound engine and restores
the Launchpad's Live mode.

If audio continues after closing the window, quit ParallelLives from the Dock or
app switcher. The release runs Csound in-process and does not intentionally leave
a command-line Csound child process behind.

## 13. Troubleshooting

### No sound

- Confirm the Mac's selected audio output and volume.
- Create a chain with at least one processor pad to the right of the generator.
- Check the track editor's Volume and random Gate.
- Use Panic, then create a new track.

### A physical-model source seems sparse

Plucked, struck, glass, plate, and wooden sources use irregular self-excitation.
Their activity is intentionally less continuous than drones. Extend the chain,
try another track, or clear and reseed if the material does not suit the moment.

### A project or scene does not load

Only occupied slots load. Projects created by earlier releases are migrated with
defaults for parameters introduced later. A corrupt project archive is rejected
rather than partially applied.

### Launchpad lights do not update

Quit other MIDI software, reconnect the controller, and relaunch ParallelLives.
Use the non-DAW MIDI port; ParallelLives selects it automatically.

### CPU spikes or dropouts

ParallelLives supports eight tracks with seven processors each, but opcode costs
vary. Panic and rebuild gradually to identify a problematic combination. Report
repeatable cases with the number of tracks, chain lengths, and whether master
returns were active.
