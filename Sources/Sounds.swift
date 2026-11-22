import AVFoundation
import Foundation

@MainActor
final class Sounds {
    static let formats: Set<String> = ["mp3", "wav", "m4a"]

    let directory: URL
    private var player: AVAudioPlayer?
    private var lastPlayed: URL?
    var volume: Float = 1

    init(directory: URL) {
        self.directory = directory
    }

    func setUp(example: URL?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let example else { return }
        let destination = directory.appendingPathComponent("example.mp3")
        do {
            try FileManager.default.copyItem(at: example, to: destination)
        } catch CocoaError.fileWriteFileExists {
            // The user's file already occupies this name.
        }
    }

    func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory,
                                                   includingPropertiesForKeys: [.isRegularFileKey],
                                                   options: [.skipsHiddenFiles])
            .filter {
                Self.formats.contains($0.pathExtension.lowercased()) &&
                    (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted {
                let left = $0.lastPathComponent
                let right = $1.lastPathComponent
                let order = left.compare(right, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                return order == .orderedSame ? left < right : order == .orderedAscending
            }
    }

    var isPlaying: Bool { player?.isPlaying == true }

    @discardableResult
    func play(advance: Bool) throws -> URL? {
        guard !isPlaying else { return nil }
        let list = try files()
        guard !list.isEmpty else { return nil }
        let first = advance ? lastPlayed.flatMap { list.firstIndex(of: $0) }.map { ($0 + 1) % list.count } ?? 0 : 0
        for offset in list.indices {
            let file = list[(first + offset) % list.count]
            guard let candidate = try? AVAudioPlayer(contentsOf: file) else { continue }
            candidate.volume = volume
            guard candidate.prepareToPlay(), candidate.play() else { continue }
            player = candidate
            if advance { lastPlayed = file }
            return file
        }
        throw Error.noPlayableFiles
    }

    enum Error: LocalizedError {
        case noPlayableFiles
        var errorDescription: String? { "Файлы в папке не удалось воспроизвести." }
    }
}
