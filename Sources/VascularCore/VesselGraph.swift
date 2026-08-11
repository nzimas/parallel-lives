import Foundation

public enum SourceFamily: String, Codable, CaseIterable, Sendable {
    case granularCloud
    case spectralResidue
    case stochasticImpulses
    case resonantBody
    case feedbackExciter
    case recursiveOscillator
    case pulsarTrain
    case frequencyModulation
    case waveTerrain
    case additiveCluster
    case noiseBands
    case resonantSwarm
    // Appended to preserve the Csound family indices used by existing scenes
    // and projects. These are distinct acoustic/physical models, rather than
    // parameter presets for the earlier oscillator sources.
    case karplusStrong
    case preparedString
    case struckPlate
    case struckMembrane
    case bowedBody
    case reedBore
    case glassBowl
    case woodenBody
}

public enum ProcessorKind: String, Codable, CaseIterable, Sendable {
    case filterBank
    case granulator
    case variableDelay
    case animatedReverb
    case spectralFreeze
    case waveshaper
    case overdrive
    case bitCrusher
    case convolution
    case resonatorBank
    case ringModulator
    case diffuser
    case phaser
    case flanger
    case controlledFeedback
}

public struct ProcessorNode: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let coordinate: PadCoordinate
    public let kind: ProcessorKind
    public let intensity: Double
    public let seed: UInt64

    public init(
        id: UUID = UUID(),
        coordinate: PadCoordinate,
        kind: ProcessorKind,
        intensity: Double,
        seed: UInt64
    ) {
        self.id = id
        self.coordinate = coordinate
        self.kind = kind
        self.intensity = intensity
        self.seed = seed
    }
}

public struct VesselGraph: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let source: PadCoordinate
    public let destination: PadCoordinate
    public let seed: UInt64
    public let sourceSeed: UInt64
    public let sourceFundamentalHz: Double
    public let rootVesselID: UUID
    public let sourceFamily: SourceFamily
    public let processors: [ProcessorNode]
    public let hasAuxiliaryGenerator: Bool
    public let parentVesselIDs: [UUID]

    public var isExtension: Bool { !parentVesselIDs.isEmpty }

    public init(
        id: UUID = UUID(),
        source: PadCoordinate,
        destination: PadCoordinate,
        seed: UInt64,
        sourceSeed: UInt64? = nil,
        sourceFundamentalHz: Double? = nil,
        rootVesselID: UUID? = nil,
        sourceFamily: SourceFamily,
        processors: [ProcessorNode],
        hasAuxiliaryGenerator: Bool,
        parentVesselIDs: [UUID] = []
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.seed = seed
        self.sourceSeed = sourceSeed ?? seed
        self.sourceFundamentalHz = sourceFundamentalHz
            ?? SourcePitch.unanchoredFundamental(sourceSeed: sourceSeed ?? seed)
        self.rootVesselID = rootVesselID ?? id
        self.sourceFamily = sourceFamily
        self.processors = processors
        self.hasAuxiliaryGenerator = hasAuxiliaryGenerator
        self.parentVesselIDs = parentVesselIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, destination, seed, sourceSeed, sourceFundamentalHz
        case rootVesselID, sourceFamily, processors, hasAuxiliaryGenerator, parentVesselIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        source = try values.decode(PadCoordinate.self, forKey: .source)
        destination = try values.decode(PadCoordinate.self, forKey: .destination)
        seed = try values.decode(UInt64.self, forKey: .seed)
        sourceSeed = try values.decodeIfPresent(UInt64.self, forKey: .sourceSeed) ?? seed
        sourceFundamentalHz = try values.decodeIfPresent(
            Double.self,
            forKey: .sourceFundamentalHz
        ) ?? SourcePitch.unanchoredFundamental(sourceSeed: sourceSeed)
        rootVesselID = try values.decodeIfPresent(UUID.self, forKey: .rootVesselID) ?? id
        sourceFamily = try values.decode(SourceFamily.self, forKey: .sourceFamily)
        processors = try values.decode([ProcessorNode].self, forKey: .processors)
        hasAuxiliaryGenerator = try values.decode(
            Bool.self,
            forKey: .hasAuxiliaryGenerator
        )
        parentVesselIDs = try values.decodeIfPresent(
            [UUID].self,
            forKey: .parentVesselIDs
        ) ?? []
    }
}
