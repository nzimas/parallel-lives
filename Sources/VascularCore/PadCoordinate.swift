import Foundation

public struct PadCoordinate: Hashable, Codable, Sendable {
    public static let matrixSize = 8

    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        precondition((0..<Self.matrixSize).contains(row))
        precondition((0..<Self.matrixSize).contains(column))
        self.row = row
        self.column = column
    }

    public var index: Int { row * Self.matrixSize + column }

    public func distance(to other: Self) -> Double {
        let rowDelta = Double(other.row - row)
        let columnDelta = Double(other.column - column)
        return hypot(rowDelta, columnDelta)
    }

    public func normalizedDistance(to other: Self) -> Double {
        distance(to: other) / hypot(7, 7)
    }

    public func gridRoute(to other: Self) -> [Self] {
        let rowDelta = other.row - row
        let columnDelta = other.column - column
        let steps = max(abs(rowDelta), abs(columnDelta))
        guard steps > 0 else { return [self] }

        return (0...steps).map { step in
            let progress = Double(step) / Double(steps)
            return Self(
                row: Int((Double(row) + Double(rowDelta) * progress).rounded()),
                column: Int((Double(column) + Double(columnDelta) * progress).rounded())
            )
        }
    }
}
