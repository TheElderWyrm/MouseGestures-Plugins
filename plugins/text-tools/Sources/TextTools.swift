import Cocoa
import MouseGestures

@objc(TextToolsPlugin)
public final class TextToolsPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.texttools" }
    public var name: String { "Text Tools" }
    public override var description: String { "Transform selected text or the clipboard" }
    public var version: String { "1.1.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "textformat", accessibilityDescription: nil) }

    private var context: PluginContext?
    private var settings: PluginHost?
    private var restoreClipboard: Bool { settings?.bool("restoreClipboard", default: true) ?? true }

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "restoreClipboard", title: "Restore the clipboard afterwards", kind: .toggle,
                           defaultValue: AnyCodable(true),
                           help: "When transforming a selection, put your previous clipboard contents back after pasting."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    private static let applyParam = ParameterDefinition(
        key: "applyToSelection", name: "Apply to selected text", type: .boolean,
        defaultValue: AnyCodable(true),
        description: "Copy the current selection, transform it and paste it back. Off = transform the clipboard only.")

    public var providedActions: [PluginAction] {
        func a(_ id: String, _ name: String, _ desc: String, _ icon: String, params: Bool = true) -> PluginAction {
            PluginAction(id: id, name: name, description: desc, requiresParameters: false,
                         supportedParameters: params ? [Self.applyParam] : [], icon: icon)
        }
        return [
            a("uppercase", "UPPERCASE", "Convert text to upper case", "textformat.size.larger"),
            a("lowercase", "lowercase", "Convert text to lower case", "textformat.size.smaller"),
            a("titlecase", "Title Case", "Capitalize each word", "textformat"),
            a("trim", "Clean Whitespace", "Trim lines, drop blank runs and double spaces", "scissors"),
            a("sort_lines", "Sort Lines", "Sort lines alphabetically", "arrow.up.arrow.down"),
            a("plain_paste", "Paste as Plain Text", "Paste the clipboard without formatting", "doc.plaintext", params: false),
        ]
    }

    public func initialize(context: PluginContext) throws { self.context = context }
    public func cleanup() { context = nil }
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        let apply = parameters.bool(for: "applyToSelection") ?? true
        switch action.id {
        case "uppercase": try transform(apply, context) { $0.uppercased() }
        case "lowercase": try transform(apply, context) { $0.lowercased() }
        case "titlecase": try transform(apply, context) { $0.capitalized }
        case "trim": try transform(apply, context, Self.clean)
        case "sort_lines":
            try transform(apply, context) { $0.components(separatedBy: "\n").sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: "\n") }
        case "plain_paste":
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            let saved = Self.snapshot()
            Self.set(text)
            context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand)
            if restoreClipboard { Self.restore(saved, after: 0.4) }
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    // MARK: helpers

    static func clean(_ s: String) -> String {
        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            if t.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(t)
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    private func transform(_ applyToSelection: Bool, _ context: PluginContext, _ f: (String) -> String) throws {
        let pb = NSPasteboard.general
        let saved = Self.snapshot()
        if applyToSelection {
            let before = pb.changeCount
            context.sendKeyboardShortcut(keyCode: 8, modifiers: .maskCommand) // ⌘C
            let deadline = Date().addingTimeInterval(0.6)
            while pb.changeCount == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            guard pb.changeCount != before else { throw PluginError.executionFailed("No text is selected") }
        }
        guard let text = pb.string(forType: .string) else { throw PluginError.executionFailed("No text to transform") }
        Self.set(f(text))
        if applyToSelection {
            context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand) // ⌘V
            if restoreClipboard { Self.restore(saved, after: 0.4) }
        }
    }

    private static func set(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private static func snapshot() -> [[(NSPasteboard.PasteboardType, Data)]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
    }

    private static func restore(_ items: [[(NSPasteboard.PasteboardType, Data)]], after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pb = NSPasteboard.general
            pb.clearContents()
            for entries in items {
                let item = NSPasteboardItem()
                for (t, d) in entries { item.setData(d, forType: t) }
                pb.writeObjects([item])
            }
        }
    }
}
