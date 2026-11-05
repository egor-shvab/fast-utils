import Foundation

/// System privacy permissions a feature may need. Core shows those required by enabled
/// features in onboarding and in Settings → Permissions.
public enum Permission: String, Hashable, Sendable, CaseIterable {
    /// Screen Recording: capturing the screen for OCR.
    case screenRecording
    /// Accessibility: simulating ⌘V / ⌘C in other apps.
    case accessibility
    /// "Paste from Other Apps" (macOS 15.4+): reading the clipboard without an alert each time.
    case pasteboard

    public var title: String {
        switch self {
        case .screenRecording: String(localized: "permission.screenRecording.title")
        case .accessibility: String(localized: "permission.accessibility.title")
        case .pasteboard: String(localized: "permission.pasteboard.title")
        }
    }

    public var explanation: String {
        switch self {
        case .screenRecording: String(localized: "permission.screenRecording.explanation")
        case .accessibility: String(localized: "permission.accessibility.explanation")
        case .pasteboard: String(localized: "permission.pasteboard.explanation")
        }
    }

    public var icon: String {
        switch self {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .pasteboard: "doc.on.clipboard"
        }
    }

    /// The pane in System Settings → Privacy & Security.
    public var settingsURL: URL {
        let anchor = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        case .pasteboard: "Privacy_Pasteboard"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

public enum PermissionStatus: Equatable, Sendable {
    case granted
    /// Not granted yet; requesting may show a system prompt.
    case notGranted
    /// Explicitly denied; only System Settings can change it.
    case denied
}
