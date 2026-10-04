import Cocoa
import MouseGestures

/// Countdown timer. Showcases all three plugin extension points:
///  • settings — default length, sound
///  • service  — keeps the running timer across app restarts (persists to the plugin's data folder)
///  • UI       — a live status panel with Start / Cancel buttons in the plugin's settings sheet
@objc(FocusTimerPlugin)
public final class FocusTimerPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.focustimer" }
    public var name: String { "Focus Timer" }
    public override var description: String { "Countdown timer with a notification when it ends" }
    public var version: String { "1.1.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "timer", accessibilityDescription: nil) }

    private var host: PluginHost?
    private var timer: Timer?
    private var endDate: Date?
    private var label = "Focus"
    private var serviceRunning = false

    // MARK: actions

    public var providedActions: [PluginAction] {[
        PluginAction(id: "start", name: "Start Timer", description: "Start (or restart) the countdown",
                     requiresParameters: false,
                     supportedParameters: [
                        ParameterDefinition(key: "minutes", name: "Minutes", type: .number,
                                            description: "Length of the countdown (blank = the plugin's default length)",
                                            validation: ValidationRule(minValue: 0.1, maxValue: 600)),
                        ParameterDefinition(key: "label", name: "Label", type: .string, description: "Shown when time is up"),
                     ], icon: "timer"),
        PluginAction(id: "status", name: "Show Time Remaining", description: "Notify how long is left", icon: "hourglass"),
        PluginAction(id: "cancel", name: "Cancel Timer", description: "Stop the running timer", icon: "xmark.circle"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "start":
            let minutes = parameters.number(for: "minutes") ?? host?.number("defaultMinutes", default: 25) ?? 25
            let label = parameters.string(for: "label") ?? "Focus"
            DispatchQueue.main.async { self.begin(minutes: min(600, max(0.1, minutes)), label: label) }
            context.showNotification(title: "\(label) timer started", message: Self.format(minutes * 60), style: .info)
        case "status":
            guard let end = endDate, end > Date() else {
                context.showNotification(title: "Focus Timer", message: "No timer running", style: .info); return
            }
            context.showNotification(title: "\(label): time remaining", message: Self.format(end.timeIntervalSinceNow), style: .info)
        case "cancel":
            DispatchQueue.main.async { self.clear() }
            context.showNotification(title: "Focus Timer", message: "Timer cancelled", style: .info)
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    // MARK: settings

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "defaultMinutes", title: "Default length", kind: .number(min: 1, max: 240, step: 1, unit: "min"),
                           defaultValue: AnyCodable(25), help: "Used when a gesture doesn't set its own minutes."),
        PluginSettingField(key: "playSound", title: "Play a sound when time is up", kind: .toggle, defaultValue: AnyCodable(true)),
        PluginSettingField(key: "sound", title: "Sound",
                           kind: .choice(["Glass", "Hero", "Ping", "Submarine", "Funk"].map { PluginSettingChoice($0, $0) }),
                           defaultValue: AnyCodable("Glass")),
    ]}

    // MARK: service — resume a timer that was running when the app quit

    public var runsBackgroundService: Bool { true }

    public func pluginAttached(host: PluginHost) { self.host = host }
    public func pluginDetached() { timer?.invalidate(); timer = nil; host = nil }

    public func startService() throws {
        serviceRunning = true
        guard let state = loadState() else { return }
        if state.end > Date() {
            begin(minutes: state.end.timeIntervalSinceNow / 60, label: state.label, persist: false)
            host?.log("Resumed timer '\(state.label)' with \(Self.format(state.end.timeIntervalSinceNow)) left")
        } else {
            clearState()
            host?.notify(title: "\(state.label) timer finished", message: "It ended while MouseGestures wasn't running.")
        }
    }

    public func stopService() {
        serviceRunning = false
        timer?.invalidate(); timer = nil   // state stays on disk; the service resumes it when switched back on
    }

    // MARK: UI — live status panel

    public var hasCustomSettingsView: Bool { true }

    public func makeSettingsView() -> NSView? { FocusTimerPanel(plugin: self) }

    fileprivate var remaining: TimeInterval? {
        guard let end = endDate, end > Date() else { return nil }
        return end.timeIntervalSinceNow
    }
    fileprivate func panelStart() { begin(minutes: host?.number("defaultMinutes", default: 25) ?? 25, label: "Focus") }
    fileprivate func panelCancel() { clear() }

    // MARK: timer core (main thread)

    private func begin(minutes: Double, label: String, persist: Bool = true) {
        timer?.invalidate()
        self.label = label
        endDate = Date().addingTimeInterval(minutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: false) { [weak self] _ in self?.finish() }
        if persist, serviceRunning { saveState() }
    }

    private func clear() {
        timer?.invalidate(); timer = nil; endDate = nil
        clearState()
    }

    private func finish() {
        let done = label
        clear()
        if host?.bool("playSound", default: true) ?? true {
            NSSound(named: NSSound.Name(host?.string("sound", default: "Glass") ?? "Glass"))?.play()
        }
        host?.notify(title: "\(done) timer done", message: "Time's up")
    }

    // MARK: persistence

    private struct State: Codable { let end: Date; let label: String }
    private var stateURL: URL? { host?.storageDirectory.appendingPathComponent("timer.json") }
    private func saveState() {
        guard let url = stateURL, let end = endDate, let data = try? JSONEncoder().encode(State(end: end, label: label)) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private func loadState() -> State? {
        guard let url = stateURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }
    private func clearState() { if let url = stateURL { try? FileManager.default.removeItem(at: url) } }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up)); let m = s / 60
        return m >= 1 ? "\(m) min" + (s % 60 > 0 ? " \(s % 60) s" : "") : "\(s) s"
    }
}

/// The custom view shown in the settings sheet.
private final class FocusTimerPanel: NSView {
    private weak var plugin: FocusTimerPlugin?
    private let status = NSTextField(labelWithString: "")
    private var tick: Timer?

    init(plugin: FocusTimerPlugin) {
        self.plugin = plugin
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 90))
        let title = NSTextField(labelWithString: "Current timer")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        status.font = .monospacedDigitSystemFont(ofSize: 22, weight: .regular)
        let start = NSButton(title: "Start", target: self, action: #selector(startTapped))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        let buttons = NSStackView(views: [start, cancel]); buttons.spacing = 8
        let stack = NSStackView(views: [title, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        refresh()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self, self.window != nil || self.superview == nil else { t.invalidate(); return }
            self.refresh()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { tick?.invalidate() }

    private func refresh() {
        if let r = plugin?.remaining {
            let s = Int(r.rounded(.up)); status.stringValue = String(format: "%d:%02d", s / 60, s % 60)
        } else { status.stringValue = "No timer running" }
    }
    @objc private func startTapped() { plugin?.panelStart(); refresh() }
    @objc private func cancelTapped() { plugin?.panelCancel(); refresh() }
}
