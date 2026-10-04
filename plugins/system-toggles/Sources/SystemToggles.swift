import Cocoa
import MouseGestures

@objc(SystemTogglesPlugin)
public final class SystemTogglesPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.systemtoggles" }
    public var name: String { "System Toggles" }
    public override var description: String { "Quick system switches" }
    public var version: String { "1.1.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .system }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil) }

    private var settings: PluginHost?
    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "confirmEmptyTrash", title: "Ask before emptying the Trash", kind: .toggle, defaultValue: AnyCodable(true),
                           help: "A gesture is easy to trigger by accident; keep this on unless you're sure."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "toggle_dark_mode", name: "Toggle Dark Mode", description: "Switch between light and dark appearance", icon: "moon.circle"),
        PluginAction(id: "lock_screen", name: "Lock Screen", description: "Lock the Mac (⌃⌘Q)", icon: "lock"),
        PluginAction(id: "sleep_display", name: "Sleep Display", description: "Turn the display off now", icon: "display"),
        PluginAction(id: "screen_saver", name: "Start Screen Saver", description: "Start the screen saver now", icon: "sparkles.tv"),
        PluginAction(id: "toggle_dock_autohide", name: "Toggle Dock Auto-Hide", description: "Show or hide the Dock automatically", icon: "dock.rectangle"),
        PluginAction(id: "empty_trash", name: "Empty Trash", description: "Empty the Trash (Finder may ask to confirm)", icon: "trash"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "toggle_dark_mode":
            try context.executeAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case "lock_screen":
            context.sendKeyboardShortcut(keyCode: 12, modifiers: [.maskControl, .maskCommand]) // ⌃⌘Q
        case "sleep_display":
            try run("/usr/bin/pmset", ["displaysleepnow"])
        case "screen_saver":
            try run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case "toggle_dock_autohide":
            try context.executeAppleScript("tell application \"System Events\" to tell dock preferences to set autohide to not autohide")
        case "empty_trash":
            if settings?.bool("confirmEmptyTrash", default: true) ?? true {
                var ok = false
                DispatchQueue.main.sync {
                    let alert = NSAlert()
                    alert.messageText = "Empty the Trash?"
                    alert.informativeText = "This permanently deletes everything in the Trash."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Empty Trash"); alert.addButton(withTitle: "Cancel")
                    NSApp.activate(ignoringOtherApps: true)
                    ok = alert.runModal() == .alertFirstButtonReturn
                }
                guard ok else { return }
            }
            try context.executeAppleScript("tell application \"Finder\" to empty trash")
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
    }
}
