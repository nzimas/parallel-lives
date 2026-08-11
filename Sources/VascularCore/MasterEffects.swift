public enum MasterEffectControl: Int, CaseIterable, Codable, Sendable {
    case reverbSize = 0
    case reverbDecay = 1
    case reverbTone = 2
    case reverbMotion = 3
    case delayTime = 4
    case delayFeedback = 5
    case delayTone = 6
    case delayWidth = 7

    public init?(padRow: Int) {
        self.init(rawValue: padRow)
    }
}

public struct MasterEffectParameters: Codable, Equatable, Sendable {
    public var reverbSize: Double
    public var reverbDecay: Double
    public var reverbTone: Double
    public var reverbMotion: Double
    public var delayTime: Double
    public var delayFeedback: Double
    public var delayTone: Double
    public var delayWidth: Double

    public static let defaults = MasterEffectParameters(
        reverbSize: 0.5,
        reverbDecay: 0.68,
        reverbTone: 0.53,
        reverbMotion: 0.15,
        delayTime: 0.4,
        delayFeedback: 0.52,
        delayTone: 0.55,
        delayWidth: 0.45
    )

    public init(
        reverbSize: Double,
        reverbDecay: Double,
        reverbTone: Double,
        reverbMotion: Double,
        delayTime: Double,
        delayFeedback: Double,
        delayTone: Double,
        delayWidth: Double
    ) {
        self.reverbSize = Self.clamp(reverbSize)
        self.reverbDecay = Self.clamp(reverbDecay)
        self.reverbTone = Self.clamp(reverbTone)
        self.reverbMotion = Self.clamp(reverbMotion)
        self.delayTime = Self.clamp(delayTime)
        self.delayFeedback = Self.clamp(delayFeedback)
        self.delayTone = Self.clamp(delayTone)
        self.delayWidth = Self.clamp(delayWidth)
    }

    private enum CodingKeys: String, CodingKey {
        case reverbSize, reverbDecay, reverbTone, reverbMotion
        case delayTime, delayFeedback, delayTone, delayWidth
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            reverbSize: try values.decode(Double.self, forKey: .reverbSize),
            reverbDecay: try values.decode(Double.self, forKey: .reverbDecay),
            reverbTone: try values.decode(Double.self, forKey: .reverbTone),
            reverbMotion: try values.decode(Double.self, forKey: .reverbMotion),
            delayTime: try values.decode(Double.self, forKey: .delayTime),
            delayFeedback: try values.decode(Double.self, forKey: .delayFeedback),
            delayTone: try values.decode(Double.self, forKey: .delayTone),
            delayWidth: try values.decode(Double.self, forKey: .delayWidth)
        )
    }

    public func value(for control: MasterEffectControl) -> Double {
        switch control {
        case .reverbSize: reverbSize
        case .reverbDecay: reverbDecay
        case .reverbTone: reverbTone
        case .reverbMotion: reverbMotion
        case .delayTime: delayTime
        case .delayFeedback: delayFeedback
        case .delayTone: delayTone
        case .delayWidth: delayWidth
        }
    }

    public mutating func setValue(_ value: Double, for control: MasterEffectControl) {
        let value = Self.clamp(value)
        switch control {
        case .reverbSize: reverbSize = value
        case .reverbDecay: reverbDecay = value
        case .reverbTone: reverbTone = value
        case .reverbMotion: reverbMotion = value
        case .delayTime: delayTime = value
        case .delayFeedback: delayFeedback = value
        case .delayTone: delayTone = value
        case .delayWidth: delayWidth = value
        }
    }

    public static func value(forColumn column: Int) -> Double {
        Double(max(0, min(7, column))) / 7
    }

    public static func column(for value: Double) -> Int {
        Int((clamp(value) * 7).rounded())
    }

    private static func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
