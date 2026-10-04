import Cocoa
import MouseGestures

@objc(CornerDwellPlugin)
public final class CornerDwellPlugin: NSObject, ExternalTriggerPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.cornerdwell" }
    public var name: String { "Corner Dwell" }
    public var summary: String { "Rest the pointer in a corner" }
    public var version: String { "1.1.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "rectangle.inset.topright.filled" }
    public var triggers: [ExternalTriggerDefinition] {[
        ExternalTriggerDefinition(id: "top_left", name: "Top Left"),
        ExternalTriggerDefinition(id: "top_right", name: "Top Right"),
        ExternalTriggerDefinition(id: "bottom_left", name: "Bottom Left"),
        ExternalTriggerDefinition(id: "bottom_right", name: "Bottom Right"),
    ]}

    private var monitor: Any?
    private weak var host: ExternalTriggerHost?
    private var current: String?
    private var timer: Timer?
    private var settings: PluginHost?
    private var size: CGFloat { CGFloat(settings?.number("cornerSize", default: 6) ?? 6) }
    private var dwell: TimeInterval { settings?.number("dwell", default: 0.9) ?? 0.9 }

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "dwell", title: "Dwell time", kind: .number(min: 0.3, max: 3, step: 0.1, unit: "s"),
                           defaultValue: AnyCodable(0.9), help: "How long the pointer must rest in the corner."),
        PluginSettingField(key: "cornerSize", title: "Corner size", kind: .number(min: 2, max: 40, step: 2, unit: "pt"),
                           defaultValue: AnyCodable(6), help: "Size of the hot area at each screen corner."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.check() }
        host.log("Corner Dwell started")
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        timer?.invalidate(); timer = nil
        current = nil; host = nil
    }

    private func corner(at p: NSPoint) -> String? {
        for s in NSScreen.screens where s.frame.insetBy(dx: -1, dy: -1).contains(p) {
            let f = s.frame
            let left = p.x - f.minX < size, right = f.maxX - p.x < size
            let bottom = p.y - f.minY < size, top = f.maxY - p.y < size
            switch (left, right, top, bottom) {
            case (true, _, true, _): return "top_left"
            case (_, true, true, _): return "top_right"
            case (true, _, _, true): return "bottom_left"
            case (_, true, _, true): return "bottom_right"
            default: return nil
            }
        }
        return nil
    }

    private func check() {
        let c = corner(at: NSEvent.mouseLocation)
        guard c != current else { return }
        current = c
        timer?.invalidate(); timer = nil
        guard let c = c else { return }
        timer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
            guard let self = self, self.corner(at: NSEvent.mouseLocation) == c else { return }
            self.host?.fire(triggerId: c)
        }
    }
}
