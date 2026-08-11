public enum DestructiveEffectControl: Int, CaseIterable, Codable, Sendable {
    case saturationDrive = 0
    case saturationCurve = 1
    case saturationTone = 2
    case saturationBody = 3
    case crusherBits = 4
    case crusherRate = 5
    case crusherJitter = 6
    case crusherTone = 7

    public init?(padRow: Int) { self.init(rawValue: padRow) }
}

public struct DestructiveEffectParameters: Codable, Equatable, Sendable {
    public var saturationDrive: Double
    public var saturationCurve: Double
    public var saturationTone: Double
    public var saturationBody: Double
    public var crusherBits: Double
    public var crusherRate: Double
    public var crusherJitter: Double
    public var crusherTone: Double

    public static let defaults = DestructiveEffectParameters(
        saturationDrive: 0.38,
        saturationCurve: 0.3,
        saturationTone: 0.58,
        saturationBody: 0.35,
        crusherBits: 0.2,
        crusherRate: 0.4,
        crusherJitter: 0.08,
        crusherTone: 0.27
    )

    public init(
        saturationDrive: Double,
        saturationCurve: Double,
        saturationTone: Double,
        saturationBody: Double,
        crusherBits: Double,
        crusherRate: Double,
        crusherJitter: Double,
        crusherTone: Double
    ) {
        self.saturationDrive = Self.clamp(saturationDrive)
        self.saturationCurve = Self.clamp(saturationCurve)
        self.saturationTone = Self.clamp(saturationTone)
        self.saturationBody = Self.clamp(saturationBody)
        self.crusherBits = Self.clamp(crusherBits)
        self.crusherRate = Self.clamp(crusherRate)
        self.crusherJitter = Self.clamp(crusherJitter)
        self.crusherTone = Self.clamp(crusherTone)
    }

    public func value(for control: DestructiveEffectControl) -> Double {
        switch control {
        case .saturationDrive: saturationDrive
        case .saturationCurve: saturationCurve
        case .saturationTone: saturationTone
        case .saturationBody: saturationBody
        case .crusherBits: crusherBits
        case .crusherRate: crusherRate
        case .crusherJitter: crusherJitter
        case .crusherTone: crusherTone
        }
    }

    public mutating func setValue(_ value: Double, for control: DestructiveEffectControl) {
        let value = Self.clamp(value)
        switch control {
        case .saturationDrive: saturationDrive = value
        case .saturationCurve: saturationCurve = value
        case .saturationTone: saturationTone = value
        case .saturationBody: saturationBody = value
        case .crusherBits: crusherBits = value
        case .crusherRate: crusherRate = value
        case .crusherJitter: crusherJitter = value
        case .crusherTone: crusherTone = value
        }
    }

    public static func value(forColumn column: Int) -> Double {
        Double(max(0, min(7, column))) / 7
    }

    public static func column(for value: Double) -> Int {
        Int((clamp(value) * 7).rounded())
    }

    private static func clamp(_ value: Double) -> Double { max(0, min(1, value)) }

    private enum CodingKeys: String, CodingKey {
        case saturationDrive, saturationCurve, saturationTone, saturationBody
        case crusherBits, crusherRate, crusherJitter, crusherTone
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            saturationDrive: try values.decode(Double.self, forKey: .saturationDrive),
            saturationCurve: try values.decode(Double.self, forKey: .saturationCurve),
            saturationTone: try values.decode(Double.self, forKey: .saturationTone),
            saturationBody: try values.decode(Double.self, forKey: .saturationBody),
            crusherBits: try values.decode(Double.self, forKey: .crusherBits),
            crusherRate: try values.decode(Double.self, forKey: .crusherRate),
            crusherJitter: try values.decode(Double.self, forKey: .crusherJitter),
            crusherTone: try values.decode(Double.self, forKey: .crusherTone)
        )
    }
}
