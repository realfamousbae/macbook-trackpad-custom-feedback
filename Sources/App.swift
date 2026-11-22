import AppKit

@main
@MainActor
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static weak var running: App?

    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let notice = NSMenuItem()
    private let reactionSwitch = NSSwitch()
    private let calibrateItem = NSMenuItem(title: "Калибровка…", action: #selector(calibrate), keyEquivalent: "")
    private let sensitivityMenu = NSMenu(title: "Чувствительность")
    private let testItem = NSMenuItem(title: "Проверить звук", action: #selector(testSound), keyEquivalent: "")
    private var sounds: Sounds!
    private var calibration: Calibration?
    private var calibrationWindow: CalibrationWindow?
    private var detector = PressDetector()
    private var sensitivity = Sensitivity.baseline
    private var timer: Timer?
    private var trackpadError: Int32?
    private var soundError: String?

    static func main() {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == "--probe" {
            exit(runProbe())
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = App()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.running = self
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        sounds = Sounds(directory: support.appendingPathComponent("Trackpad Feedback/Sounds", isDirectory: true))
        setUpSounds()
        sensitivity = Sensitivity(rawValue: defaults.integer(forKey: "sensitivityOffset")) ?? .baseline

        if let data = defaults.data(forKey: "calibration"),
           let saved = try? JSONDecoder().decode(Calibration.self, from: data),
           (0..<3).contains(saved.channel), saved.threshold.isFinite, saved.threshold > 0 {
            calibration = saved
        }

        let menu = NSMenu()
        menu.delegate = self
        let reactionTitle = "Реакция на нажатия"
        let label = NSTextField(labelWithString: reactionTitle)
        label.font = .menuFont(ofSize: 0)
        label.setAccessibilityElement(false)
        reactionSwitch.setAccessibilityLabel(reactionTitle)
        reactionSwitch.target = self
        reactionSwitch.action = #selector(toggleEnabled)

        let row = NSStackView(views: [label, reactionSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.edgeInsets = NSEdgeInsets(top: 5, left: 18, bottom: 5, right: 14)
        row.setFrameSize(row.fittingSize)

        let reactionItem = NSMenuItem(title: reactionTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        reactionItem.target = self
        reactionItem.view = row
        menu.addItem(reactionItem)
        menu.addItem(notice)
        menu.addItem(.separator())
        let sensitivityItem = NSMenuItem(title: "Чувствительность", action: nil, keyEquivalent: "")
        sensitivityItem.submenu = sensitivityMenu
        for option in Sensitivity.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(changeSensitivity), keyEquivalent: "")
            item.target = self
            item.tag = option.rawValue
            sensitivityMenu.addItem(item)
        }
        for item in [sensitivityItem, calibrateItem, testItem,
                     NSMenuItem(title: "Открыть папку звуков", action: #selector(openSounds), keyEquivalent: "")] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.button?.title = "◉"
        statusItem.button?.setAccessibilityLabel("Trackpad Feedback")
        statusItem.button?.toolTip = "Trackpad Feedback"
        statusItem.menu = menu

        startTrackpad()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer(timeInterval: 0.08, repeats: true) { _ in
            MainActor.assumeIsolated {
                Self.running?.calibrationWindow?.tick(now: ProcessInfo.processInfo.systemUptime)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refreshMenu()
        if calibration == nil, trackpadError == nil { calibrate() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trackpad_stop()
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func startTrackpad() {
        let result = trackpad_start(handleFrame)
        trackpadError = result == 0 ? nil : result
    }

    @objc private func willSleep() {
        trackpad_stop()
        detector.reset()
    }

    @objc private func didWake() {
        startTrackpad()
        refreshMenu()
    }

    private func setUpSounds() {
        do {
            let seeded = defaults.bool(forKey: "exampleInstalled")
            let example = Bundle.main.url(forResource: "example", withExtension: "mp3")
            try sounds.setUp(example: seeded ? nil : example)
            if example != nil { defaults.set(true, forKey: "exampleInstalled") }
            soundError = nil
        } catch {
            soundError = "Не удалось подготовить папку звуков."
        }
    }

    private var enabled: Bool {
        calibration != nil && !defaults.bool(forKey: "paused") && trackpadError == nil
    }

    fileprivate static func deliver(_ frame: ContactFrame, arrivedAt: Double) {
        running?.receive(frame, arrivedAt: arrivedAt)
    }

    private func receive(_ frame: ContactFrame, arrivedAt: Double) {
        if let calibrationWindow {
            calibrationWindow.receive(frame, arrivedAt: arrivedAt)
            return
        }
        guard enabled, let calibration else { return }
        if detector.consume(frame, calibration: calibration, sensitivity: sensitivity), !sounds.isPlaying {
            play(advance: true)
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        let files = try? sounds.files()
        if let trackpadError {
            notice.title = "Трекпад недоступен (\(trackpadError))"
        } else if let soundError {
            notice.title = soundError
        } else if files?.isEmpty != false {
            notice.title = "Папка звуков пуста"
        } else if calibration == nil {
            notice.title = "Требуется калибровка"
        } else {
            notice.title = ""
        }
        notice.isHidden = notice.title.isEmpty
        reactionSwitch.state = enabled ? .on : .off
        reactionSwitch.isEnabled = trackpadError == nil
        for item in sensitivityMenu.items {
            item.state = item.tag == sensitivity.rawValue ? .on : .off
        }
        calibrateItem.title = trackpadError == nil ? "Калибровка…" : "Повторить подключение трекпада…"
        testItem.isEnabled = files?.isEmpty == false && !sounds.isPlaying
    }

    @objc private func changeSensitivity(_ item: NSMenuItem) {
        guard let option = Sensitivity(rawValue: item.tag) else { return }
        sensitivity = option
        defaults.set(option.rawValue, forKey: "sensitivityOffset")
        detector.reset()
        refreshMenu()
    }

    @objc private func toggleEnabled() {
        guard trackpadError == nil else { return }
        guard calibration != nil else {
            refreshMenu()
            statusItem.menu?.cancelTracking()
            DispatchQueue.main.async { [weak self] in self?.calibrate() }
            return
        }
        defaults.set(enabled, forKey: "paused")
        detector.reset()
        refreshMenu()
    }

    @objc private func calibrate() {
        if trackpadError != nil { startTrackpad() }
        refreshMenu()
        guard trackpadError == nil else { return }
        if calibrationWindow == nil {
            calibrationWindow = CalibrationWindow { [weak self] result in
                guard let self else { return }
                calibration = result
                defaults.set(try? JSONEncoder().encode(result), forKey: "calibration")
                refreshMenu()
            } closed: { [weak self] in
                self?.calibrationWindow = nil
                self?.detector.reset()
            }
        }
        calibrationWindow?.showWindow(nil)
        NSApp.activate()
    }

    private func play(advance: Bool) {
        do {
            _ = try sounds.play(advance: advance)
            soundError = nil
        } catch {
            soundError = error.localizedDescription
        }
        refreshMenu()
    }

    @objc private func testSound() { play(advance: false) }

    @objc private func openSounds() {
        setUpSounds()
        if soundError == nil { NSWorkspace.shared.open(sounds.directory) }
        refreshMenu()
    }

    private static func runProbe() -> Int32 {
        let result = trackpad_start { _, _, _, _, _, _ in }
        print("Trackpad stream start result: \(result)")
        trackpad_stop()
        return result
    }
}


private func handleFrame(_ time: Double, _ count: Int32, _ id: Int32,
                         _ size: Float, _ pressure: Float, _ depth: Float) {
    guard time.isFinite, size.isFinite, pressure.isFinite, depth.isFinite else { return }
    let arrivedAt = ProcessInfo.processInfo.systemUptime
    let frame = ContactFrame(time: time, count: count, id: id,
                             signal: Signal(size: Double(size), pressure: Double(pressure), depth: Double(depth)))
    DispatchQueue.main.async {
        App.deliver(frame, arrivedAt: arrivedAt)
    }
}
