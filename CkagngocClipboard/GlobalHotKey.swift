import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKey {
    var onPress: (() -> Void)?

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = noErr

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        eventHandlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                var identifier = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard result == noErr, identifier.id == 1, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    hotKey.onPress?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        if eventHandlerStatus != noErr {
            eventHandlerReference = nil
        }
    }

    func register(_ shortcut: Shortcut) throws {
        guard eventHandlerStatus == noErr else {
            throw HotKeyError.registrationFailed(eventHandlerStatus)
        }
        unregisterHotKey()
        let identifier = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyReference
        )
        guard status == noErr else {
            hotKeyReference = nil
            throw HotKeyError.registrationFailed(status)
        }
    }

    private func unregisterHotKey() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}

private enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Không đăng ký được phím tắt (mã lỗi \(status))."
        }
    }
}
