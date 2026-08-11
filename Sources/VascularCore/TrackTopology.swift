public enum TrackRuleViolation: String, Equatable, Sendable {
    case generatorMustBeHeld
    case mustStayOnSameTrack
    case targetMustBeToRightOfGenerator
}

public enum TrackManagementAction: Equatable, Sendable {
    case create
    case extend(parent: VesselGraph)
    case trim
    case clear
    case rejected(TrackRuleViolation)
}

/// Eight independent tracks managed from their permanent leftmost generator pad.
public struct TrackTopology: Sendable {
    public let vessels: [VesselGraph]

    public init(vessels: [VesselGraph]) {
        self.vessels = vessels
    }

    public func managementAction(
        from generator: PadCoordinate,
        to target: PadCoordinate
    ) -> TrackManagementAction {
        guard generator.column == 0 else {
            return .rejected(.generatorMustBeHeld)
        }
        guard generator.row == target.row else {
            return .rejected(.mustStayOnSameTrack)
        }
        guard target.column > generator.column else {
            return .rejected(.targetMustBeToRightOfGenerator)
        }

        let trackVessels = vessels.filter { $0.source.row == generator.row }
        guard !trackVessels.isEmpty else { return .create }

        let parentIDs = Set(trackVessels.flatMap(\.parentVesselIDs))
        guard let terminal = trackVessels.last(where: { !parentIDs.contains($0.id) }) else {
            return .rejected(.generatorMustBeHeld)
        }

        if target == terminal.destination { return .clear }
        if target.column < terminal.destination.column { return .trim }
        return .extend(parent: terminal)
    }

    /// Removes all processing to the right of `target`, retaining UUIDs, seeds,
    /// source identity, and every processor that remains on the track.
    public func trimmingTrack(
        row: Int,
        endingAt target: PadCoordinate
    ) -> [VesselGraph] {
        precondition(target.row == row && target.column > 0)

        return vessels.compactMap { vessel in
            guard vessel.source.row == row else { return vessel }
            if vessel.destination.column <= target.column { return vessel }
            guard vessel.source.column < target.column else { return nil }

            return VesselGraph(
                id: vessel.id,
                source: vessel.source,
                destination: target,
                seed: vessel.seed,
                sourceSeed: vessel.sourceSeed,
                sourceFundamentalHz: vessel.sourceFundamentalHz,
                rootVesselID: vessel.rootVesselID,
                sourceFamily: vessel.sourceFamily,
                processors: vessel.processors.filter {
                    $0.coordinate.column <= target.column
                },
                hasAuxiliaryGenerator: vessel.hasAuxiliaryGenerator,
                parentVesselIDs: vessel.parentVesselIDs
            )
        }
    }

    public func descendants(of vesselID: VesselGraph.ID) -> Set<VesselGraph.ID> {
        var result: Set<VesselGraph.ID> = [vesselID]
        var changed = true
        while changed {
            changed = false
            for vessel in vessels where !result.contains(vessel.id) {
                if vessel.parentVesselIDs.contains(where: result.contains) {
                    result.insert(vessel.id)
                    changed = true
                }
            }
        }
        return result
    }
}
