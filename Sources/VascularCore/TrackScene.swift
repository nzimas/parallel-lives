public struct TrackScene: Codable, Equatable, Sendable {
    public let vessels: [VesselGraph]
    public let volume: Double
    public let pan: Double
    public let sends: TrackSendLevels
    public let gate: Double
    public let generatorLock: GeneratorLock?
    public let chainLock: TrackChainLock?
    public let harmonicAnchor: HarmonicAnchor?

    public init(
        vessels: [VesselGraph],
        volume: Double,
        pan: Double,
        sends: TrackSendLevels,
        gate: Double,
        generatorLock: GeneratorLock?,
        chainLock: TrackChainLock? = nil,
        harmonicAnchor: HarmonicAnchor?
    ) {
        self.vessels = vessels
        self.volume = volume
        self.pan = pan
        self.sends = sends
        self.gate = gate
        self.generatorLock = generatorLock
        self.chainLock = chainLock
        self.harmonicAnchor = harmonicAnchor
    }

    private enum CodingKeys: String, CodingKey {
        case vessels, volume, pan, sends, gate, generatorLock, chainLock, harmonicAnchor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        vessels = try values.decode([VesselGraph].self, forKey: .vessels)
        volume = try values.decode(Double.self, forKey: .volume)
        pan = try values.decode(Double.self, forKey: .pan)
        sends = try values.decode(TrackSendLevels.self, forKey: .sends)
        gate = try values.decode(Double.self, forKey: .gate)
        generatorLock = try values.decodeIfPresent(GeneratorLock.self, forKey: .generatorLock)
        chainLock = try values.decodeIfPresent(TrackChainLock.self, forKey: .chainLock)
        harmonicAnchor = try values.decodeIfPresent(HarmonicAnchor.self, forKey: .harmonicAnchor)
    }
}

public struct TrackSceneBank: Codable, Equatable, Sendable {
    public static let trackCount = 8
    public static let slotsPerTrack = 8
    public var scenes: [Int: [Int: TrackScene]]

    public init(scenes: [Int: [Int: TrackScene]] = [:]) {
        self.scenes = scenes
    }

    public func scene(track: Int, slot: Int) -> TrackScene? {
        guard (0..<Self.trackCount).contains(track),
              (0..<Self.slotsPerTrack).contains(slot) else { return nil }
        return scenes[track]?[slot]
    }

    public mutating func setScene(_ scene: TrackScene, track: Int, slot: Int) {
        guard (0..<Self.trackCount).contains(track),
              (0..<Self.slotsPerTrack).contains(slot) else { return }
        scenes[track, default: [:]][slot] = scene
    }

    public func occupiedSlots(track: Int) -> Set<Int> {
        guard let trackScenes = scenes[track] else { return [] }
        return Set(trackScenes.keys)
    }
}
