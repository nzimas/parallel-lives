import Foundation

public struct VesselGraphFactory: Sendable {
    public init() {}

    public func make(
        source: PadCoordinate,
        destination: PadCoordinate,
        seed: UInt64,
        parentVessels: [VesselGraph] = [],
        existingProcessors: [ProcessorNode] = [],
        avoidingSourceFamilies: Set<SourceFamily> = [],
        generatorLock: GeneratorLock? = nil,
        harmonicAnchor: HarmonicAnchor? = nil,
        id: UUID = UUID()
    ) -> VesselGraph {
        precondition(
            source.row == destination.row && source.column < destination.column,
            "A track vessel must grow horizontally from left to right"
        )

        var random = SeededGenerator(seed: seed)
        let sourceFamily = parentVessels.first?.sourceFamily
            ?? generatorLock?.sourceFamily
            ?? selectSourceFamily(avoiding: avoidingSourceFamilies, using: &random)
        let sourceSeed = parentVessels.first?.sourceSeed ?? generatorLock?.sourceSeed ?? seed
        let sourceFundamentalHz = parentVessels.first?.sourceFundamentalHz
            ?? generatorLock?.fundamentalHz
            ?? harmonicAnchor.map {
                SourcePitch.relatedFundamental(
                    anchor: $0,
                    sourceSeed: sourceSeed,
                    track: source.row
                )
            }
            ?? SourcePitch.unanchoredFundamental(sourceSeed: sourceSeed)
        let route = source.gridRoute(to: destination)
        let processorCoordinates = route.dropFirst()
        var history = existingProcessors.isEmpty
            ? parentVessels.flatMap(\.processors)
            : existingProcessors
        let palette = Int(sourceSeed % 7)
        var previousKind = history.last?.kind
        var processors: [ProcessorNode] = []

        for coordinate in processorCoordinates {
            let position = history.count
            let hasDestructiveStage = history.contains { isDestructive($0.kind) }
            var weightedCandidates = ProcessorKind.allCases.compactMap { kind -> (ProcessorKind, Double)? in
                if isDestructive(kind), hasDestructiveStage || position < 2 { return nil }
                var weight = baseWeight(for: kind, palette: palette)
                if let previousKind, character(of: previousKind) == character(of: kind) {
                    weight *= 0.22
                }
                if kind == previousKind { weight *= 0.08 }
                return (kind, weight)
            }
            if weightedCandidates.isEmpty {
                weightedCandidates = ProcessorKind.allCases.map {
                    ($0, baseWeight(for: $0, palette: palette))
                }
            }
            let kind = weightedChoice(weightedCandidates, using: &random)
            let intensity: Double
            switch character(of: kind) {
            case .destructive:
                intensity = Double.random(in: 0.34...0.58, using: &random)
            case .volatile:
                intensity = Double.random(in: 0.46...0.72, using: &random)
            default:
                intensity = Double.random(in: 0.58...0.9, using: &random)
            }
            let nodeID = deterministicUUID(using: &random)
            processors.append(ProcessorNode(
                id: nodeID,
                coordinate: coordinate,
                kind: kind,
                intensity: intensity,
                seed: random.next()
            ))
            previousKind = kind
            history.append(processors.last!)
        }

        return VesselGraph(
            id: id,
            source: source,
            destination: destination,
            seed: seed,
            sourceSeed: sourceSeed,
            sourceFundamentalHz: sourceFundamentalHz,
            rootVesselID: parentVessels.first?.rootVesselID ?? id,
            sourceFamily: sourceFamily,
            processors: processors,
            hasAuxiliaryGenerator: false,
            parentVesselIDs: parentVessels.map(\.id)
        )
    }

    private enum Character {
        case spectral, temporal, spatial, resonant, destructive, volatile
    }

    private func character(of kind: ProcessorKind) -> Character {
        switch kind {
        case .filterBank, .spectralFreeze: .spectral
        case .granulator, .variableDelay, .flanger: .temporal
        case .animatedReverb, .diffuser, .phaser: .spatial
        case .resonatorBank, .ringModulator: .resonant
        case .waveshaper, .overdrive, .bitCrusher: .destructive
        case .convolution, .controlledFeedback: .volatile
        }
    }

    private func isDestructive(_ kind: ProcessorKind) -> Bool {
        character(of: kind) == .destructive
    }

