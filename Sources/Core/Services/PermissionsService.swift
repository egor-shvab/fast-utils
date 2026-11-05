import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// Reads and requests system permissions. Abstracted so tests do not touch TCC.
@MainActor
public protocol PermissionChecker: AnyObject {
    func status(of permission: Permission) -> PermissionStatus
    func request(_ permission: Permission)
}

@MainActor
public final class SystemPermissionChecker: PermissionChecker {
    public init() {}

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .pasteboard:
            guard #available(macOS 15.4, *) else { return .granted }
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: return .granted
            case .alwaysDeny: return .denied
            default: return .notGranted
            }
        }
    }

    public func request(_ permission: Permission) {
        switch permission {
        case .screenRecording:
            // Shows the system prompt only the first time; afterwards it just returns the status.
            if !CGRequestScreenCaptureAccess() { NSWorkspace.shared.open(permission.settingsURL) }
        case .accessibility:
            // The string literal avoids the non-Sendable global `kAXTrustedCheckOptionPrompt`.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { NSWorkspace.shared.open(permission.settingsURL) }
        case .pasteboard:
            guard #available(macOS 15.4, *) else { return }
            if NSPasteboard.general.accessBehavior == .default {
                // A programmatic read triggers the system alert, after which the app appears in
                // System Settings. Nothing read here is kept.
                _ = NSPasteboard.general.string(forType: .string)
            } else {
                NSWorkspace.shared.open(permission.settingsURL)
            }
        }
    }
}

/// Current permission statuses. Refreshes when the app becomes active and, while a
/// permissions UI is visible, once a second (granting happens in System Settings, which
/// does not notify us).
@MainActor
@Observable
public final class PermissionsService {
    public private(set) var statuses: [Permission: PermissionStatus] = [:]

    @ObservationIgnored private let checker: any PermissionChecker
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    public init(checker: any PermissionChecker = SystemPermissionChecker()) {
        self.checker = checker
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notGranted
    }

    public func isGranted(_ permission: Permission) -> Bool { status(of: permission) == .granted }

    public func refresh() {
        var result: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases {
            result[permission] = checker.status(of: permission)
        }
        if result != statuses { statuses = result }
    }

    public func request(_ permission: Permission) {
        checker.request(permission)
        refresh()
    }

    public func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    /// Call from `onAppear` of a view that shows statuses; balance with `stopWatching()`.
    public func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}

/// Test double with settable statuses.
@MainActor
public final class FakePermissionChecker: PermissionChecker {
    public var statuses: [Permission: PermissionStatus] = [:]
    public private(set) var requested: [Permission] = []
    public init() {}
    public func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .notGranted }
    public func request(_ permission: Permission) { requested.append(permission) }
}
