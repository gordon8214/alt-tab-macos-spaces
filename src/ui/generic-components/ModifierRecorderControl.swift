import Cocoa
import Carbon.HIToolbox

class ModifierRecorderControl: NSView {
    var modifiers: SCCarbonModifiers? {
        didSet { needsDisplay = true }
    }
    var onModifiersChanged: ((SCCarbonModifiers) -> Void)?
    var isEnabled: Bool = true {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.5
            if !isEnabled, isRecording {
                pendingModifiers = nil
                isRecording = false
            }
        }
    }
    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var pendingModifiers: SCCarbonModifiers?

    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 28) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { NSLocalizedString("Modifier key recorder", comment: "") }
    override func accessibilityValue() -> Any? {
        if isRecording {
            return NSLocalizedString("Recording. Press modifier keys.", comment: "")
        } else if let modifiers {
            return modifiers.displayString
        }
        return NSLocalizedString("No modifiers set. Click to record.", comment: "")
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor = isRecording ? .selectedControlColor : .controlBackgroundColor
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        path.fill()
        NSColor.gridColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let text: String
        if isRecording, let pending = pendingModifiers {
            text = pending.displayString
        } else if isRecording {
            text = NSLocalizedString("Press modifiers...", comment: "")
        } else if let modifiers {
            text = modifiers.displayString
        } else {
            text = NSLocalizedString("Click to record", comment: "")
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.white : NSColor.labelColor
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let strSize = attrStr.size()
        let point = NSPoint(
            x: (bounds.width - strSize.width) / 2,
            y: (bounds.height - strSize.height) / 2
        )
        attrStr.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            pendingModifiers = nil
            isRecording = false
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        let current = SCCarbonModifiers(cocoaFlags: event.modifierFlags)
        if current.isEmpty {
            if let pending = pendingModifiers {
                modifiers = pending
                pendingModifiers = nil
                isRecording = false
                onModifiersChanged?(pending)
            }
        } else {
            pendingModifiers = current
            needsDisplay = true
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        pendingModifiers = nil
        isRecording = false
    }
}
