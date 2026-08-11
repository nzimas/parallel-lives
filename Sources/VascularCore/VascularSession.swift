import Foundation

public struct GeneratorLock: Codable, Equatable, Sendable {
    public let sourceSeed: UInt64
    public let sourceFamily: SourceFamily
    public let fundamentalHz: Double

    public init(sourceSeed: UInt64, sourceFamily: SourceFamily, fundamentalHz: Double? = nil) {
        self.sourceSeed = sourceSeed
        self.sourceFamily = sourceFamily
        self.fundamentalHz = fundamentalHz
            ?? SourcePitch.unanchoredFundamental(sourceSeed: sourceSeed)
    }

    private enum CodingKeys: String, CodingKey {
        case sourceSeed, sourceFamily, fundamentalHz
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourceSeed = try values.decode(UInt64.self, forKey: .sourceSeed)
        sourceFamily = try values.decode(SourceFamily.self, forKey: .sourceFamily)
        fundamentalHz = try values.decodeIfPresent(Double.self, forKey: .fundamentalHz)
            ?? SourcePitch.unanchoredFundamental(sourceSeed: sourceSeed)
    }
}

public struct TrackChainLock: Codable, Equatable, Sendable {
    public let vessels: [VesselGraph]
    public let endpointColumn: Int
    public let generatorLock: GeneratorLock

    public init(
        vessels: [VesselGraph],
        endpointColumn: Int,
        generatorLock: GeneratorLock
    ) {
        self.vessels = vessels
        self.endpointColumn = max(1, min(7, endpointColumn))
        self.generatorLock = generatorLock
    }

    public func matchesLivePrefix(in liveVessels: [VesselGraph], row: Int) -> Bool {
        let trackVessels = liveVessels.filter { $0.source.row == row }
        guard let liveEndpoint = trackVessels.map(\.destination.column).max(),
              liveEndpoint >= endpointColumn else { return false }
        let prefix = TrackTopology(vessels: trackVessels).trimmingTrack(
            row: row,
            endingAt: PadCoordinate(row: row, column: endpointColumn)
        )
        return prefix == vessels
    }
}

public struct VascularSession: Codable, Equatable, Sendable {
    public var vessels: [VesselGraph]
    public var nextSeed: UInt64
    public var generatorLocks: [Int: GeneratorLock]
    public var chainLocks: [Int: TrackChainLock]
    public var harmonicAnchor: HarmonicAnchor?

    public init(
        vessels: [VesselGraph] = [],
        nextSeed: UInt64? = nil,
        generatorLocks: [Int: GeneratorLock] = [:],
        chainLocks: [Int: TrackChainLock] = [:],
        harmonicAnchor: HarmonicAnchor? = nil
    ) {
        self.vessels = vessels
        self.generatorLocks = generatorLocks
        self.chainLocks = chainLocks
        self.harmonicAnchor = harmonicAnchor
        if let nextSeed {
            self.nextSeed = nextSeed == 0 ? 0xA0761D6478BD642F : nextSeed
        } else {
            var entropy = SystemRandomNumberGenerator()
            let value = entropy.next()
            self.nextSeed = value == 0 ? 0xA0761D6478BD642F : value
        }
    }

    /// Advances the session stream and returns an avalanche-mixed seed. Adjacent
    /// vessels therefore never expose adjacent integers to Csound.
    public mutating func drawSeed() -> UInt64 {
        nextSeed &+= 0x9E3779B97F4A7C15
        var value = nextSeed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return value == 0 ? 0xD1B54A32D192ED03 : value
    }

    private enum CodingKeys: String, CodingKey {
        case vessels, nextSeed, generatorLocks, chainLocks, harmonicAnchor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        vessels = try values.decode([VesselGraph].self, forKey: .vessels)
        nextSeed = try values.decode(UInt64.self, forKey: .nextSeed)
        generatorLocks = try values.decodeIfPresent(
            [Int: GeneratorLock].self,
            forKey: .generatorLocks
        ) ?? [:]
        chainLocks = try values.decodeIfPresent(
            [Int: TrackChainLock].self,
            forKey: .chainLocks
        ) ?? [:]
        harmonicAnchor = try values.decodeIfPresent(HarmonicAnchor.self, forKey: .harmonicAnchor)
    }
}
