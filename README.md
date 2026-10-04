# MouseGestures Official Plugins

The official MouseGestures **plugin library**. The app connects to it automatically: Developer ▸ Plugin Management ▸ Add Plugins. Format details: `docs/PLUGIN_LIBRARIES.md` in the app repo.

| Plugin | Kind | What it does | Permissions |
|---|---|---|---|
| Text Tools | action | UPPER/lower/Title case, clean whitespace, sort lines, paste as plain text (on selection or clipboard) | keystrokes |
| System Toggles | action | Dark mode, lock screen, sleep display, screen saver, Dock auto-hide, empty Trash | keystrokes, AppleScript |
| Quick Launch | action | Open URL / file / folder / app; search selection on the web; open clipboard URL | keystrokes |
| Finder Helpers | action | Copy selected paths, Terminal here, new Finder window, toggle hidden files | keystrokes, AppleScript |
| Focus Timer | action | Start / check / cancel a countdown with a notification | none |
| Mouse Shake | detection | Trigger: shake the pointer side to side | — |
| Corner Dwell | detection | Triggers: rest the pointer in a corner ~1 s | — |
| System Events | detection | Triggers: wake, lock/unlock, display change, power plugged/unplugged | — |

Detection plugins appear in the gesture editor as a **Plugin** trigger with a picker for their triggers.

## Building

```
python3 build.py [--sdk <Products/Release dir with MouseGestures.swiftmodule>] [--only slug ...]
```

Compiles each `plugins/<slug>/Sources`, wraps it as `<id>.plugin`, ad-hoc signs it, zips it into `dist/`
and rewrites `library.json` (SHA-256 included). Plugins import the app's own module and resolve its
symbols at load time, so rebuild against the app version you target (`minAppVersion` in `plugin.json`).
Commit `dist/` and `library.json` together.

## Settings, services, UI

Plugins can also conform to `PluginExtension` to add a settings form, a background service and a custom
settings view (see `docs/PLUGIN_LIBRARIES.md` in the app repo). Focus Timer demonstrates all three;
most other plugins declare settings.

## Writing a plugin

Action plugin: subclass `NSObject`, conform to `GestureActionPlugin`, `@objc(Name)`.
Detection plugin: subclass `NSObject`, conform to `ExternalTriggerPlugin`, call `host.fire(triggerId:)`.
Copy any `plugins/*` directory as a template; `plugin.json` holds the manifest entry.
