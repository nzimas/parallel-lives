import Foundation

public struct HarmonicAnchor: Codable, Equatable, Sendable {
    public let fundamentalHz: Double
    public let sourceSeed: UInt64

    public init(fundamentalHz: Double, sourceSeed: UInt64) {
        self.fundamentalHz = fundamentalHz
        self.sourceSeed = sourceSeed
    }
}

public enum SourcePitch {
    /// A deliberately compact just-intonation field. Octave normalization keeps
    /// source fundamentals useful for bass-rich electroacoustic material.
    public static let harmonicRatios: [Double] = [
        1, 9.0 / 8, 6.0 / 5, 5.0 / 4, 4.0 / 3,
        3.0 / 2, 8.0 / 5, 5.0 / 3, 7.0 / 4, 15.0 / 8,
    ]

    public static func unanchoredFundamental(sourceSeed: UInt64) -> Double {
        let pitchSeed = mixed(sourceSeed, salt: 0xA0761D6478BD642F)
        let character = Double(pitchSeed % 1009) / 1009
        return 29 * pow(2, character * 2.25)
    }

    public static func relatedFundamental(
        anchor: HarmonicAnchor,
        sourceSeed: UInt64,
        track: Int
    ) -> Double {
        let selection = mixed(
            sourceSeed ^ UInt64(max(0, track) &* 0x9E37),
            salt: anchor.sourceSeed ^ 0xD1B54A32D192ED03
        )
        var frequency = anchor.fundamentalHz
            * harmonicRatios[Int(selection % UInt64(harmonicRatios.count))]
        let octave = Int((selection / UInt64(harmonicRatios.count)) % 3) - 1
        frequency *= pow(2, Double(octave))
        while frequency < 29 { frequency *= 2 }
        while frequency > 220 { frequency *= 0.5 }
        return frequency
    }

    private static func mixed(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var value = seed ^ salt
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return value
    }
}
