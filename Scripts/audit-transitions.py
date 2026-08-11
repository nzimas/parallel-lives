#!/usr/bin/env python3
"""Offline sample-discontinuity audit for live Vascular graph transactions."""

import ctypes
import math
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "Sources/VascularMac/Resources/Runtime"
FRAMEWORK = RUNTIME / "Frameworks/CsoundLib64.framework/Versions/6.0/CsoundLib64"
OPCODES = RUNTIME / "Frameworks/CsoundLib64.framework/Versions/6.0/Resources/Opcodes64"
CSD = ROOT / "Sources/VascularMac/Resources/Orchestra/Vascular.csd"
os.environ["OPCODE6DIR64"] = str(OPCODES)

lib = ctypes.CDLL(str(FRAMEWORK), mode=ctypes.RTLD_LOCAL)
handle_type = ctypes.c_void_p
lib.csoundCreate.argtypes = [ctypes.c_void_p]
lib.csoundCreate.restype = handle_type
lib.csoundDestroy.argtypes = [handle_type]
lib.csoundSetOption.argtypes = [handle_type, ctypes.c_char_p]
lib.csoundSetOption.restype = ctypes.c_int
lib.csoundCompileCsd.argtypes = [handle_type, ctypes.c_char_p]
lib.csoundCompileCsd.restype = ctypes.c_int
lib.csoundStart.argtypes = [handle_type]
lib.csoundStart.restype = ctypes.c_int
lib.csoundPerformKsmps.argtypes = [handle_type]
lib.csoundPerformKsmps.restype = ctypes.c_int
lib.csoundGetKsmps.argtypes = [handle_type]
lib.csoundGetKsmps.restype = ctypes.c_uint
lib.csoundGetNchnls.argtypes = [handle_type]
lib.csoundGetNchnls.restype = ctypes.c_uint
lib.csoundGetSr.argtypes = [handle_type]
lib.csoundGetSr.restype = ctypes.c_double
lib.csoundGetSpout.argtypes = [handle_type]
lib.csoundGetSpout.restype = ctypes.POINTER(ctypes.c_double)
lib.csoundInputMessageAsync.argtypes = [handle_type, ctypes.c_char_p]
lib.csoundStop.argtypes = [handle_type]
lib.csoundCleanup.argtypes = [handle_type]
lib.csoundReset.argtypes = [handle_type]


def send(csound, message):
    lib.csoundInputMessageAsync(csound, message.encode("utf-8"))


csound = lib.csoundCreate(None)
if not csound:
    raise RuntimeError("csoundCreate failed")

