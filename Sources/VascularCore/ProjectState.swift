public enum ProjectGrid {
    public static let slotCount = 32
    public static let padRows = [7, 6, 5, 4]

    public static func slot(for pad: PadCoordinate) -> Int? {
        guard let rowOffset = padRows.firstIndex(of: pad.row) else { return nil }
        return rowOffset * 8 + pad.column
    }

    public static func pad(for slot: Int) -> PadCoordinate? {
        guard (0..<slotCount).contains(slot) else { return nil }
        return PadCoordinate(row: padRows[slot / 8], column: slot % 8)
    }
}

public enum GlobalSceneGrid {
    public static let slotCount = 32
    public static let padRows = [7, 6, 5, 4]

    public static func slot(for pad: PadCoordinate) -> Int? {
        guard let rowOffset = padRows.firstIndex(of: pad.row) else { return nil }
        return rowOffset * 8 + pad.column
    }

    public static func pad(for slot: Int) -> PadCoordinate? {
        guard (0..<slotCount).contains(slot) else { return nil }
        return PadCoordinate(row: padRows[slot / 8], column: slot % 8)
    }
}

/// A performance snapshot deliberately excludes scene banks, preventing a
/// project -> scene -> project recursion while retaining every audible setting.
public struct GlobalSceneState: Codable, Equatable, Sendable {
    public let session: VascularSession
    public let trackVolumes: [Double]
    public let trackPans: [Double]
    public let trackSends: [TrackSendLevels]
    public let trackGates: [Double]
    public let activeTrackSceneSlots: [Int: Int]
    public let masterEffects: MasterEffectParameters
    public let destructiveEffects: DestructiveEffectParameters

    public init(
        session: VascularSession,
        trackVolumes: [Double],
        trackPans: [Double],
        trackSends: [TrackSendLevels],
        trackGates: [Double],
        activeTrackSceneSlots: [Int: Int],
        masterEffects: MasterEffectParameters,
        destructiveEffects: DestructiveEffectParameters
    ) {
        self.session = session
        self.trackVolumes = trackVolumes
        self.trackPans = trackPans
        self.trackSends = trackSends
        self.trackGates = trackGates
        self.activeTrackSceneSlots = activeTrackSceneSlots
        self.masterEffects = masterEffects
        self.destructiveEffects = destructiveEffects
    }

    public var hasValidTrackState: Bool {
        trackVolumes.count == 8
            && trackPans.count == 8
            && trackSends.count == 8
            && trackGates.count == 8
    }
}

public struct GlobalSceneBank: Codable, Equatable, Sendable {
    public var scenes: [Int: GlobalSceneState]

    public init(scenes: [Int: GlobalSceneState] = [:]) {
        self.scenes = scenes.filter { (0..<GlobalSceneGrid.slotCount).contains($0.key) }
    }

    public func scene(slot: Int) -> GlobalSceneState? {
        guard (0..<GlobalSceneGrid.slotCount).contains(slot) else { return nil }
        return scenes[slot]
    }

    public mutating func setScene(_ scene: GlobalSceneState, slot: Int) {
        guard (0..<GlobalSceneGrid.slotCount).contains(slot) else { return }
        scenes[slot] = scene
    }

    public var occupiedSlots: Set<Int> { Set(scenes.keys) }
    public var hasValidSceneStates: Bool {
        scenes.values.allSatisfy(\.hasValidTrackState)
    }
}

public struct ProjectState: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 4

    public let formatVersion: Int
    public let session: VascularSession
    public let trackVolumes: [Double]
    public let trackPans: [Double]
    public let trackSends: [TrackSendLevels]
    public let trackGates: [Double]
    public let sceneBank: TrackSceneBank
    public let activeSceneSlots: [Int: Int]
    public let masterEffects: MasterEffectParameters
    public let destructiveEffects: DestructiveEffectParameters
    public let globalSceneBank: GlobalSceneBank
    public let activeGlobalSceneSlot: Int?

    public init(
        session: VascularSession,
        trackVolumes: [Double],
        trackPans: [Double],
        trackSends: [TrackSendLevels],
        trackGates: [Double],
        sceneBank: TrackSceneBank,
        activeSceneSlots: [Int: Int],
        masterEffects: MasterEffectParameters = .defaults,
        destructiveEffects: DestructiveEffectParameters = .defaults,
        globalSceneBank: GlobalSceneBank = GlobalSceneBank(),
        activeGlobalSceneSlot: Int? = nil,
        formatVersion: Int = currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.session = session
        self.trackVolumes = trackVolumes
        self.trackPans = trackPans
        self.trackSends = trackSends
        self.trackGates = trackGates
        self.sceneBank = sceneBank
        self.activeSceneSlots = activeSceneSlots
        self.masterEffects = masterEffects
        self.destructiveEffects = destructiveEffects
        self.globalSceneBank = globalSceneBank
        self.activeGlobalSceneSlot = activeGlobalSceneSlot
    }

    public var hasValidTrackState: Bool {
        trackVolumes.count == 8
            && trackPans.count == 8
            && trackSends.count == 8
            && trackGates.count == 8
            && globalSceneBank.hasValidSceneStates
    }


    private enum CodingKeys: String, CodingKey {
        case formatVersion, session, trackVolumes, trackPans, trackSends
        case trackGates, sceneBank, activeSceneSlots, masterEffects, destructiveEffects
        case globalSceneBank, activeGlobalSceneSlot
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        session = try values.decode(VascularSession.self, forKey: .session)
        trackVolumes = try values.decode([Double].self, forKey: .trackVolumes)
        trackPans = try values.decode([Double].self, forKey: .trackPans)
        trackSends = try values.decode([TrackSendLevels].self, forKey: .trackSends)
        trackGates = try values.decode([Double].self, forKey: .trackGates)
        sceneBank = try values.decode(TrackSceneBank.self, forKey: .sceneBank)
        activeSceneSlots = try values.decode([Int: Int].self, forKey: .activeSceneSlots)
        masterEffects = try values.decodeIfPresent(
            MasterEffectParameters.self,
            forKey: .masterEffects
        ) ?? .defaults
        destructiveEffects = try values.decodeIfPresent(
            DestructiveEffectParameters.self,
            forKey: .destructiveEffects
        ) ?? .defaults
        globalSceneBank = try values.decodeIfPresent(
            GlobalSceneBank.self,
            forKey: .globalSceneBank
        ) ?? GlobalSceneBank()
        activeGlobalSceneSlot = try values.decodeIfPresent(
            Int.self,
            forKey: .activeGlobalSceneSlot
        )
    }

    public var isSupportedFormat: Bool {
        (1...Self.currentFormatVersion).contains(formatVersion)
    }
}

public struct ProjectBank: Codable, Equatable, Sendable {
    public var projects: [Int: ProjectState]

    public init(projects: [Int: ProjectState] = [:]) {
        self.projects = projects.filter { (0..<ProjectGrid.slotCount).contains($0.key) }
    }

    public func project(slot: Int) -> ProjectState? {
        guard (0..<ProjectGrid.slotCount).contains(slot) else { return nil }
        return projects[slot]
    }

    public mutating func setProject(_ project: ProjectState, slot: Int) {
        guard (0..<ProjectGrid.slotCount).contains(slot) else { return }
        projects[slot] = project
    }

    public var occupiedSlots: Set<Int> { Set(projects.keys) }
}
