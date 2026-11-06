import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// View-local state. Not `@State`: in the macOS 27 SDK `@State` is a macro whose plugin
/// ships only with Xcode (see CLAUDE.md), so local view state lives in an ObservableObject.
@MainActor
final class RecorderState: ObservableObject {
    @Published var isRecording = false
    @Published var liveModifiers: Shortcut.Modifiers = []
    @Published var error: String?
    var monitor: Any?
}

/// Records a global shortcut for one action.
/// Click → press a combination. Esc cancels, ⌫ clears. Hot keys are paused while recording
/// so the combination reaches the recorder instead of running an action.
struct ShortcutRecorder: View {
    let id: ActionID
    let hotkeys: HotkeyService

    @StateObject private var state = RecorderState()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(label)
                        .monospacedDigit()
                        .frame(minWidth: 150)
                        .foregroundStyle(state.isRecording || current == nil ? .secondary : .primary)
                }
                .buttonStyle(.bordered)
                .tint(state.isRecording ? .accentColor : nil)
                .help(String(localized: "shortcut.recorder.help"))

                Button {
                    stopRecording()
                    state.error = nil
                    hotkeys.setShortcut(nil, for: id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(current == nil)
                .help(String(localized: "shortcut.recorder.clear"))
                .accessibilityLabel(String(localized: "shortcut.recorder.clear"))

                Button {
                    stopRecording()
                    state.error = nil
                    hotkeys.reset([id])
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(current == hotkeys.defaultShortcut(for: id))
                .help(String(localized: "shortcut.recorder.reset"))
                .accessibilityLabel(String(localized: "shortcut.recorder.reset"))
            }
            if let note {
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(note.isError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var current: Shortcut? { hotkeys.shortcut(for: id) }

    private var label: String {
        if state.isRecording {
            return state.liveModifiers.isEmpty
                ? String(localized: "shortcut.recorder.press")
                : state.liveModifiers.symbols + "…"
        }
        return current?.description ?? String(localized: "shortcut.recorder.none")
    }

    /// An error from the last attempt, otherwise a warning about the current shortcut.
    private var note: (text: String, isError: Bool)? {
        if let error = state.error { return (error, true) }
        if let current, case .warning(let text) = hotkeys.check(current, for: id) { return (text, false) }
        return nil
    }

    private func toggleRecording() {
        state.isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        state.error = nil
        state.isRecording = true
        state.liveModifiers = []
        hotkeys.isPaused = true
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        if let monitor = state.monitor { NSEvent.removeMonitor(monitor) }
        state.monitor = nil
        if state.isRecording { hotkeys.isPaused = false }
        state.isRecording = false
        state.liveModifiers = []
    }

    /// Returns `nil` to swallow the event.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            state.liveModifiers = Shortcut.Modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            return event
        }
        let bare = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        if bare && Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return nil
        }
        if bare && (Int(event.keyCode) == kVK_Delete || Int(event.keyCode) == kVK_ForwardDelete) {
            stopRecording()
            hotkeys.setShortcut(nil, for: id)
            return nil
        }
        guard let shortcut = Shortcut(event: event) else {
            NSSound.beep()
            return nil
        }
        stopRecording()
        if case .blocked(let reason) = hotkeys.check(shortcut, for: id) {
            state.error = String(format: String(localized: "shortcut.recorder.refused"), shortcut.description, reason)
        } else {
            hotkeys.setShortcut(shortcut, for: id)
        }
        return nil
    }
}
