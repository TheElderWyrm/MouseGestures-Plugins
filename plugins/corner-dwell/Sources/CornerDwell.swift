import Cocoa
import MouseGestures

@objc(CornerDwellPlugin)
public final class CornerDwellPlugin: NSObject, ExternalTriggerPlugin {
    public var identifier: String { "com.mousegestures.lib.cornerdwell" }
    public var name: String { "Corner Dwell" }
    public var summary: String { "Rest the pointer in a corner" }
    public var version: String { "1.0.0" }
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
    private let size: CGFloat = 6        // corner hot-area, points
    private let dwell: TimeInterval = 0.9

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