    private func baseWeight(for kind: ProcessorKind, palette: Int) -> Double {
        let foundation: Double = switch kind {
        case .filterBank: 1.45
        case .granulator: 1.35
        case .variableDelay: 1.35
        case .animatedReverb: 1.1
        case .spectralFreeze: 0.82
        case .waveshaper: 0.32
        case .overdrive: 0.28
        case .bitCrusher: 0.16
        case .convolution: 0.48
        case .resonatorBank: 1.05
        case .ringModulator: 0.62
        case .diffuser: 1.25
        case .phaser: 1.0
        case .flanger: 0.92
        case .controlledFeedback: 0.5
        }
        let emphasis: Double
        switch palette {
        case 0: // temporal mutation
            emphasis = switch kind {
            case .variableDelay, .flanger: 3.2
            case .granulator, .phaser: 2.25
            case .animatedReverb, .diffuser: 1.45
            default: 0.38
            }
        case 1: // spectral disassembly
            emphasis = switch kind {
            case .spectralFreeze, .filterBank: 3.3
            case .resonatorBank, .ringModulator, .convolution: 1.8
            default: 0.34
            }
        case 2: // resonant matter
            emphasis = switch kind {
            case .resonatorBank, .filterBank: 3.4
            case .ringModulator, .controlledFeedback: 2.0
            case .diffuser: 1.25
            default: 0.35
            }
        case 3: // deep space
            emphasis = switch kind {
            case .animatedReverb, .diffuser: 3.5
            case .variableDelay, .flanger, .phaser: 1.9
            default: 0.3
            }
        case 4: // microsound
            emphasis = switch kind {
            case .granulator: 4.2
            case .variableDelay, .filterBank: 2.2
            case .spectralFreeze, .flanger: 1.35
            default: 0.3
            }
        case 5: // controlled fracture: one nonlinear event, never a whole chain
            emphasis = switch kind {
            case .waveshaper, .overdrive, .bitCrusher: 4.5
            case .filterBank, .variableDelay: 1.9
            case .convolution, .controlledFeedback: 1.35
            default: 0.42
            }
        default: // heterogeneous hybrid
            emphasis = 1
        }
        return foundation * emphasis
    }

    private func selectSourceFamily(
        avoiding: Set<SourceFamily>,
        using random: inout SeededGenerator
    ) -> SourceFamily {
        let available = SourceFamily.allCases.filter { !avoiding.contains($0) }
        let pool = available.isEmpty ? SourceFamily.allCases : available
        return weightedChoice(pool.map { ($0, sourceWeight(for: $0)) }, using: &random)
    }

    private func sourceWeight(for family: SourceFamily) -> Double {
        switch family {
        case .granularCloud: 1.35
        case .spectralResidue: 0.72
        case .stochasticImpulses: 0.62
        case .resonantBody: 1.15
        case .feedbackExciter: 0.78
        case .recursiveOscillator: 1.2
        case .pulsarTrain: 0.95
        case .frequencyModulation: 1.2
        case .waveTerrain: 1.3
        case .additiveCluster: 1.35
        case .noiseBands: 0.58
        case .resonantSwarm: 0.82
        case .karplusStrong: 1.55
        case .preparedString: 1.3
        case .struckPlate: 1.2
        case .struckMembrane: 1.2
        case .bowedBody: 1.15
        case .reedBore: 1.05
        case .glassBowl: 1.15
        case .woodenBody: 1.15
        }
    }

    private func weightedChoice<T>(
        _ choices: [(T, Double)],
        using random: inout SeededGenerator
    ) -> T {
        let total = choices.reduce(0) { $0 + $1.1 }
        var cursor = Double.random(in: 0..<total, using: &random)
        for (choice, weight) in choices {
            cursor -= weight
            if cursor < 0 { return choice }
        }
        return choices.last!.0
    }

    private func deterministicUUID(using random: inout SeededGenerator) -> UUID {
        let high = random.next()
        let low = random.next()
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: high >> 56), UInt8(truncatingIfNeeded: high >> 48),
            UInt8(truncatingIfNeeded: high >> 40), UInt8(truncatingIfNeeded: high >> 32),
            UInt8(truncatingIfNeeded: high >> 24), UInt8(truncatingIfNeeded: high >> 16),
            UInt8(truncatingIfNeeded: high >> 8), UInt8(truncatingIfNeeded: high),
            UInt8(truncatingIfNeeded: low >> 56), UInt8(truncatingIfNeeded: low >> 48),
            UInt8(truncatingIfNeeded: low >> 40), UInt8(truncatingIfNeeded: low >> 32),
            UInt8(truncatingIfNeeded: low >> 24), UInt8(truncatingIfNeeded: low >> 16),
            UInt8(truncatingIfNeeded: low >> 8), UInt8(truncatingIfNeeded: low),
        ]
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
