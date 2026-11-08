import AppKit

/// After the preview overlay closes, SwiftUI stops sending hover to the list rows that were
/// under it until the list scrolls. A scroll by 1 pt and back in the same turn (nothing is
/// drawn in between, the position does not change) makes AppKit rebuild the tracking areas.
@MainActor
enum HoverTracking {
    static func refresh(in window: NSWindow?) {
        guard let root = window?.contentView else { return }
        for scrollView in scrollViews(in: root) {
            let clip = scrollView.contentView
            let origin = clip.bounds.origin
            clip.scroll(to: NSPoint(x: origin.x, y: origin.y + 1))
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }
}