try:
    for option in (b"-+ignore_csopts=1", b"-n", b"-d", b"-m0"):
        if lib.csoundSetOption(csound, option) != 0:
            raise RuntimeError(f"csoundSetOption failed: {option!r}")
    if lib.csoundCompileCsd(csound, str(CSD).encode("utf-8")) != 0:
        raise RuntimeError("csoundCompileCsd failed")
    if lib.csoundStart(csound) != 0:
        raise RuntimeError("csoundStart failed")

    sample_rate = int(lib.csoundGetSr(csound))
    ksmps = int(lib.csoundGetKsmps(csound))
    channels = int(lib.csoundGetNchnls(csound))
    samples = []
    transition_times = [
        1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0,
        6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 10.0,
    ]

    send(csound, "i 700 0 0.01 0 1 0 0.55 0.55 0.55 0.55 0")
    send(csound, "i 100.000000001 0 -1 9 0.72 12001 78001 55 1")
    send(csound, "i 200.000000001 0 -1 9 0.68 22001 1 2 55")
    send(csound, "i 200.000000002 0 -1 2 0.68 22102 2 3 55")
    send(csound, "i 800.000000001 0.26 -1 3 0 0.2")

    events = {
        int(1.0 * sample_rate / ksmps): [
            "i 700 0 0.01 0 1 0 0.55 0.55 0.55 0.55 -1",
        ],
        int(1.5 * sample_rate / ksmps): [
            "i 710 0 0.01 1 0.9 1 1 0.1 0.7 0.2 1",
        ],
        int(2.0 * sample_rate / ksmps): [
            "i 200.000000003 0 -1 14 0.68 22303 3 4 55",
            "i 800.000000002 0.26 -1 4 0 0.2",
            "i -800.000000001 0.26 0",
        ],
        int(2.5 * sample_rate / ksmps): [
            "i 720 0 0.01 1 1 0.8 1 1 1 0 1",
        ],
        int(3.0 * sample_rate / ksmps): [
            "i 700 0 0.01 0 1 0 0.55 0.55 0.55 0.55 0",
        ],
        int(3.5 * sample_rate / ksmps): [
            "i 710 0 0.01 0.1 0.2 0.1 0 0.9 0.2 1 0",
        ],
        int(4.0 * sample_rate / ksmps): [
            "i 800.000000003 0.26 -1 3 0 0.2",
            "i -800.000000002 0.26 0",
            "i -200.000000003 0.64 0",
        ],
        int(4.5 * sample_rate / ksmps): [
            "i 720 0 0.01 0.2 0.1 0.3 0.2 0 0 1 0.2",
        ],
        int(5.0 * sample_rate / ksmps): [
            "i 700 0 0.01 0 1 0 0.55 0.55 0.55 0.55 1",
        ],
        int(5.5 * sample_rate / ksmps): [
            "i 710 0 0.01 0.5 0.68 0.53 0.15 0.4 0.52 0.55 0.45",
        ],
        int(6.0 * sample_rate / ksmps): [
            "i 100.000000010 0 -1 9 0.77 32001 88001 68.75 10",
            "i 200.000000010 0 -1 3 0.72 42001 10 11 68.75",
            "i 200.000000011 0 -1 4 0.64 42102 11 12 68.75",
            "i 800.000000010 0.26 -1 12 0 0.2",
            "i -800.000000003 0.26 0",
            "i -100.000000001 0.64 0",
            "i -200.000000001 0.64 0",
            "i -200.000000002 0.64 0",
        ],
        int(6.5 * sample_rate / ksmps): [
            "i 720 0 0.01 0.38 0.3 0.58 0.35 0.2 0.4 0.08 0.27",
        ],
        int(7.0 * sample_rate / ksmps): [
            "i 700 0 0.01 0 1 0 0.55 0.55 0.55 0.55 0",
            # Re-seed a generator in place: the new source writes to the same
            # root bus while the old voice follows its release envelope.
            "i 100.000000012 0 -1 9 0.63 33091 89117 68.75 10",
            "i -100.000000010 0 0",
        ],
        int(7.5 * sample_rate / ksmps): [
            "i 710 0 0.01 0.8 0.95 0.8 0.8 0.65 1 0.7 0.9",
        ],
        int(8.0 * sample_rate / ksmps): [
            "i 100.000000020 0 -1 9 0.72 12001 78001 55 20",
            "i 200.000000020 0 -1 9 0.68 22001 20 21 55",
            "i 200.000000021 0 -1 2 0.68 22102 21 22 55",
            "i 800.000000020 0.26 -1 22 0 0.2",
            "i -800.000000010 0.26 0",
            "i -100.000000012 0.64 0",
            "i -200.000000010 0.64 0",
            "i -200.000000011 0.64 0",
        ],
        int(8.5 * sample_rate / ksmps): [
            "i 720 0 0.01 0.8 0.7 0.6 0.8 0.15 0.15 0.8 0.4",
        ],
        # Remove the only terminal while leaving the shared returns running.
        # The following silent-feed interval must still contain their tails.
        int(9.0 * sample_rate / ksmps): [
            "i -800.000000020 0 0",
        ],
        int(10.0 * sample_rate / ksmps): [
            "i 800.000000022 0.26 -1 22 0 0.2",
        ],
    }

    # Exercise insertion and removal of every processor family from a stable
    # source path. Each transaction gets a fresh bus and named instrument so no
    # previous delay or feedback memory can mask an unsafe startup.
    current_base_output = "800.000000022"
    for kind in range(15):
        insertion_time = 10.5 + kind * 2.0
        collapse_time = insertion_time + 1.2
        processor_voice = f"200.{100 + kind:09d}"
        effect_output = f"800.{100 + kind:09d}"
        next_base_output = f"800.{200 + kind:09d}"
        effect_bus = 40 + kind
        events[int(insertion_time * sample_rate / ksmps)] = [
            f"i {processor_voice} 0 -1 {kind} 0.72 {52001 + kind * 101} 22 {effect_bus} 55",
            f"i {effect_output} 0.26 -1 {effect_bus} 0 0.2",
            f"i -{current_base_output} 0.26 0",
        ]
        events[int(collapse_time * sample_rate / ksmps)] = [
            f"i {next_base_output} 0.26 -1 22 0 0.2",
            f"i -{effect_output} 0.26 0",
            f"i -{processor_voice} 0.64 0",
        ]
        transition_times.extend([insertion_time, collapse_time])
        current_base_output = next_base_output

    # Full root replacement across every self-generating source family catches
    # excitation and oscillator startup faults that processor-only edits cannot.
    # Seven rotating processor families make each replacement a realistic scene.
    current_source = "100.000000020"
    current_scene_processors = []
    source_family_windows = []
    source_onset_windows = []
    for family in range(20):
        switch_time = 41.0 + family * 1.5
        source_family_windows.append((family, switch_time + 0.35, switch_time + 1.35))
        source_onset_windows.append((family, switch_time + 0.28, switch_time + 0.55))
        source_voice = f"100.{300 + family:09d}"
        source_output = f"800.{300 + family:09d}"
        bus_bank = family % 2
        source_bus = 140 + bus_bank
        fundamental = 55 * (1, 1.125, 1.2, 1.25, 4 / 3, 1.5)[family % 6]
        messages = [
            f"i {source_voice} 0 -1 {family} 0.74 {62001 + family * 307} {92001 + family * 401} {fundamental} {source_bus}",
        ]
        input_bus = source_bus
        scene_processors = []
        for stage in range(7):
            processor_voice = f"200.{400 + family * 10 + stage:09d}"
            output_bus = 150 + bus_bank * 8 + stage
            kind = (family * 7 + stage) % 15
            messages.append(
                f"i {processor_voice} 0 -1 {kind} 0.7 {72001 + family * 701 + stage * 103} {input_bus} {output_bus} {fundamental}"
            )
            scene_processors.append(processor_voice)
            input_bus = output_bus
        messages.extend([
            f"i {source_output} 0.26 -1 {input_bus} 0 0.2",
            f"i -{current_base_output} 0.26 0",
            f"i -{current_source} 0.64 0",
        ])
        messages.extend(f"i -{voice} 0.64 0" for voice in current_scene_processors)
        events[int(switch_time * sample_rate / ksmps)] = messages
        transition_times.append(switch_time)
        current_base_output = source_output
        current_source = source_voice
        current_scene_processors = scene_processors

    # After the final scene has excited the maximum-decay return, remove every
    # graph voice and require the shared ambient tail to survive for many more
    # seconds with no possible source feed.
    final_drain_time = 41.0 + 20 * 1.5
    events[int(final_drain_time * sample_rate / ksmps)] = [
        f"i -{current_base_output} 0 0",
        f"i -{current_source} 0.64 0",
    ] + [f"i -{voice} 0.64 0" for voice in current_scene_processors]
    transition_times.append(final_drain_time)

    total_blocks = int((final_drain_time + 26.0) * sample_rate / ksmps)
    for block in range(total_blocks):
        for message in events.get(block, ()):
            send(csound, message)
        if lib.csoundPerformKsmps(csound) != 0:
            raise RuntimeError(f"performance ended at block {block}")
        spout = lib.csoundGetSpout(csound)
        for frame in range(ksmps):
            samples.append(float(spout[frame * channels]))

    deltas = [abs(right - left) for left, right in zip(samples, samples[1:])]
    peak = max(abs(value) for value in samples)
    global_jump = max(deltas)
    tail = samples[int(9.45 * sample_rate):int(9.95 * sample_rate)]
    tail_rms = math.sqrt(sum(value * value for value in tail) / len(tail))
    long_tail = samples[
        int((final_drain_time + 20.0) * sample_rate):
        int((final_drain_time + 22.0) * sample_rate)
    ]
    long_tail_rms = math.sqrt(
        sum(value * value for value in long_tail) / len(long_tail)
    )
    print(f"peak={peak:.6f} max_sample_jump={global_jump:.6f}")
    print(f"master_return_tail_rms={tail_rms:.6f}")
    print(f"master_return_20s_tail_rms={long_tail_rms:.6f}")
    family_rms_values = []
    for family, start_time, end_time in source_family_windows:
        window = samples[int(start_time * sample_rate):int(end_time * sample_rate)]
        family_rms = math.sqrt(sum(value * value for value in window) / len(window))
        family_rms_values.append(family_rms)
        print(f"source_family={family} rms={family_rms:.6f}")
    onset_rms_values = []
    for family, start_time, end_time in source_onset_windows:
        window = samples[int(start_time * sample_rate):int(end_time * sample_rate)]
        onset_rms = math.sqrt(sum(value * value for value in window) / len(window))
        onset_rms_values.append(onset_rms)
        print(f"source_onset_family={family} rms={onset_rms:.6f}")
    for transition in transition_times:
        start = int((transition - 0.15) * sample_rate)
        end = int((transition + 1.25) * sample_rate)
        jump = max(deltas[start:end])
        print(f"transition@{transition:.1f}s max_sample_jump={jump:.6f}")

    if not math.isfinite(peak) or not math.isfinite(global_jump):
        raise RuntimeError("non-finite audio detected")
    if peak >= 0.98:
        raise RuntimeError(f"transition peak reached safety saturation: {peak:.6f}")
    if global_jump >= 0.12:
        raise RuntimeError(f"sample discontinuity exceeded threshold: {global_jump:.6f}")
    if tail_rms <= 0.00005:
        raise RuntimeError(f"master return tail was truncated: rms={tail_rms:.6f}")
    if long_tail_rms <= 0.00005:
        raise RuntimeError(f"maximum reverb did not sustain a 20s tail: rms={long_tail_rms:.6f}")
    for family, family_rms in enumerate(family_rms_values):
        if family_rms <= 0.000001:
            raise RuntimeError(
                f"source family {family} was silent in a realistic chain: rms={family_rms:.6f}"
            )
    sparse_physical_families = (3, 12, 13, 14, 15, 18, 19)
    for family in sparse_physical_families:
        if onset_rms_values[family] <= 0.00001:
            raise RuntimeError(
                f"physical source family {family} missed its onset window: "
                f"rms={onset_rms_values[family]:.6f}"
            )
finally:
    lib.csoundStop(csound)
    lib.csoundCleanup(csound)
    lib.csoundReset(csound)
    lib.csoundDestroy(csound)
