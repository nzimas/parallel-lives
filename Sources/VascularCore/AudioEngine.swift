public protocol AudioEngine: Sendable {
    func synchronize(_ vessels: [VesselGraph]) async throws
    func setTrackMix(
        row: Int,
        volume: Double,
        pan: Double,
        sends: TrackSendLevels,
        gate: Double
    ) async throws
    func setMasterEffects(_ parameters: MasterEffectParameters) async throws
    func setDestructiveEffects(_ parameters: DestructiveEffectParameters) async throws
    func panic() async
}

public struct SilentAudioEngine: AudioEngine {
    public init() {}
    public func synchronize(_ vessels: [VesselGraph]) async throws {}
    public func setTrackMix(
        row: Int,
        volume: Double,
        pan: Double,
        sends: TrackSendLevels,
        gate: Double
    ) async throws {}
    public func setMasterEffects(_ parameters: MasterEffectParameters) async throws {}
    public func setDestructiveEffects(_ parameters: DestructiveEffectParameters) async throws {}
    public func panic() async {}
}
