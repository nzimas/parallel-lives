public struct VesselTopology: Sendable {
    public let vessels: [VesselGraph]

    public init(vessels: [VesselGraph]) {
        self.vessels = vessels
    }

    public var hubs: Set<PadCoordinate> {
        var lineages: [PadCoordinate: Set<VesselGraph.ID>] = [:]
        for vessel in vessels {
            for coordinate in Set(vessel.source.gridRoute(to: vessel.destination)) {
                lineages[coordinate, default: []].insert(vessel.rootVesselID)
            }
        }
        return Set(lineages.compactMap { coordinate, rootIDs in
            rootIDs.count > 1 ? coordinate : nil
        })
    }

    public func parents(for source: PadCoordinate) -> [VesselGraph] {
        vessels.filter { $0.destination == source }
    }
}
