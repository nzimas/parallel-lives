import Foundation
import VascularCore

struct ProjectStore {
    enum StoreError: LocalizedError {
        case invalidProject

        var errorDescription: String? {
            switch self {
            case .invalidProject: "Project contains an invalid track state"
            }
        }
    }

    let fileURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        fileURL = support
            .appending(path: "Vascular", directoryHint: .isDirectory)
            .appending(path: "Projects.json", directoryHint: .notDirectory)
    }

    func load() throws -> ProjectBank {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProjectBank()
        }
        let bank = try JSONDecoder().decode(ProjectBank.self, from: Data(contentsOf: fileURL))
        guard bank.projects.values.allSatisfy(\.hasValidTrackState) else {
            throw StoreError.invalidProject
        }
        return bank
    }

    func save(_ bank: ProjectBank) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bank).write(to: fileURL, options: .atomic)
    }
}
