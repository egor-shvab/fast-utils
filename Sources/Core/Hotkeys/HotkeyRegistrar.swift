import Carbon.HIToolbox

/// Registers system-wide hot keys. Abstracted so tests never grab real hot keys.
@MainActor
public protocol HotkeyRegistrar: AnyObject {
    var onPress: ((ActionID) -> Void)? { get set }
    /// Returns `false` if the system refused the combination.
    func register(_ shortcut: Shortcut, for id: ActionID) -> Bool
    func unregister(_ id: ActionID)
}

/// 'FUTS' — tags our hot keys so the handler ignores other events.
private let hotkeySignature: OSType = 0x4655_5453

/// Carbon `RegisterEventHotKey`: the standard way to get global hot keys without
/// Accessibility permission. Note: macOS does NOT report when another app already uses the
/// same combination — both registrations succeed (checked on macOS 27).
@MainActor
public final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    public var onPress: ((ActionID) -> Void)?

    private var refs: [ActionID: EventHotKeyRef] = [:]
    private var numbers: [ActionID: UInt32] = [:]
    private var idsByNumber: [UInt32: ActionID] = [:]
    private var nextNumber: UInt32 = 1
    private var handler: EventHandlerRef?

    public init() {}

    public func register(_ shortcut: Shortcut, for id: ActionID) -> Bool {
        installHandlerIfNeeded()
        unregister(id)

        let number = nextNumber
        nextNumber += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.modifiers.carbon,
            EventHotKeyID(signature: hotkeySignature, id: number),
            GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        numbers[id] = number
        idsByNumber[number] = id
        return true
    }

    public func unregister(_ id: ActionID) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        if let number = numbers.removeValue(forKey: id) {
            idsByNumber[number] = nil
        }
    }

    fileprivate func handlePress(_ number: UInt32) {
        guard let id = idsByNumber[number] else { return }
        onPress?(id)
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == hotkeySignature else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            // The dispatcher target delivers hot key events on the main thread.
            MainActor.assumeIsolated { registrar.handlePress(hotKeyID.id) }
            return noErr
        }, 1, &spec, context, &handler)
    }
}

/// Test double: remembers registrations and lets tests "press" a hot key.
@MainActor
public final class FakeHotkeyRegistrar: HotkeyRegistrar {
    public var onPress: ((ActionID) -> Void)?
    public private(set) var registered: [ActionID: Shortcut] = [:]

    public init() {}

    public func register(_ shortcut: Shortcut, for id: ActionID) -> Bool {
        registered[id] = shortcut
        return true
    }

    public func unregister(_ id: ActionID) { registered[id] = nil }

    public func press(_ id: ActionID) {
        guard registered[id] != nil else { return }
        onPress?(id)
    }
}
