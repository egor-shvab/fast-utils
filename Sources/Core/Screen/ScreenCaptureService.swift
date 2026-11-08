import AppKit
import ScreenCaptureKit

/// A full-resolution snapshot of one display.
public struct ScreenSnapshot: @unchecked Sendable {
    /// The screen frame in AppKit global coordinates (points, bottom-left origin).
    public let frame: CGRect
    public let scale: CGFloat
    public let image: CGImage
    public let displayID: CGDirectDisplayID

    public init(frame: CGRect, scale: CGFloat, image: CGImage, displayID: CGDirectDisplayID) {
        self.frame = frame
        self.scale = scale
        self.image = image
        self.displayID = displayID
    }
}

public enum ScreenCaptureError: Error, Equatable {
    case notPermitted
    case noDisplays
    /// Anything else (a transient ScreenCaptureKit failure): asking for permission would not help.
    case failed(String)

    /// The user declined, or the app has no Screen Recording access. `preflight` is
    /// `CGPreflightScreenCaptureAccess()`: it covers errors that do not say "declined".
    static func classify(_ error: Error, preflight: Bool) -> ScreenCaptureError {
        if let error = error as? ScreenCaptureError { return error }
        if (error as? SCStreamError)?.code == .userDeclined || !preflight { return .notPermitted }
        return .failed(String(describing: error))
    }
}

/// Snapshots of all displays via ScreenCaptureKit (`CGWindowListCreateImage` is deprecated
/// since macOS 15). FastUtils' own windows (HUD, panels) are excluded from the snapshot.
@MainActor
public final class ScreenCaptureService {
    public init() {}

    public func captureAllScreens() async throws -> [ScreenSnapshot] {
        do {
            return try await capture()
        } catch {
            throw ScreenCaptureError.classify(error, preflight: CGPreflightScreenCaptureAccess())
        }
    }

    private func capture() async throws -> [ScreenSnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }

        var result: [ScreenSnapshot] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value })
            else { continue }
            let scale = screen.backingScaleFactor
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(ScreenSnapshot(frame: screen.frame, scale: scale, image: image, displayID: display.displayID))
        }
        guard !result.isEmpty else { throw ScreenCaptureError.noDisplays }
        return result
    }
}

public extension ScreenSnapshot {
    /// Crops a rect given in global AppKit points (bottom-left origin) out of the snapshot.
    func crop(_ rect: CGRect) -> CGImage? {
        image.cropping(to: Self.pixelRect(for: rect, screenFrame: frame, imageSize: CGSize(width: image.width, height: image.height)))
    }

    /// Global points → image pixels (top-left origin), using the real image/screen ratio
    /// rather than `scale`, so it stays right if the system returned a different size.
    static func pixelRect(for rect: CGRect, screenFrame: CGRect, imageSize: CGSize) -> CGRect {
        let sx = imageSize.width / screenFrame.width
        let sy = imageSize.height / screenFrame.height
        let local = rect.intersection(screenFrame).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        return CGRect(
            x: (local.minX * sx).rounded(.down),
            y: ((screenFrame.height - local.maxY) * sy).rounded(.down),
            width: (local.width * sx).rounded(.up),
            height: (local.height * sy).rounded(.up)
        )
    }
}
