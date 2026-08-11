import Foundation

public enum TrackPalette {
    public static let hues: [Double] = [
        0.000, 0.070, 0.145, 0.315,
        0.500, 0.605, 0.735, 0.885,
    ]

    public static func hue(forRow row: Int) -> Double {
        hues[max(0, min(hues.count - 1, row))]
    }
}

public enum TrackMixer {
    public static let defaultVolume = 1.0
    public static let defaultPan = 0.0
    // PadCoordinate is top-origin; the Launchpad's physical rows are bottom-origin.
    public static let volumePadRow = 7  // physical row 1
    public static let panPadRow = 6     // physical row 2
    public static let reverbPadRow = 0      // physical top row 8
    public static let delayPadRow = 1       // physical row 7
    public static let saturationPadRow = 2  // physical row 6
    public static let crusherPadRow = 3     // physical row 5
    public static let gatePadRow = 4         // physical row 4
    public static let scenePadRows = [5]     // physical row 3
    public static let defaultGate = 0.0
    public static let defaultTempoBPM = 90.0

    public static func sceneSlot(for pad: PadCoordinate) -> Int? {
        guard let rowOffset = scenePadRows.firstIndex(of: pad.row) else { return nil }
        return rowOffset * 8 + pad.column
    }

    // An eight-column bipolar control needs two central cells. Both deliberately
    // resolve to exact centre, avoiding an unwanted left/right bias at rest.
    public static let panValues: [Double] = [
        -1, -2.0 / 3.0, -1.0 / 3.0, 0,
         0,  1.0 / 3.0,  2.0 / 3.0, 1,
    ]
    public static let gateValues = panValues

    public static func volume(forColumn column: Int) -> Double {
        Double(max(0, min(7, column))) / 7.0
    }

    public static func send(forColumn column: Int) -> Double {
        Double(max(0, min(7, column))) / 7.0
    }

    public static func pan(forColumn column: Int) -> Double {
        panValues[max(0, min(7, column))]
    }

    public static func gate(forColumn column: Int) -> Double {
        gateValues[max(0, min(7, column))]
    }

    public static func gateColumn(for gate: Double) -> Int {
        let value = max(-1, min(1, gate))
        if abs(value) < 0.000_001 { return 3 }
        return gateValues.enumerated().min {
            abs($0.element - value) < abs($1.element - value)
        }?.offset ?? 3
    }

    public static func gateClockMultiplier(for gate: Double) -> Double {
        let value = max(-1, min(1, gate))
        guard abs(value) >= 0.000_001 else { return 0 }
        let magnitude = abs(value)
        let exponent = Int((magnitude * 3).rounded())
        return value < 0
            ? 1 / pow(2, Double(exponent))
            : pow(2, Double(exponent))
    }

    public static func volumeColumn(for volume: Double) -> Int {
        Int((max(0, min(1, volume)) * 7).rounded())
    }

    public static func sendColumn(for value: Double) -> Int {
        Int((max(0, min(1, value)) * 7).rounded())
    }

    public static func panColumn(for pan: Double) -> Int {
        let value = max(-1, min(1, pan))
        if abs(value) < 0.000_001 { return 3 }
        return panValues.enumerated().min {
            abs($0.element - value) < abs($1.element - value)
        }?.offset ?? 3
    }
}

/// Launchpad Mini Mk3 faders expose four successive values on each of eight
/// pads. This reproduces that 32-position behaviour while the controller stays
/// in Programmer mode, where ParallelLives can retain mixed slider/slot pages.
public enum LaunchpadFader {
    public static let levelsPerPad = 4
    public static let stepCount = 32
    public static let maximumStep = stepCount - 1

    public static func unipolarValue(forStep step: Int) -> Double {
        Double(clamp(step)) / Double(maximumStep)
    }

    public static func unipolarStep(for value: Double) -> Int {
        clamp(Int((max(0, min(1, value)) * Double(maximumStep)).rounded()))
    }

    // Two centre steps deliberately resolve to exact zero, retaining the
    // Launchpad's visually centred bipolar rest position.
    public static func bipolarValue(forStep step: Int) -> Double {
        let step = clamp(step)
        if step <= 15 { return -1 + (Double(step) / 15) }
        return Double(step - 16) / 15
    }

    public static func bipolarStep(for value: Double) -> Int {
        let value = max(-1, min(1, value))
        if abs(value) < 0.000_001 { return 15 }
        if value < 0 { return clamp(Int(((value + 1) * 15).rounded())) }
        return clamp(16 + Int((value * 15).rounded()))
    }

    public static func nextUnipolarStep(currentValue: Double, padColumn: Int) -> Int {
        nextStep(currentStep: unipolarStep(for: currentValue), padColumn: padColumn)
    }

    public static func nextBipolarStep(currentValue: Double, padColumn: Int) -> Int {
        nextStep(currentStep: bipolarStep(for: currentValue), padColumn: padColumn)
    }

    public static func padColumn(forStep step: Int) -> Int { clamp(step) / levelsPerPad }
    public static func levelInPad(forStep step: Int) -> Int { clamp(step) % levelsPerPad }

    public static func markerBrightness(forStep step: Int) -> Double {
        [0.67, 0.78, 0.89, 1.0][levelInPad(forStep: step)]
    }

    private static func nextStep(currentStep: Int, padColumn targetColumn: Int) -> Int {
        let column = max(0, min(7, targetColumn))
        let currentStep = clamp(currentStep)
        let currentColumn = padColumn(forStep: currentStep)
        if column == currentColumn {
            let nextLevel = (levelInPad(forStep: currentStep) + 1) % levelsPerPad
            return (column * levelsPerPad) + nextLevel
        }
        // Enter a higher cell at its lowest sublevel and a lower cell at its
        // highest, so large fader moves remain directionally continuous.
        return column > currentColumn
            ? column * levelsPerPad
            : (column * levelsPerPad) + levelsPerPad - 1
    }

    private static func clamp(_ step: Int) -> Int { max(0, min(maximumStep, step)) }
}

public struct TrackSendLevels: Codable, Equatable, Sendable {
    public var reverb: Double
    public var delay: Double
    public var saturation: Double
    public var crusher: Double

    public static let zero = TrackSendLevels()

    public init(
        reverb: Double = 0,
        delay: Double = 0,
        saturation: Double = 0,
        crusher: Double = 0
    ) {
        self.reverb = reverb
        self.delay = delay
        self.saturation = saturation
        self.crusher = crusher
    }
}
