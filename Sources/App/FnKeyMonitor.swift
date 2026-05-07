import Cocoa
import CoreGraphics

/// Monitors the Fn key via a CGEvent tap.
/// Calls `onFnDown` when Fn is pressed and `onFnUp` when released.
/// Returns nil from the tap callback to suppress the system emoji picker.
///
/// Requires Accessibility permission (CGEvent tap needs it for `.defaultTap`).
final class FnKeyMonitor {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Set by the callback; NOT accessed from multiple threads (tap runs on main RunLoop).
    fileprivate var fnIsDown = false

    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?

    /// 0x800000 = NX_SECONDARYFNMASK — the flag bit for the Fn key.
    fileprivate static let fnBit = CGEventFlags(rawValue: 0x80_0000)

    /// Installs the event tap on the current run loop. Returns `false` if the tap
    /// could not be created (usually means Accessibility permission is missing).
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // active — can suppress events
            eventsOfInterest: mask,
            callback: fnTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        fnIsDown = false
    }

    deinit { stop() }
}

// ── C-convention callback ─────────────────────────────────────────────────────
// Runs on the main RunLoop (same thread that installed the tap).

private func fnTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // If the tap is disabled by the system (e.g. timeout), re-enable it.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo,
           let tap = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo)
                .takeUnretainedValue().eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged, let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let flags = event.flags
    let fnDown = flags.contains(FnKeyMonitor.fnBit)

    if fnDown, !monitor.fnIsDown {
        monitor.fnIsDown = true
        monitor.onFnDown?()
        return nil  // suppress → no emoji picker
    }

    if !fnDown, monitor.fnIsDown {
        monitor.fnIsDown = false
        monitor.onFnUp?()
        return nil
    }

    // Other flag changes (Shift, Control, etc.) — pass through.
    return Unmanaged.passUnretained(event)
}
