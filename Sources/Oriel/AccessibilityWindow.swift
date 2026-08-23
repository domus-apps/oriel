import AppKit
import ApplicationServices

/* Thin wrapper over an AXUIElement of role AXWindow. All frames are in AX
   space (top-left origin of the primary screen). */
struct AccessibilityWindow {
    let element: AXUIElement

    static func focused() -> AccessibilityWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AccessibilityWindow(element: unsafeDowncast(value, to: AXUIElement.self))
    }

    var frame: CGRect? {
        guard let position: CGPoint = copyValue(kAXPositionAttribute, type: .cgPoint),
            let size: CGSize = copyValue(kAXSizeAttribute, type: .cgSize)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /* Size → position → size: some apps clamp the position to keep the
       window on its current screen when it is still at its old size, and
       others re-clamp the size after a move — setting size on both ends of
       the position change sidesteps both behaviors. */
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    func isSameWindow(as other: AccessibilityWindow) -> Bool {
        CFEqual(element, other.element)
    }

    private func copyValue<T>(_ attribute: String, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }

    private func setPosition(_ point: CGPoint) {
        var mutable = point
        guard let axValue = AXValueCreate(.cgPoint, &mutable) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
    }

    private func setSize(_ size: CGSize) {
        var mutable = size
        guard let axValue = AXValueCreate(.cgSize, &mutable) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
    }
}
