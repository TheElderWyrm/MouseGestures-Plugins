import Cocoa
import MouseGestures

@objc(QuickLaunchPlugin)
public final class QuickLaunchPlugin: NSObject, GestureActionPlugin {
    public var identifier: String { "com.mousegestures.lib.quicklaunch" }
    public var name: String { "Quick Launch" }
    public override var description: String { "Open URLs, files, folders and apps; web search" }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: nil) }

    private static let engines: [String: (String, String)] = [
        "google": ("Google", "https://www.google.com/search?q=%s"),
        "duckduckgo": ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        "wikipedia": ("Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"),
        "youtube": ("YouTube", "https://www.youtube.com/results?search_query=%s"),
        "maps": ("Apple Maps", "https://maps.apple.com/?q=%s"),
    ]

    public var providedActions: [PluginAction] {[
        PluginAction(id: "open_url", name: "Open URL", description: "Open a web address in the default browser",
                     requiresParameters: true,
                     supportedParameters: [ParameterDefinition(key: "url", name: "URL", type: .url, required: true, description: "https://…")],
                     icon: "link"),
        PluginAction(id: "open_path", name: "Open File or Folder", description: "Open a file or folder",
                     requiresParameters: true,
                     supportedParameters: [ParameterDefinition(key: "path", name: "Path", type: .path, required: true, description: "File or folder")],
                     icon: "folder"),
        PluginAction(id: "open_app", name: "Open Application", description: "Launch or activate an app",
                     requiresParameters: true,
                     supportedParameters: [ParameterDefinition(key: "application", name: "Application", type: .application, required: true, description: "App name or path")],
                     icon: "app"),
        PluginAction(id: "search_selection", name: "Search Selection on the Web", description: "Search the selected text",
                     requiresParameters: true,
                     supportedParameters: [ParameterDefinition(
                        key: "engine", name: "Search engine", type: .selection, defaultValue: AnyCodable("google"),
                        description: "Where to search",
                        validation: ValidationRule(allowedValues: Self.engines.keys.sorted().map { AnyCodable($0) }),
                        displayValues: Dictionary(uniqueKeysWithValues: Self.engines.map { ($0.key, $0.value.0) }))],
                     icon: "magnifyingglass"),
        PluginAction(id: "open_clipboard_url", name: "Open URL from Clipboard", description: "Open the web address on the clipboard", icon: "doc.on.clipboard"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}

    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "open_url": return Self.webURL(parameters.string(for: "url")) == nil ? .invalid(error: "Enter a valid http(s) URL") : .valid
        case "open_path": return (parameters.string(for: "path") ?? "").isEmpty ? .invalid(error: "Choose a file or folder") : .valid
        case "open_app": return (parameters.string(for: "application") ?? "").isEmpty ? .invalid(error: "Choose an application") : .valid
        default: return .valid
        }
    }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "open_url":
            guard let url = Self.webURL(parameters.string(for: "url")) else { throw PluginError.invalidParameters("Invalid URL") }
            NSWorkspace.shared.open(url)
        case "open_path":
            let path = ((parameters.string(for: "path") ?? "") as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { throw PluginError.executionFailed("Not found: \(path)") }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case "open_app":
            let app = (parameters.string(for: "application") ?? "")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = app.hasPrefix("/") || app.hasSuffix(".app") ? [(app as NSString).expandingTildeInPath] : ["-a", app]
            try p.run()
        case "search_selection":
            let pb = NSPasteboard.general
            let before = pb.changeCount
            context.sendKeyboardShortcut(keyCode: 8, modifiers: .maskCommand)
            let deadline = Date().addingTimeInterval(0.6)
            while pb.changeCount == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            guard pb.changeCount != before, let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw PluginError.executionFailed("No text is selected")
            }
            let template = Self.engines[parameters.string(for: "engine") ?? "google"]?.1 ?? Self.engines["google"]!.1
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))) ?? text
            if let url = URL(string: template.replacingOccurrences(of: "%s", with: q)) { NSWorkspace.shared.open(url) }
        case "open_clipboard_url":
            guard let url = Self.webURL(NSPasteboard.general.string(forType: .string)) else { throw PluginError.executionFailed("Clipboard doesn't hold a web address") }
            NSWorkspace.shared.open(url)
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    static func webURL(_ s: String?) -> URL? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.contains(" ") else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), (u.host ?? "").contains(".") else { return nil }
        return u
    }
}
