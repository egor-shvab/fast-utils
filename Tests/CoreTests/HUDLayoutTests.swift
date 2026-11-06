import AppKit
import Testing
@testable import Core

@MainActor
struct HUDLayoutTests {
    @Test func longTextStaysWithinMaximumSize() {
        let hud = AppContext.testing().hud
        let long = String(repeating: "Закоммитил новое окно настроек с боковой панелью ", count: 8)
        hud.show("Скопировано 196 символов", detail: long)
        let frame = try! #require(hud.panel?.frame)
        #expect(frame.width <= HUDService.maxSize.width)
        #expect(frame.width > 200)
        #expect(frame.height <= HUDService.maxSize.height)
        // The content fills the panel exactly: nothing sticks out to the right.
        let content = try! #require(hud.panel?.contentView?.subviews.first)
        #expect(content.frame.size == frame.size)
        hud.panel?.orderOut(nil)
    }

    @Test func shortTextGivesCompactHUD() {
        let hud = AppContext.testing().hud
        hud.show("Готово")
        let frame = try! #require(hud.panel?.frame)
        #expect(frame.width < 200)
        #expect(frame.height < 70)
        hud.panel?.orderOut(nil)
    }
}
