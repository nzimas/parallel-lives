import CoreMIDI
import Foundation
import VascularCore

enum LaunchpadEvent: Sendable {
    case projectPressed
    case projectReleased
    case masterEffectsPressed
    case masterEffectsReleased
    case destructiveEffectsPressed
    case destructiveEffectsReleased
    case globalScenesPressed
    case globalScenesReleased
    case pressed(PadCoordinate, velocity: UInt8)
    case released(PadCoordinate)
    case auxiliaryPressed(row: Int)
    case auxiliaryReleased(row: Int)
    case shiftPressed
    case shiftReleased
}

final class LaunchpadController: @unchecked Sendable {
    typealias EventHandler = @Sendable (LaunchpadEvent) -> Void

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var destination = MIDIEndpointRef()
    private let eventHandler: EventHandler

    init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    deinit {
        disconnect()
    }

    func disconnect() {
        send(Self.liveModeMessage)
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
        inputPort = 0
        outputPort = 0
        destination = 0
        client = 0
    }

    @discardableResult
    func connect() -> [String] {
        guard client == 0 else { return connectedSources.compactMap(endpointName) }

        guard MIDIClientCreate(
            "ParallelLives MIDI" as CFString,
            nil,
            nil,
            &client
        ) == noErr else { return [] }

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        guard MIDIInputPortCreate(
            client,
            "ParallelLives Launchpad Input" as CFString,
            launchpadMIDIRead,
            opaqueSelf,
            &inputPort
        ) == noErr else { return [] }

        guard MIDIOutputPortCreate(
            client,
            "ParallelLives Launchpad Output" as CFString,
            &outputPort
        ) == noErr else { return [] }

        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0,
                  let name = endpointName(source),
                  isProgrammerEndpoint(name) else { continue }

            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connectedSources.append(source)
                names.append(name)
            }
        }


        for index in 0..<MIDIGetNumberOfDestinations() {
            let candidate = MIDIGetDestination(index)
            guard candidate != 0,
                  let name = endpointName(candidate),
                  isProgrammerEndpoint(name) else { continue }
            destination = candidate
            break
        }

        if destination != 0 {
            send(Self.programmerModeMessage)
        }
        return names
    }

    func render(
        vessels: [VesselGraph],
        awakenedPad: PadCoordinate?,
        selectedVesselID: VesselGraph.ID?,
        hubPulseBright: Bool,
        editingTrack: Int?,
        trackVolumes: [Double],
        trackPans: [Double],
        trackSends: [TrackSendLevels],
        trackGates: [Double],
        projectViewOpen: Bool,
        occupiedProjectSlots: Set<Int>,
        activeProjectSlot: Int?,
        projectSaveConfirmationSlot: Int?,
        projectSaveConfirmationBright: Bool,
        globalSceneViewOpen: Bool,
        occupiedGlobalSceneSlots: Set<Int>,
        activeGlobalSceneSlot: Int?,
        globalSceneSaveConfirmationSlot: Int?,
        globalSceneSaveConfirmationBright: Bool,
        masterEffectsViewOpen: Bool,
        masterEffects: MasterEffectParameters,
        destructiveEffectsViewOpen: Bool,
        destructiveEffects: DestructiveEffectParameters,
        occupiedSceneSlots: Set<Int>,
        activeSceneSlot: Int?,
        generatorLockRows: Set<Int>,
        chainLockEndpoints: [Int: Int],
        shiftHeld: Bool,
        processorRandomizeTrack: Int?
    ) {
        guard destination != 0 else { return }

        var colours = Dictionary(
            uniqueKeysWithValues: (0..<64).map { index in
                (PadCoordinate(row: index / 8, column: index % 8), RGB(r: 3, g: 4, b: 4))
            }
        )

        if destructiveEffectsViewOpen {
            for control in DestructiveEffectControl.allCases {
                let step = LaunchpadFader.unipolarStep(for: destructiveEffects.value(for: control))
                let selectedColumn = LaunchpadFader.padColumn(forStep: step)
                let hue = control.rawValue < 4 ? 0.02 : 0.58
                for column in 0..<8 {
                    let brightness = column == selectedColumn
                        ? LaunchpadFader.markerBrightness(forStep: step)
                        : (column < selectedColumn ? 0.58 : 0.045)
                    colours[PadCoordinate(row: control.rawValue, column: column)] = Self.colour(
                        hue: hue, brightness: brightness
                    )
                }
            }
        } else if masterEffectsViewOpen {
            for control in MasterEffectControl.allCases {
                let step = LaunchpadFader.unipolarStep(for: masterEffects.value(for: control))
                let selectedColumn = LaunchpadFader.padColumn(forStep: step)
                let hue = control.rawValue < 4 ? 0.78 : 0.1
                for column in 0..<8 {
                    let brightness = column == selectedColumn
                        ? LaunchpadFader.markerBrightness(forStep: step)
                        : (column < selectedColumn ? 0.58 : 0.045)
                    colours[PadCoordinate(row: control.rawValue, column: column)] = Self.colour(
                        hue: hue, brightness: brightness
                    )
                }
            }
        } else if globalSceneViewOpen {
            for slot in 0..<GlobalSceneGrid.slotCount {
                guard let pad = GlobalSceneGrid.pad(for: slot) else { continue }
                if globalSceneSaveConfirmationSlot == slot
                    && globalSceneSaveConfirmationBright {
                    colours[pad] = RGB(r: 127, g: 127, b: 127)
                } else if activeGlobalSceneSlot == slot {
                    colours[pad] = Self.colour(hue: 0.13, brightness: 0.98)
                } else {
                    colours[pad] = Self.colour(
                        hue: 0.82,
                        brightness: occupiedGlobalSceneSlots.contains(slot) ? 0.72 : 0.075
                    )
                }
            }
        } else if projectViewOpen {
            for slot in 0..<ProjectGrid.slotCount {
                guard let pad = ProjectGrid.pad(for: slot) else { continue }
                if projectSaveConfirmationSlot == slot && projectSaveConfirmationBright {
                    colours[pad] = RGB(r: 127, g: 127, b: 127)
                } else if activeProjectSlot == slot {
                    // Saturated red is reserved for the project currently loaded
                    // into the machine, distinct from occupied cyan slots.
                    colours[pad] = RGB(r: 127, g: 0, b: 0)
                } else {
                    colours[pad] = Self.colour(
                        hue: 0.52,
                        brightness: occupiedProjectSlots.contains(slot) ? 0.72 : 0.075
                    )
                }
            }
        } else if let track = editingTrack {
            let hue = TrackPalette.hue(forRow: track)
            let volumeStep = LaunchpadFader.unipolarStep(for: trackVolumes[track])
            let volumeColumn = LaunchpadFader.padColumn(forStep: volumeStep)
            for column in 0..<8 {
                let brightness = column == volumeColumn
                    ? LaunchpadFader.markerBrightness(forStep: volumeStep)
                    : (column < volumeColumn ? 0.58 : 0.045)
                colours[PadCoordinate(row: TrackMixer.volumePadRow, column: column)] = Self.colour(
                    hue: hue, brightness: brightness
                )
            }

            let panStep = LaunchpadFader.bipolarStep(for: trackPans[track])
            let panColumn = LaunchpadFader.padColumn(forStep: panStep)
            for column in 0..<8 {
                let active: Bool
                if panColumn <= 3 {
                    active = column >= panColumn && column <= 3
                } else {
                    active = column >= 4 && column <= panColumn
                }
                let centre = trackPans[track] == 0 && (column == 3 || column == 4)
                let brightness = column == panColumn
                    ? LaunchpadFader.markerBrightness(forStep: panStep)
                    : (centre ? 0.67 : (active ? 0.58 : 0.045))
                colours[PadCoordinate(row: TrackMixer.panPadRow, column: column)] = Self.colour(
                    hue: hue, brightness: brightness
                )
            }

            let sends = trackSends[track]
            let sendRows: [(row: Int, value: Double)] = [
                (TrackMixer.reverbPadRow, sends.reverb),
                (TrackMixer.delayPadRow, sends.delay),
                (TrackMixer.saturationPadRow, sends.saturation),
                (TrackMixer.crusherPadRow, sends.crusher),
            ]
            for send in sendRows {
                let step = LaunchpadFader.unipolarStep(for: send.value)
                let selectedColumn = LaunchpadFader.padColumn(forStep: step)
                for column in 0..<8 {
                    let brightness = column == selectedColumn
                        ? LaunchpadFader.markerBrightness(forStep: step)
                        : (column < selectedColumn ? 0.58 : 0.045)
                    colours[PadCoordinate(row: send.row, column: column)] = Self.colour(
                        hue: hue, brightness: brightness
                    )
                }
            }

            let gate = trackGates[track]
            let gateStep = LaunchpadFader.bipolarStep(for: gate)
            let gateColumn = LaunchpadFader.padColumn(forStep: gateStep)
            for column in 0..<8 {
                let active = gateColumn <= 3
                    ? (column >= gateColumn && column <= 3)
                    : (column >= 4 && column <= gateColumn)
                let centre = abs(gate) < 0.000_001 && (column == 3 || column == 4)
                let brightness = column == gateColumn
                    ? LaunchpadFader.markerBrightness(forStep: gateStep)
                    : (centre ? 0.67 : (active ? 0.58 : 0.045))
                colours[PadCoordinate(row: TrackMixer.gatePadRow, column: column)] = Self.colour(
                    hue: hue, brightness: brightness
                )
            }

            for slot in 0..<TrackSceneBank.slotsPerTrack {
                let pad = PadCoordinate(
                    row: TrackMixer.scenePadRows[slot / 8],
                    column: slot % 8
                )
                if activeSceneSlot == slot {
                    colours[pad] = RGB(r: 127, g: 127, b: 127)
                } else {
                    colours[pad] = Self.colour(
                        hue: hue + 0.085,
                        brightness: occupiedSceneSlots.contains(slot) ? 0.68 : 0.075
                    )
                }
            }
        } else {
            for (row, endpointColumn) in chainLockEndpoints {
                for column in 0...max(0, min(7, endpointColumn)) {
                    colours[PadCoordinate(row: row, column: column)] = Self.colour(
                        hue: TrackPalette.hue(forRow: row),
                        brightness: column == endpointColumn ? 0.2 : 0.085
                    )
                }
            }
            for vessel in vessels {
                let selected = vessel.id == selectedVesselID
                let routeColour = Self.colour(
                    hue: TrackPalette.hue(forRow: vessel.source.row),
                    brightness: selected ? 0.62 : 0.45
                )
                for pad in vessel.source.gridRoute(to: vessel.destination) {
                    colours[pad] = routeColour
                }
            }
            let activePads = Set(vessels.flatMap { $0.source.gridRoute(to: $0.destination) })
            for (row, endpointColumn) in chainLockEndpoints {
                for column in 0...max(0, min(7, endpointColumn)) {
                    let pad = PadCoordinate(row: row, column: column)
                    let active = activePads.contains(pad)
                    colours[pad] = Self.colour(
                        hue: TrackPalette.hue(forRow: row),
                        brightness: column == endpointColumn
                            ? (active ? 0.34 : 0.2)
                            : (active ? 0.27 : 0.085)
                    )
                }
            }
            let parentIDs = Set(vessels.flatMap(\.parentVesselIDs))
            for vessel in vessels where vessel.parentVesselIDs.isEmpty {
                colours[vessel.source] = Self.colour(
                    hue: TrackPalette.hue(forRow: vessel.source.row), brightness: 0.98
                )
            }
            for row in generatorLockRows {
                let generator = PadCoordinate(row: row, column: 0)
                let hasVessel = vessels.contains {
                    $0.parentVesselIDs.isEmpty && $0.source.row == row
                }
                if shiftHeld {
                    colours[generator] = RGB(r: 127, g: 127, b: 127)
                } else if hasVessel {
                    colours[generator] = Self.colour(
                        hue: TrackPalette.hue(forRow: row), brightness: 0.98
                    )
                }
            }
            for vessel in vessels where !parentIDs.contains(vessel.id) {
                colours[vessel.destination] = Self.colour(
                    hue: TrackPalette.hue(forRow: vessel.source.row), brightness: 0.98
                )
            }
            if let awakenedPad { colours[awakenedPad] = RGB(r: 127, g: 42, b: 2) }
            if shiftHeld {
                for (row, endpointColumn) in chainLockEndpoints {
                    colours[PadCoordinate(row: row, column: endpointColumn)] = RGB(
                        r: 127, g: 127, b: 127
                    )
                }
            }
        }
        let hubColour = hubPulseBright
            ? RGB(r: 127, g: 127, b: 127)
            : RGB(r: 18, g: 20, b: 20)
        if !projectViewOpen && !globalSceneViewOpen && !masterEffectsViewOpen
            && !destructiveEffectsViewOpen && editingTrack == nil {
            for hub in VesselTopology(vessels: vessels).hubs {
                colours[hub] = hubColour
            }
        }

        var lights: [(note: UInt8, colour: RGB)] = (0..<64).map {
            let pad = PadCoordinate(row: $0 / 8, column: $0 % 8)
            return (LaunchpadGridMapping.note(for: pad), colours[pad] ?? RGB(r: 0, g: 0, b: 0))
        }
        lights += (0..<8).map { row in
            let brightness = processorRandomizeTrack == row
                ? 0.98
                : (editingTrack == row ? 0.82 : 0.16)
            return (LaunchpadGridMapping.auxiliaryNote(forRow: row), Self.colour(
                hue: TrackPalette.hue(forRow: row), brightness: brightness
            ))
        }
        lights.append((
            LaunchpadGridMapping.projectNote,
            projectViewOpen
                ? Self.colour(hue: 0.52, brightness: 0.98)
                : Self.colour(hue: 0.52, brightness: 0.12)
        ))
        lights.append((
            LaunchpadGridMapping.masterEffectsNote,
            masterEffectsViewOpen
                ? Self.colour(hue: 0.78, brightness: 0.98)
                : Self.colour(hue: 0.78, brightness: 0.12)
        ))
        lights.append((
            LaunchpadGridMapping.destructiveEffectsNote,
            destructiveEffectsViewOpen
                ? Self.colour(hue: 0.02, brightness: 0.98)
                : Self.colour(hue: 0.02, brightness: 0.12)
        ))
        lights.append((
            LaunchpadGridMapping.globalScenesNote,
            globalSceneViewOpen
                ? Self.colour(hue: 0.82, brightness: 0.98)
                : Self.colour(hue: 0.82, brightness: 0.12)
        ))
        lights.append((
            LaunchpadGridMapping.shiftNote,
            shiftHeld ? RGB(r: 127, g: 127, b: 127) : RGB(r: 14, g: 14, b: 14)
        ))
        for start in stride(from: 0, to: lights.count, by: 32) {
            var message = Self.vendorHeader + [0x03]
            for light in lights[start..<min(start + 32, lights.count)] {
                message += [
                    0x03,
                    light.note,
                    light.colour.r,
                    light.colour.g,
                    light.colour.b,
                ]
            }
            message.append(0xF7)
            send(message)
        }
    }

    fileprivate func receive(_ bytes: UnsafeBufferPointer<UInt8>) {
        var cursor = 0
        while cursor + 2 < bytes.count {
            let status = bytes[cursor] & 0xF0
            let note = bytes[cursor + 1]
            let velocity = bytes[cursor + 2]
            cursor += 3

            if let phase = LaunchpadGridMapping.projectPhase(
                note: note,
                status: status,
                value: velocity
            ) {
                eventHandler(phase == .pressed ? .projectPressed : .projectReleased)
                continue
            }
            if let phase = LaunchpadGridMapping.masterEffectsPhase(
                note: note,
                status: status,
                value: velocity
            ) {
                eventHandler(phase == .pressed ? .masterEffectsPressed : .masterEffectsReleased)
                continue
            }
            if let phase = LaunchpadGridMapping.destructiveEffectsPhase(
                note: note,
                status: status,
                value: velocity
            ) {
                eventHandler(phase == .pressed
                    ? .destructiveEffectsPressed
                    : .destructiveEffectsReleased)
                continue
            }
            if let phase = LaunchpadGridMapping.globalScenesPhase(
                note: note,
                status: status,
                value: velocity
            ) {
                eventHandler(phase == .pressed ? .globalScenesPressed : .globalScenesReleased)
                continue
            }
            if let phase = LaunchpadGridMapping.shiftPhase(
                note: note,
                status: status,
                value: velocity
            ) {
                eventHandler(phase == .pressed ? .shiftPressed : .shiftReleased)
                continue
            }
            if let row = LaunchpadGridMapping.auxiliaryRow(for: note) {
                // In Programmer mode the eight right-side scene buttons use
                // Control Change, whereas the 8x8 matrix uses Note messages.
                if LaunchpadGridMapping.auxiliaryPhase(status: status, value: velocity) == .pressed {
                    eventHandler(.auxiliaryPressed(row: row))
                } else if LaunchpadGridMapping.auxiliaryPhase(
                    status: status, value: velocity
                ) == .released {
                    eventHandler(.auxiliaryReleased(row: row))
                }
                continue
            }
            guard let coordinate = LaunchpadGridMapping.coordinate(for: note) else { continue }
            if status == 0x90, velocity > 0 {
                eventHandler(.pressed(coordinate, velocity: velocity))
            } else if status == 0x80 || (status == 0x90 && velocity == 0) {
                eventHandler(.released(coordinate))
            }
        }
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(
            endpoint,
            kMIDIPropertyDisplayName,
            &unmanagedName
        ) == noErr else { return nil }
        return unmanagedName?.takeRetainedValue() as String?
    }

    private func isProgrammerEndpoint(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("launchpad")
            && name.localizedCaseInsensitiveContains("midi")
            && !name.localizedCaseInsensitiveContains("daw")
    }

    private func send(_ bytes: [UInt8]) {
        guard outputPort != 0, destination != 0, !bytes.isEmpty else { return }
        var packetList = MIDIPacketList()
        bytes.withUnsafeBufferPointer { byteBuffer in
            withUnsafeMutablePointer(to: &packetList) { packetListPointer in
                let packet = MIDIPacketListInit(packetListPointer)
                _ = MIDIPacketListAdd(
                    packetListPointer,
                    MemoryLayout<MIDIPacketList>.size,
                    packet,
                    0,
                    byteBuffer.count,
                    byteBuffer.baseAddress!
                )
                MIDISend(outputPort, destination, packetListPointer)
            }
        }
    }

    private static let vendorHeader: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D]
    private static let programmerModeMessage = vendorHeader + [0x0E, 0x01, 0xF7]
    private static let liveModeMessage = vendorHeader + [0x0E, 0x00, 0xF7]

    private struct RGB {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    private static func colour(hue: Double, brightness: Double) -> RGB {
        let sector = hue * 6
        let fraction = sector - floor(sector)
        let value = max(0, min(1, brightness))
        let saturation = 0.88
        let low = value * (1 - saturation)
        let falling = value * (1 - saturation * fraction)
        let rising = value * (1 - saturation * (1 - fraction))
        let components: (Double, Double, Double)

        switch Int(sector) % 6 {
        case 0: components = (value, rising, low)
        case 1: components = (falling, value, low)
        case 2: components = (low, value, rising)
        case 3: components = (low, falling, value)
        case 4: components = (rising, low, value)
        default: components = (value, low, falling)
        }

        return RGB(
            r: UInt8((components.0 * 127).rounded()),
            g: UInt8((components.1 * 127).rounded()),
            b: UInt8((components.2 * 127).rounded())
        )
    }
}

private let launchpadMIDIRead: MIDIReadProc = { packetList, refCon, _ in
    guard let refCon else { return }
    let controller = Unmanaged<LaunchpadController>.fromOpaque(refCon).takeUnretainedValue()
    var packet = packetList.pointee.packet

    for _ in 0..<packetList.pointee.numPackets {
        withUnsafeBytes(of: packet.data) { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            controller.receive(
                UnsafeBufferPointer(start: bytes.baseAddress, count: Int(packet.length))
            )
        }
        packet = MIDIPacketNext(&packet).pointee
    }
}
