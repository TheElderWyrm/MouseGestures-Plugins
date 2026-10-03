import Cocoa
import MouseGestures

@objc(FocusTimerPlugin)
public final class FocusTimerPlugin: NSObject, GestureActionPlugin {
    public var identifier: String { "com.mousegestures.lib.focustimer" }
    public var name: String { "Focus Timer" }
    public override var description: String { "Countdown timer with a notification when it ends" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "timer", accessibilityDescription: nil) }

    private var timer: Timer?
    private var endDate: Date?
    private var label = "Timer"

    public var providedActions: [PluginAction] {[
        PluginAction(id: "start", name: "Start Timer", description: "Start (or restart) the countdown",
                     requiresParameters: true,
                     supportedParameters: [
                        ParameterDefinition(key: "minutes", name: "Minutes", type: .number, defaultValue: AnyCodable(25),
                                            description: "Length of the countdown", validation: ValidationRule(minValue: 0.1, maxValue: 600)),
                        ParameterDefinition(key: "label", name: "Label", type: .string, defaultValue: AnyCodable("Focus"), description: "Shown when time is up"),
                     ], icon: "timer"),
        PluginAction(id: "status", name: "Show Time Remaining", description: "Notify how long is left", icon: "hourglass"),
        PluginAction(id: "cancel", name: "Cancel Timer", description: "Stop the running timer", icon: "xmark.circle"),
    ]}

    private var context: PluginContext?
    public func initialize(context: PluginContext) throws { self.context = context }
    public func cleanup() { DispatchQueue.main.async { self.timer?.invalidate() }; timer = nil; context = nil }
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "start":
            let minutes = min(600, max(0.1, parameters.number(for: "minutes") ?? 25))
            let name = parameters.string(for: "label") ?? "Focus"
            DispatchQueue.main.async { [self] in
                timer?.invalidate()
                label = name
                endDate = Date().addingTimeInterval(minutes * 60)
                timer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: false) { [weak self] _ in
                    self?.finish()
                }
            }
            context.showNotification(title: "\(name) timer started", message: Self.format(minutes * 60), style: .info)
        case "status":
            guard let end = endDate, end > Date() else {
                context.showNotification(title: "Focus Timer", message: "No timer running", style: .info); return
            }
            context.showNotification(title: "\(label): time remaining", message: Self.format(end.timeIntervalSinceNow), style: .info)
        case "cancel":
            DispatchQueue.main.async { [self] in timer?.invalidate(); timer = nil; endDate = nil }
            context.showNotification(title: "Focus Timer", message: "Timer cancelled", style: .info)
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private func finish() {
        endDate = nil; timer = nil
        NSSound(named: "Glass")?.play()
        context?.showNotification(title: "\(label) timer done", message: "Time's up", style: .success)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up)); let m = s / 60
        return m >= 1 ? "\(m) min" + (s % 60 > 0 ? " \(s % 60) s" : "") : "\(s) s"
    }
}
