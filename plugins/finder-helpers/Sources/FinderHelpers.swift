import Cocoa
import MouseGestures

@objc(FinderHelpersPlugin)
public final class FinderHelpersPlugin: NSObject, GestureActionPlugin {
    public var identifier: String { "com.mousegestures.lib.finderhelpers" }
    public var name: String { "Finder Helpers" }
    public override var description: String { "Finder shortcuts: copy path, Terminal here, new window" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .file }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "copy_path", name: "Copy Path of Selection", description: "Copy the POSIX path(s) of the selected Finder items", icon: "doc.on.doc"),
        PluginAction(id: "terminal_here", name: "Open Terminal Here", description: "Open Terminal at the front Finder window's folder", icon: "terminal"),
        PluginAction(id: "new_window", name: "New Finder Window", description: "Open a new Finder window at your home folder", icon: "macwindow.badge.plus"),
        PluginAction(id: "show_hidden", name: "Toggle Hidden Files", description: "Show or hide hidden files in Finder (⌘⇧.)", icon: "eye"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "copy_path":
            let out = try Self.osascript("""
            tell application "Finder"
              set sel to selection as alias list
              if sel is {} then set sel to {(target of front window) as alias}
              set paths to {}
              repeat with f in sel
                set end of paths to POSIX path of f
              end repeat
              set AppleScript's text item delimiters to linefeed
              return paths as text
            end tell
            """)
            guard !out.isEmpty else { throw PluginError.executionFailed("Nothing selected in Finder") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(out, forType: .string)
            context.showNotification(title: "Path copied", message: out, style: .success)
        case "terminal_here":
            let path = try Self.osascript("tell application \"Finder\" to return POSIX path of (target of front window as alias)")
            guard !path.isEmpty else { throw PluginError.executionFailed("No Finder window is open") }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Terminal", path]
            try p.run()
        case "new_window":
            try context.executeAppleScript("tell application \"Finder\"\n make new Finder window to home\n activate\nend tell")
        case "show_hidden":
            context.sendKeyboardShortcut(keyCode: 47, modifiers: [.maskCommand, .maskShift]) // ⌘⇧.
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private static func osascript(_ source: String) throws -> String {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw PluginError.executionFailed("Bad script") }
        let result = script.executeAndReturnError(&err)
        if let err = err { throw PluginError.executionFailed("AppleScript: \(err[NSAppleScript.errorMessage] ?? "failed")") }
        return result.stringValue ?? ""
    }
}
