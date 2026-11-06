import Carbon
import OSLog

/// Switches the system keyboard layout. Text Input Sources must only be called on the main
/// thread (two threads at once abort the process), hence `@MainActor`.
@MainActor
enum InputSourceSwitcher {
    /// Selects the first enabled keyboard layout for `language` ("ru", "en"). `false` if none.
    @discardableResult
    static func select(language: String) -> Bool {
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }
        for source in list {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { continue }
            let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
            if languages.first == language {
                return TISSelectInputSource(source) == noErr
            }
        }
        return false
    }
}
