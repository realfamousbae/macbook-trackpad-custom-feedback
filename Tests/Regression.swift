import AVFoundation

@main
@MainActor
struct Regression {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        func signal(_ pressure: Double) -> Signal { Signal(size: 0.4, pressure: pressure, depth: 1) }
        let calibration = try XCTUnwrap(Calibration.fit(ordinary: [signal(2), signal(3)],
                                                        sharp: [signal(12), signal(15)]))
        try require(calibration.channel == 1, "Selects separable pressure channel")
        try require(Calibration.fit(ordinary: [signal(15)], sharp: [signal(12)]) == nil, "Rejects overlapping calibration")

        var detector = PressDetector()
        func press(_ time: Double, _ pressure: Double, count: Int32 = 1,
                   sensitivity: Sensitivity = .higher) -> Bool {
            detector.consume(ContactFrame(time: time, count: count, id: 1, signal: signal(pressure)),
                             calibration: calibration, sensitivity: sensitivity)
        }
        try require(!press(0, 2), "Ordinary click is silent")
        try require(press(0.02, 12), "Fast pressure rise triggers without a click event")
        try require(!press(0.04, 14), "A held press triggers once")
        try require(!press(0.06, 0, count: 0), "Release is silent")
        try require(!press(0.08, 15, count: 2), "Multitouch is silent")
        try require(!press(0.10, 15), "Lifting one finger does not start a new gesture")
        try require(!press(0.12, 0, count: 0), "Reset after full lift")
        try require(press(0.14, 12), "Next sharp contact triggers")
        detector.reset()
        try require(Sensitivity(rawValue: 0) == .baseline, "An unset preference uses the baseline")
        try require(!press(0.20, 8, sensitivity: .baseline), "The baseline ignores a press that the higher level detects")
        try require(press(0.22, 8.5, sensitivity: .baseline), "The baseline detects a stronger press")
        detector.reset()
        try require(!press(0.30, 8.5, sensitivity: .lower), "The lower level raises the threshold further")
        try require(press(0.32, 9, sensitivity: .lower), "The lower level still detects a harder press")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let realSounds = Sounds(directory: directory.appendingPathComponent("example"))
        realSounds.volume = 0
        let example = URL(fileURLWithPath: CommandLine.arguments[1])
        try realSounds.setUp(example: example)
        try realSounds.setUp(example: example)
        let seeded = try realSounds.play(advance: true)
        try require(seeded?.lastPathComponent == "example.mp3" && realSounds.isPlaying, "Starts the bundled MP3")
        let busy = try realSounds.play(advance: true)
        try require(busy == nil && realSounds.isPlaying, "A second press leaves the current sound playing")

        let sounds = Sounds(directory: directory.appendingPathComponent("playlist"))
        sounds.volume = 0
        try sounds.setUp(example: nil)
        let empty = try sounds.play(advance: true)
        try require(empty == nil, "An empty folder is silent")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
        buffer.frameLength = 4410
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }

        func write(_ name: String) throws {
            let file = try AVAudioFile(forWriting: sounds.directory.appendingPathComponent(name), settings: format.settings)
            try file.write(from: buffer)
        }

        try write("10.wav")
        try write("2.wav")
        let first = try sounds.play(advance: true)
        try require(first?.lastPathComponent == "2.wav", "Numeric filename order")
        try write("3.wav")
        for expected in ["3.wav", "10.wav", "2.wav"] {
            let deadline = Date().addingTimeInterval(2)
            while sounds.isPlaying && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            let next = try sounds.play(advance: true)
            try require(next?.lastPathComponent == expected, "Playlist order, folder refresh, and wraparound: \(expected)")
        }
        print("Regression checks passed")
    }

    static func XCTUnwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "Missing expected test value", code: 1) }
        return value
    }
}
