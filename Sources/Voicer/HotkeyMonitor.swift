import AppKit

@MainActor
final class HotkeyMonitor {
    enum Event {
        case start(OutputMode)
        case stop
        case cancel
        case locked
    }

    private enum State {
        case idle
        case pressing(OutputMode, since: Date)
        case awaitingToggleRelease(OutputMode)
        case locked(OutputMode)
        case waitingForRelease
    }

    private static let tapThreshold: TimeInterval = 0.3
    private static let escapeKeyCode: UInt16 = 53

    var bindings: [OutputMode: Shortcut] = [:]
    var behavior = TriggerBehavior.holdOrTap
    var isSuspended = false {
        didSet { if isSuspended { state = .idle } }
    }
    var onEvent: (Event) -> Void = { _ in }
    var onModifiersChanged: (Set<ModifierKey>) -> Void = { _ in }

    private var state = State.idle
    private var activeModifiers = Set<ModifierKey>()
    private var heldTriggerKey: UInt16?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DebugLog.write("event tap creation failed, AX trusted=\(AXIsProcessTrusted())")
            return false
        }
        DebugLog.write("event tap created, listen=\(CGPreflightListenEventAccess()) post=\(CGPreflightPostEventAccess()) enabled=\(CGEvent.tapIsEnabled(tap: tap))")

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    func reset() {
        state = .idle
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged:
            activeModifiers = ModifierKey.active(in: event.flags.rawValue)
            onModifiersChanged(activeModifiers)
            if !isSuspended { evaluate() }
            return false
        case .keyDown:
            guard !isSuspended else { return false }
            return handleKeyDown(
                UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp:
            guard !isSuspended else { return false }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == heldTriggerKey else { return false }
            heldTriggerKey = nil
            evaluate()
            return true
        default:
            return false
        }
    }

    private func isHeld(_ shortcut: Shortcut) -> Bool {
        guard shortcut.modifiersMatch(activeModifiers) else { return false }
        return shortcut.keyCode == nil || shortcut.keyCode == heldTriggerKey
    }

    private func modeHeld() -> OutputMode? {
        OutputMode.allCases.first { mode in bindings[mode].map(isHeld) ?? false }
    }

    private func evaluate() {
        switch state {
        case .idle:
            if let mode = modeHeld() { begin(mode) }

        case .pressing(let mode, let since):
            guard let shortcut = bindings[mode], !isHeld(shortcut) else { return }
            if shortcut.hasExtraModifiers(activeModifiers) {
                // Part of a bigger shortcut like ⌃⌥⌘K.
                finish(.cancel)
            } else if Date().timeIntervalSince(since) < Self.tapThreshold {
                if behavior == .holdOrTap {
                    state = .locked(mode)
                    onEvent(.locked)
                } else {
                    finish(.cancel)
                }
            } else {
                finish(.stop)
            }

        case .awaitingToggleRelease(let mode):
            if let shortcut = bindings[mode], !isHeld(shortcut) {
                state = .locked(mode)
                onEvent(.locked)
            }

        case .locked(let mode):
            if let shortcut = bindings[mode], isHeld(shortcut) { finish(.stop) }

        case .waitingForRelease:
            if activeModifiers.isEmpty, heldTriggerKey == nil { state = .idle }
        }
    }

    private func begin(_ mode: OutputMode) {
        state = behavior == .toggle ? .awaitingToggleRelease(mode) : .pressing(mode, since: Date())
        onEvent(.start(mode))
    }

    private func finish(_ event: Event) {
        state = .waitingForRelease
        onEvent(event)
        evaluate()
    }

    private func handleKeyDown(_ keyCode: UInt16, isRepeat: Bool) -> Bool {
        if keyCode == heldTriggerKey { return true }

        if case .idle = state,
           let mode = OutputMode.allCases.first(where: {
               guard let shortcut = bindings[$0] else { return false }
               return shortcut.keyCode == keyCode && shortcut.modifiersMatch(activeModifiers)
           }) {
            heldTriggerKey = keyCode
            begin(mode)
            return true
        }

        if case .locked(let mode) = state {
            if keyCode == Self.escapeKeyCode {
                state = .idle
                onEvent(.cancel)
                return true
            }
            if bindings[mode]?.keyCode == keyCode, bindings[mode]?.modifiersMatch(activeModifiers) == true {
                heldTriggerKey = keyCode
                finish(.stop)
                return true
            }
            return false
        }

        switch state {
        case .pressing, .awaitingToggleRelease:
            // The modifiers were part of an ordinary shortcut such as ⌃⌥→.
            if !isRepeat { finish(.cancel) }
        default:
            break
        }
        return false
    }
}
