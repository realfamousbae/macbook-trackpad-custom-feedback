import AppKit

@MainActor
final class CalibrationWindow: NSWindowController, NSWindowDelegate {
    private let instructions = NSTextField(wrappingLabelWithString: "")
    private let progress = NSTextField(labelWithString: "")
    private let button = NSButton(title: "Начать", target: nil, action: nil)
    private var phase = 0
    private var recording = false
    private var readyAt = 0.0
    private var lastFrameAt: Double?
    private var peak: Signal?
    private var multipleContacts = false
    private var history = ContactHistory()
    private var ordinary: [Signal] = []
    private var sharp: [Signal] = []
    private var count = 0

    private let phases = [
        ("Сделай 6 обычных кликов одним пальцем, как при работе за Mac.", 6),
        ("Сделай 4 плавных нажатия одним пальцем. Плавно увеличивай нажим, затем отпускай.", 4),
        ("Сделай 6 коротких резких касаний одним пальцем, без тактильного щелчка.", 6)
    ]
    private let complete: (Calibration) -> Void
    private let closed: () -> Void

    init(complete: @escaping (Calibration) -> Void, closed: @escaping () -> Void) {
        self.complete = complete
        self.closed = closed
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 195),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Калибровка трекпада"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView()
        let stack = NSStackView(views: [instructions, progress, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.contentView = content
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(begin)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        closed()
    }

    @objc private func begin() {
        if phase == phases.count {
            phase = 0
            ordinary.removeAll()
            sharp.removeAll()
        }
        recording = true
        readyAt = ProcessInfo.processInfo.systemUptime + 0.55
        refresh()
    }

    private func refresh() {
        if phase == phases.count {
            instructions.stringValue = "Обычные и резкие касания дали похожие показания. Попробуй ещё раз, отрывая палец между попытками."
            progress.stringValue = "Порог не подобран"
            button.title = "Повторить"
            button.isEnabled = true
            return
        }
        let (text, total) = phases[phase]
        instructions.stringValue = text + " Каждый раз полностью отрывай палец."
        progress.stringValue = "Шаг \(phase + 1) из \(phases.count) · \(count) из \(total)"
        button.title = recording ? "Запись касаний…" : "Начать шаг"
        button.isEnabled = !recording
    }

    func receive(_ frame: ContactFrame, arrivedAt: Double) {
        guard recording, arrivedAt >= readyAt else { return }
        if let lastFrameAt, arrivedAt - lastFrameAt >= 0.18 { endContact() }
        guard recording else { return }
        if frame.count == 0 {
            endContact()
            return
        }
        lastFrameAt = arrivedAt
        if frame.count > 1 { multipleContacts = true }
        guard !multipleContacts else { return }
        if let id = history.id, id != frame.id {
            endContact()
            guard recording else { return }
            lastFrameAt = arrivedAt
        }
        let sample = history.measure(frame)
        peak = (peak ?? .zero).combined(with: sample, using: max)
    }

    func tick(now: Double) {
        if let lastFrameAt, now - lastFrameAt >= 0.18 { endContact() }
    }

    private func endContact() {
        let sample = multipleContacts ? nil : peak
        peak = nil
        history.reset()
        lastFrameAt = nil
        multipleContacts = false
        guard let sample, sample.values.contains(where: { $0 > 0 }) else { return }
        if phase == 2 {
            sharp.append(sample)
        } else {
            ordinary.append(sample)
        }
        count += 1
        if count == phases[phase].1 {
            recording = false
            count = 0
            phase += 1
            if phase == phases.count, let calibration = Calibration.fit(ordinary: ordinary, sharp: sharp) {
                complete(calibration)
                close()
                return
            }
        }
        refresh()
    }
}
