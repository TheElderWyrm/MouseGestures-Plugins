import Cocoa
import MouseGestures

@objc(MouseShakePlugin)
public final class MouseShakePlugin: NSObject, ExternalTriggerPlugin {
    public var identifier: String { "com.mousegestures.lib.mouseshake" }
    public var name: String { "Mouse Shake" }
    public var summary: String { "Shake the pointer left and right" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "cursorarrow.motionlines" }
    public var triggers: [ExternalTriggerDefinition] {
        [ExternalTriggerDefinition(id: "shake", name: "Shake", summary: "Four quick direction changes within 0.8 s")]
    }

    private var monitor: Any?
    private weak var host: ExternalTriggerHost?

    // Tuning
    private let minTravel: CGFloat = 70        // points between reversals
    private let window: TimeInterval = 0.8     // seconds
    private let reversalsNeeded = 4
    private let cooldown: TimeInterval = 1.2

    private var direction = 0
    private var segmentStartX: CGFloat = 0
    private var lastX: CGFloat = 0
    private var reversals: [Date] = []
    private var lastFire = Date.distantPast

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.moved(NSEvent.mouseLocation)
        }
        host.log("Mouse Shake started")
    }

    public func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        host = nil
    }

    private func moved(_ p: NSPoint) {
        let dx = p.x - lastX
        lastX = p.x
        guard abs(dx) >= 1 else { return }
        let dir = dx > 0 ? 1 : -1
        if direction == 0 { direction = dir; segmentStartX = p.x; return }
        guard dir != direction else { return }
        // Direction flipped: it only counts if the stroke we just finished was long enough.
        if abs(p.x - segmentStartX) >= minTravel || segmentStartX == 0 {
            let now = Date()
            reversals.append(now)
            reversals.removeAll { now.timeIntervalSince($0) > window }
            if reversals.count >= reversalsNeeded, now.timeIntervalSince(lastFire) > cooldown {
                lastFire = now
                reversals.removeAll()
                host?.fire(triggerId: "shake")
            }
            segmentStartX = p.x
        }
        direction = dir
    }
}
