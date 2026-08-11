public enum LaunchpadButtonPhase: Equatable, Sendable {
    case pressed
    case released
}

public enum LaunchpadGridMapping {
    /// Top-left button above the matrix in Programmer mode.
    public static let projectNote: UInt8 = 91
    /// Second button from the left above the matrix in Programmer mode.
    public static let masterEffectsNote: UInt8 = 92
    /// Third button from the left above the matrix in Programmer mode.
    public static let destructiveEffectsNote: UInt8 = 93
    /// Fourth button from the left above the matrix in Programmer mode.
    public static let globalScenesNote: UInt8 = 94
    /// Top-right button above the matrix in Programmer mode.
    public static let shiftNote: UInt8 = 98

    /// Mk3 programmer layout uses XY addresses 11...88, with 11 at bottom-left.
    public static func coordinate(for note: UInt8) -> PadCoordinate? {
        let deviceRow = Int(note / 10)
        let deviceColumn = Int(note % 10)
        guard (1...8).contains(deviceRow), (1...8).contains(deviceColumn) else {
            return nil
        }
        return PadCoordinate(row: 8 - deviceRow, column: deviceColumn - 1)
    }

    public static func note(for coordinate: PadCoordinate) -> UInt8 {
        UInt8((8 - coordinate.row) * 10 + coordinate.column + 1)
    }

    public static func auxiliaryNote(forRow row: Int) -> UInt8 {
        UInt8((8 - max(0, min(7, row))) * 10 + 9)
    }

    public static func auxiliaryRow(for note: UInt8) -> Int? {
        guard note % 10 == 9 else { return nil }
        let deviceRow = Int(note / 10)
        guard (1...8).contains(deviceRow) else { return nil }
        return 8 - deviceRow
    }

    public static func auxiliaryPhase(status: UInt8, value: UInt8) -> LaunchpadButtonPhase? {
        switch status & 0xF0 {
        case 0xB0, 0x90:
            value > 0 ? .pressed : .released
        case 0x80:
            .released
        default:
            nil
        }
    }

    public static func shiftPhase(
        note: UInt8,
        status: UInt8,
        value: UInt8
    ) -> LaunchpadButtonPhase? {
        guard note == shiftNote else { return nil }
        return auxiliaryPhase(status: status, value: value)
    }

    public static func projectPhase(
        note: UInt8,
        status: UInt8,
        value: UInt8
    ) -> LaunchpadButtonPhase? {
        guard note == projectNote else { return nil }
        return auxiliaryPhase(status: status, value: value)
    }

    public static func masterEffectsPhase(
        note: UInt8,
        status: UInt8,
        value: UInt8
    ) -> LaunchpadButtonPhase? {
        guard note == masterEffectsNote else { return nil }
        return auxiliaryPhase(status: status, value: value)
    }

    public static func destructiveEffectsPhase(
        note: UInt8,
        status: UInt8,
        value: UInt8
    ) -> LaunchpadButtonPhase? {
        guard note == destructiveEffectsNote else { return nil }
        return auxiliaryPhase(status: status, value: value)
    }

    public static func globalScenesPhase(
        note: UInt8,
        status: UInt8,
        value: UInt8
    ) -> LaunchpadButtonPhase? {
        guard note == globalScenesNote else { return nil }
        return auxiliaryPhase(status: status, value: value)
    }
}
