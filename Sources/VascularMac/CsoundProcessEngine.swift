import Foundation
import VascularCore

actor CsoundProcessEngine: AudioEngine {
    enum EngineError: LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let path): "Bundled Csound resource is missing: \(path)"
            }
        }
    }

    private struct StageSpec {
        let vesselID: VesselGraph.ID
        let node: ProcessorNode
        var inputBuses: [Int]
        let outputBus: Int
        let fundamentalHz: Double
    }

    private struct ProcessorRuntime {
        let processorVoice: String
        let inputBuses: [Int]
        let outputBus: Int
        let fundamentalHz: Double
        let kind: ProcessorKind
        let intensity: Double
        let seed: UInt64
    }

    private struct OutputRuntime {
        let voice: String
        let bus: Int
        let track: Int
    }

    private var host: EmbeddedCsoundHost?
    private var rootVoices: [VesselGraph.ID: String] = [:]
    private var rootBuses: [VesselGraph.ID: Int] = [:]
    private var nodeBuses: [ProcessorNode.ID: Int] = [:]
    private var processorStates: [ProcessorNode.ID: ProcessorRuntime] = [:]
    private var outputStates: [VesselGraph.ID: OutputRuntime] = [:]
    private var nextVoiceSerial: UInt64 = 1
    private var nextBus = 1
    private var freeBuses: [Int] = []
    private var busGeneration: UInt64 = 0
    // The dynamic Zak graph requires strict read/write/clear ordering. Csound's
    // multicore scheduler improved offline throughput but is not safe for this
    // live routing architecture; parallelism will return with isolated engines.
    private let renderThreadCount = 1
    private let zakBusCapacity = 256
    private let initialTerminalWarmup = 0.02
    private let terminalWarmup = 0.26
    private let retiredGraphDelay = 0.64
    private var trackVolumes = Array(repeating: TrackMixer.defaultVolume, count: 8)
    private var trackPans = Array(repeating: TrackMixer.defaultPan, count: 8)
    private var trackSends = Array(repeating: TrackSendLevels.zero, count: 8)
    private var trackGates = Array(repeating: TrackMixer.defaultGate, count: 8)
    private var masterEffects = MasterEffectParameters.defaults
    private var destructiveEffects = DestructiveEffectParameters.defaults

    func synchronize(_ vessels: [VesselGraph]) async throws {
        guard !vessels.isEmpty else {
            stopGraph(gracefully: true)
            writeDiagnostics(vessels: [], roots: [], stages: [], leaves: [])
            return
        }

        try startIfNeeded()
        let roots = vessels.filter { $0.parentVesselIDs.isEmpty }
        let fundamentalByRoot = Dictionary(
            uniqueKeysWithValues: roots.map { ($0.id, $0.sourceFundamentalHz) }
        )
        let liveRootIDs = Set(roots.map(\.id))
        for root in roots where rootVoices[root.id] == nil {
            try activateSource(root)
        }

        var terminalBusByVessel: [VesselGraph.ID: Int] = [:]
        var stages: [StageSpec] = []

        for vessel in vessels {
            var inputs = vessel.parentVesselIDs.compactMap { terminalBusByVessel[$0] }
            if inputs.isEmpty, let sourceBus = rootBuses[vessel.rootVesselID] {
                inputs = [sourceBus]
            }

            for node in vessel.processors {
                let outputBus = bus(for: node.id)
                stages.append(StageSpec(
                    vesselID: vessel.id,
                    node: node,
                    inputBuses: inputs,
                    outputBus: outputBus,
                    fundamentalHz: fundamentalByRoot[vessel.rootVesselID]
                        ?? vessel.sourceFundamentalHz
                ))
                inputs = [outputBus]
            }
            if let terminal = inputs.first { terminalBusByVessel[vessel.id] = terminal }
        }

        let liveNodeIDs = Set(stages.map { $0.node.id })
        for stage in stages {
            if let current = processorStates[stage.node.id],
               current.inputBuses == stage.inputBuses,
               current.outputBus == stage.outputBus,
               current.fundamentalHz == stage.fundamentalHz,
               current.kind == stage.node.kind,
               current.intensity == stage.node.intensity,
               current.seed == stage.node.seed {
                continue
            }
            if let current = processorStates[stage.node.id] {
                try? stop(current.processorVoice)
            }
            processorStates[stage.node.id] = try activateProcessor(stage)
        }

        let parentIDs = Set(vessels.flatMap(\.parentVesselIDs))
        let leaves = vessels.filter { !parentIDs.contains($0.id) }
        var desiredOutputRoots: Set<VesselGraph.ID> = []
        for leaf in leaves {
            guard let terminalBus = terminalBusByVessel[leaf.id] else { continue }
            let rootID = leaf.rootVesselID
            desiredOutputRoots.insert(rootID)
            let track = leaf.source.row
            if let current = outputStates[rootID],
               current.bus == terminalBus,
               current.track == track {
                continue
            }
            let outputWarmup = outputStates[rootID] == nil
                ? initialTerminalWarmup
                : terminalWarmup
            let newOutput = try activateOutput(
                bus: terminalBus,
                track: track,
                gain: 0.48,
                after: outputWarmup
            )
            if let current = outputStates[rootID] {
                try? stop(current.voice, after: terminalWarmup)
            }
            outputStates[rootID] = newOutput
        }

        for rootID in Array(outputStates.keys) where !desiredOutputRoots.contains(rootID) {
            if let output = outputStates.removeValue(forKey: rootID) {
                try? stop(output.voice, after: terminalWarmup)
            }
        }

        // Keep removed downstream processors alive until the previous terminal's
        // release ramp has completed. This prevents a trim from cutting its fade.
        for nodeID in Array(processorStates.keys) where !liveNodeIDs.contains(nodeID) {
            if let state = processorStates.removeValue(forKey: nodeID) {
                try? stop(state.processorVoice, after: retiredGraphDelay)
            }
            if let bus = nodeBuses.removeValue(forKey: nodeID) {
                recycleBus(bus, after: retiredGraphDelay + 0.08)
            }
        }

        for rootID in Array(rootVoices.keys) where !liveRootIDs.contains(rootID) {
            if let voice = rootVoices.removeValue(forKey: rootID) {
                try? stop(voice, after: retiredGraphDelay)
            }
            if let bus = rootBuses.removeValue(forKey: rootID) {
                recycleBus(bus, after: retiredGraphDelay + 0.08)
            }
        }

        writeDiagnostics(vessels: vessels, roots: roots, stages: stages, leaves: leaves)
    }

    func setTrackMix(
        row: Int,
        volume: Double,
        pan: Double,
        sends: TrackSendLevels,
        gate: Double
    ) async throws {
        guard trackVolumes.indices.contains(row) else { return }
        trackVolumes[row] = max(0, min(1, volume))
        trackPans[row] = max(-1, min(1, pan))
        trackSends[row] = TrackSendLevels(
            reverb: clampedSend(sends.reverb),
            delay: clampedSend(sends.delay),
            saturation: clampedSend(sends.saturation),
            crusher: clampedSend(sends.crusher)
        )
        trackGates[row] = max(-1, min(1, gate))
        guard host?.isRunning == true else { return }
        try sendTrackMix(row: row)
    }

    func setMasterEffects(_ parameters: MasterEffectParameters) async throws {
        masterEffects = MasterEffectParameters(
            reverbSize: parameters.reverbSize,
            reverbDecay: parameters.reverbDecay,
            reverbTone: parameters.reverbTone,
            reverbMotion: parameters.reverbMotion,
            delayTime: parameters.delayTime,
            delayFeedback: parameters.delayFeedback,
            delayTone: parameters.delayTone,
            delayWidth: parameters.delayWidth
        )
        guard host?.isRunning == true else { return }
        try sendMasterEffects()
    }

    func setDestructiveEffects(_ parameters: DestructiveEffectParameters) async throws {
        destructiveEffects = DestructiveEffectParameters(
            saturationDrive: parameters.saturationDrive,
            saturationCurve: parameters.saturationCurve,
            saturationTone: parameters.saturationTone,
            saturationBody: parameters.saturationBody,
            crusherBits: parameters.crusherBits,
            crusherRate: parameters.crusherRate,
            crusherJitter: parameters.crusherJitter,
            crusherTone: parameters.crusherTone
        )
        guard host?.isRunning == true else { return }
        try sendDestructiveEffects()
    }

    private func clampedSend(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func activateSource(_ root: VesselGraph) throws {
        let voice = makeVoice(instrument: 100)
        let bus = rootBuses[root.id] ?? allocateBus()
        rootBuses[root.id] = bus
        let family = SourceFamily.allCases.firstIndex(of: root.sourceFamily) ?? 0
        let pitchSeed = csoundSeed(root.sourceSeed, salt: 0xA0761D6478BD642F)
        let variationSeed = csoundSeed(root.sourceSeed, salt: 0xE7037ED1A0B428DB)
        let sourceDepth = 0.52 + Double(csoundSeed(
            root.sourceSeed, salt: 0x8EBC6AF09C88C6E3
        ) % 10_001) / 10_000 * 0.44
        let fields = [
            "i", voice, "0", "-1", String(family), String(sourceDepth),
            String(pitchSeed), String(variationSeed), String(root.sourceFundamentalHz),
            String(bus),
        ]
        try send(fields.joined(separator: " ") + "\n")
        rootVoices[root.id] = voice
    }

    private func activateProcessor(_ stage: StageSpec) throws -> ProcessorRuntime {
        guard let inputBus = stage.inputBuses.first else {
            preconditionFailure("A track processor has no upstream bus")
        }

        let voice = makeVoice(instrument: 200)
        let kind = ProcessorKind.allCases.firstIndex(of: stage.node.kind) ?? 0
        let seed = (stage.node.seed % 2_000_000_000) + 1
        let fields = [
            "i", voice, "0", "-1", String(kind), String(stage.node.intensity),
            String(seed), String(inputBus), String(stage.outputBus),
            String(stage.fundamentalHz),
        ]
        try send(fields.joined(separator: " ") + "\n")
        return ProcessorRuntime(
            processorVoice: voice,
            inputBuses: stage.inputBuses,
            outputBus: stage.outputBus,
            fundamentalHz: stage.fundamentalHz,
            kind: stage.node.kind,
            intensity: stage.node.intensity,
            seed: stage.node.seed
        )
    }

    private func activateOutput(
        bus: Int,
        track: Int,
        gain: Double,
        after delay: Double
    ) throws -> OutputRuntime {
        let voice = makeVoice(instrument: 800)
        let fields = [
            "i", voice, String(delay), "-1", String(bus), String(track), String(gain),
        ]
        try send(fields.joined(separator: " ") + "\n")
        return OutputRuntime(voice: voice, bus: bus, track: track)
    }

    private func makeVoice(instrument: Int) -> String {
        defer { nextVoiceSerial &+= 1 }
        return String(format: "%d.%09llu", instrument, nextVoiceSerial)
    }

    private func bus(for nodeID: ProcessorNode.ID) -> Int {
        if let existing = nodeBuses[nodeID] { return existing }
        let new = allocateBus()
        nodeBuses[nodeID] = new
        return new
    }

    private func allocateBus() -> Int {
        if let recycled = freeBuses.popLast() { return recycled }
        precondition(nextBus < zakBusCapacity, "Csound flow bus capacity exhausted")
        defer { nextBus += 1 }
        return nextBus
    }

    private func recycleBus(_ bus: Int, after delay: Double) {
        let generation = busGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.makeBusAvailable(bus, generation: generation)
        }
    }

    private func makeBusAvailable(_ bus: Int, generation: UInt64) {
        guard generation == busGeneration, !freeBuses.contains(bus) else { return }
        freeBuses.append(bus)
    }

    private func csoundSeed(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var value = seed ^ salt
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return (value % 2_000_000_000) + 1
    }

    private func stop(_ voice: String, after delay: Double = 0) throws {
        try send("i -\(voice) \(delay) 0\n")
    }

    private func stopGraph(gracefully: Bool) {
        let downstreamDelay = gracefully ? retiredGraphDelay : 0
        for output in outputStates.values { try? stop(output.voice) }
        for state in processorStates.values {
            try? stop(state.processorVoice, after: downstreamDelay)
        }
        for voice in rootVoices.values { try? stop(voice, after: downstreamDelay) }
        outputStates.removeAll()
        processorStates.removeAll()
        rootVoices.removeAll()
        let buses = Array(rootBuses.values) + Array(nodeBuses.values)
        rootBuses.removeAll()
        nodeBuses.removeAll()
        if gracefully {
            for bus in buses { recycleBus(bus, after: retiredGraphDelay + 0.08) }
        }
    }

    func panic() async {
        stopGraph(gracefully: false)
        terminateProcess()
    }

    private func startIfNeeded() throws {
        if host?.isRunning == true { return }
        rootVoices.removeAll()
        processorStates.removeAll()
        outputStates.removeAll()
        resetBusAllocator()

        let resources = applicationResourceBundle
        guard let runtimeURL = resources.resourceURL?.appending(path: "Runtime"),
              FileManager.default.fileExists(atPath: runtimeURL.path) else {
            throw EngineError.missingResource("Runtime")
        }
        guard let orchestraURL = resources.url(
            forResource: "Vascular",
            withExtension: "csd",
            subdirectory: "Orchestra"
        ) else {
            throw EngineError.missingResource("Orchestra/Vascular.csd")
        }

        host = try EmbeddedCsoundHost(runtimeURL: runtimeURL, orchestraURL: orchestraURL)
        for row in trackVolumes.indices { try sendTrackMix(row: row) }
        try sendMasterEffects()
        try sendDestructiveEffects()
    }

    private func terminateProcess() {
        host?.stop()
        host = nil
        resetBusAllocator()
    }

    private func resetBusAllocator() {
        busGeneration &+= 1
        rootBuses.removeAll()
        nodeBuses.removeAll()
        freeBuses.removeAll()
        nextBus = 1
    }

    private func sendTrackMix(row: Int) throws {
        let sends = trackSends[row]
        try send([
            "i", "700", "0", "0.01", String(row),
            String(trackVolumes[row]), String(trackPans[row]),
            String(sends.reverb), String(sends.delay),
            String(sends.saturation), String(sends.crusher),
            String(trackGates[row]),
        ].joined(separator: " ") + "\n")
    }

    private func sendMasterEffects() throws {
        try send([
            "i", "710", "0", "0.01",
            String(masterEffects.reverbSize),
            String(masterEffects.reverbDecay),
            String(masterEffects.reverbTone),
            String(masterEffects.reverbMotion),
            String(masterEffects.delayTime),
            String(masterEffects.delayFeedback),
            String(masterEffects.delayTone),
            String(masterEffects.delayWidth),
        ].joined(separator: " ") + "\n")
    }

    private func sendDestructiveEffects() throws {
        try send([
            "i", "720", "0", "0.01",
            String(destructiveEffects.saturationDrive),
            String(destructiveEffects.saturationCurve),
            String(destructiveEffects.saturationTone),
            String(destructiveEffects.saturationBody),
            String(destructiveEffects.crusherBits),
            String(destructiveEffects.crusherRate),
            String(destructiveEffects.crusherJitter),
            String(destructiveEffects.crusherTone),
        ].joined(separator: " ") + "\n")
    }

    private var applicationResourceBundle: Bundle {
        if let resourcesURL = Bundle.main.resourceURL?
            .appending(path: "Vascular_VascularMac.bundle"),
           let applicationBundle = Bundle(url: resourcesURL) {
            return applicationBundle
        }
        return Bundle.module
    }

    private func send(_ message: String) throws {
        host?.inputMessage(message)
    }

    private func writeDiagnostics(
        vessels: [VesselGraph],
        roots: [VesselGraph],
        stages: [StageSpec],
        leaves: [VesselGraph]
    ) {
        let payload: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "renderThreads": renderThreadCount,
            "audioBuses": [
                "capacity": zakBusCapacity,
                "highWater": nextBus - 1,
                "live": rootBuses.count + nodeBuses.count,
                "recycled": freeBuses.count,
            ],
            "vesselCount": vessels.count,
            "rootSourceCount": roots.count,
            "rootSources": roots.map {
                [
                    "rootVessel": $0.id.uuidString,
                    "sourcePad": $0.source.index + 1,
                    "sourceFamily": $0.sourceFamily.rawValue,
                    "processingArchetype": processingArchetype(for: $0.sourceSeed),
                    "fundamentalHz": $0.sourceFundamentalHz,
                    "bus": rootBuses[$0.id] ?? -1,
                    "voice": rootVoices[$0.id] ?? "missing",
                ] as [String: Any]
            },
            "processorCount": stages.count,
            "processors": stages.enumerated().map { offset, stage in
                [
                    "stage": offset + 1,
                    "node": stage.node.id.uuidString,
                    "vessel": stage.vesselID.uuidString,
                    "pad": stage.node.coordinate.index + 1,
                    "opcode": stage.node.kind.rawValue,
                    "intensity": stage.node.intensity,
                    "inputBuses": stage.inputBuses,
                    "outputBus": stage.outputBus,
                    "fundamentalHz": stage.fundamentalHz,
                    "voice": processorStates[stage.node.id]?.processorVoice ?? "missing",
                ] as [String: Any]
            },
            "leafVessels": leaves.map(\.id.uuidString),
            "masterEffects": [
                "reverbSize": masterEffects.reverbSize,
                "reverbDecay": masterEffects.reverbDecay,
                "reverbTone": masterEffects.reverbTone,
                "reverbMotion": masterEffects.reverbMotion,
                "delayTime": masterEffects.delayTime,
                "delayFeedback": masterEffects.delayFeedback,
                "delayTone": masterEffects.delayTone,
                "delayWidth": masterEffects.delayWidth,
            ],
            "destructiveEffects": [
                "saturationDrive": destructiveEffects.saturationDrive,
                "saturationCurve": destructiveEffects.saturationCurve,
                "saturationTone": destructiveEffects.saturationTone,
                "saturationBody": destructiveEffects.saturationBody,
                "crusherBits": destructiveEffects.crusherBits,
                "crusherRate": destructiveEffects.crusherRate,
                "crusherJitter": destructiveEffects.crusherJitter,
                "crusherTone": destructiveEffects.crusherTone,
            ],
            "trackOutputs": outputStates.map { rootID, output in
                [
                    "rootVessel": rootID.uuidString,
                    "bus": output.bus,
                    "track": output.track + 1,
                    "volume": trackVolumes[output.track],
                    "pan": trackPans[output.track],
                    "sends": [
                        "reverb": trackSends[output.track].reverb,
                        "delay": trackSends[output.track].delay,
                        "saturation": trackSends[output.track].saturation,
                        "crusher": trackSends[output.track].crusher,
                    ],
                    "rhythmicGate": trackGates[output.track],
                    "voice": output.voice,
                ] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ), let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let directory = support.appending(path: "Vascular", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: "current-graph.json"), options: .atomic)
    }

    private func processingArchetype(for sourceSeed: UInt64) -> String {
        [
            "temporalMutation", "spectralDisassembly", "resonantMatter",
            "deepSpace", "microsound", "controlledFracture", "hybrid",
        ][Int(sourceSeed % 7)]
    }
}
