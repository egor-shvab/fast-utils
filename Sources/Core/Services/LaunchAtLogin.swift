import Observation
import OSLog
import ServiceManagement

/// "Open at Login" via `SMAppService.mainApp`. Registers the app at its current location,
/// so it should run from /Applications (`scripts/build.sh --install`).
@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "launchAtLogin")

    public init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login change failed: \(String(describing: error), privacy: .public)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
