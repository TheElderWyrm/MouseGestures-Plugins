import Cocoa
import IOKit.ps
import MouseGestures

@objc(SystemEventsPlugin)
public final class SystemEventsPlugin: NSObject, ExternalTriggerPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.systemevents" }
    public var name: String { "System Events" }
    public var summary: String { "Wake, lock, displays and power" }
    public var version: String { "1.1.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "bolt.badge.clock" }
    public var triggers: [ExternalTriggerDefinition] {[
        ExternalTriggerDefinition(id: "wake", name: "Mac woke from sleep"),
        ExternalTriggerDefinition(id: "screen_locked", name: "Screen locked"),
        ExternalTriggerDefinition(id: "screen_unlocked", name: "Screen unlocked"),
        ExternalTriggerDefinition(id: "display_changed", name: "Display connected or removed"),
        ExternalTriggerDefinition(id: "power_plugged", name: "Power adapter plugged in"),
        ExternalTriggerDefinition(id: "power_unplugged", name: "Power adapter unplugged"),
    ]}

    private weak var host: ExternalTriggerHost?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?
    private var onAC: Bool?
    private var displayDebounce: Timer?
    private var settings: PluginHost?

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "displaySettle", title: "Display change settle time",
                           kind: .number(min: 0.5, max: 5, step: 0.5, unit: "s"), defaultValue: AnyCodable(1.0),
                           help: "Connecting a display produces several change events; the trigger fires once after this quiet period."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        func observe(_ center: NotificationCenter, _ name: NSNotification.Name, _ id: String) {
            tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.host?.fire(triggerId: id)
            }))
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, "wake")
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked"), "screen_locked")
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked"), "screen_unlocked")
        // Display changes arrive in bursts; settle for a second before firing once.
        tokens.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayDebounce?.invalidate()
            self?.displayDebounce = Timer.scheduledTimer(withTimeInterval: self?.settings?.number("displaySettle", default: 1.0) ?? 1.0, repeats: false) { _ in
                self?.host?.fire(triggerId: "display_changed")
            }
        }))
        onAC = Self.isOnAC()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            Unmanaged<SystemEventsPlugin>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            powerSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        host.log("System Events started")
    }

    public func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
        if let s = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode) }
        powerSource = nil
        displayDebounce?.invalidate()
        host = nil
    }

    private func powerChanged() {
        let now = Self.isOnAC()
        guard let was = onAC, was != now else { onAC = now; return }
        onAC = now
        host?.fire(triggerId: now ? "power_plugged" : "power_unplugged")
    }

    private static func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPSACPowerValue
    }
}
