import AppKit
import ApplicationServices

@MainActor
enum TextInserter {
    enum Outcome {
        case pasted
        case copied
    }

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    static func deliver(_ text: String, keepInClipboard: Bool) -> Outcome {
        let pasteboard = NSPasteboard.general
        guard focusedElementIsEditable() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copied
        }

        let saved = keepInClipboard ? [] : snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount
        sendCommandV()

        if !keepInClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard pasteboard.changeCount == ourChange else { return }
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
        return .pasted
    }

    static func focusedElementIsEditable() -> Bool {
        if let app = NSWorkspace.shared.frontmostApplication {
            // Electron and Chromium only build their accessibility tree when asked.
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let element = focused as! AXUIElement

        if let role = stringAttribute(element, kAXRoleAttribute), editableRoles.contains(role) {
            return true
        }
        if hasAttribute(element, "AXEditableAncestor") {
            return true
        }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue && hasAttribute(element, kAXSelectedTextRangeAttribute)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func hasAttribute(_ element: AXUIElement, _ name: String) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success && value != nil
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
