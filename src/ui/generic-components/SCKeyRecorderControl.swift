import Cocoa
import Carbon.HIToolbox

class SCKeyRecorderControl: NSView {
    var keyCode: UInt32? {
        didSet { needsDisplay = true }
    }
    var onKeyChanged: ((UInt32) -> Void)?
    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor = isRecording ? .selectedControlColor : .controlBackgroundColor
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        path.fill()
        NSColor.gridColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let text: String
        if isRecording {
            text = NSLocalizedString("Press a key...", comment: "")
        } else if let keyCode {
            text = SCKeyCombo.keyCodeToString(keyCode)
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
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }
        let newKeyCode = UInt32(event.keyCode)
        keyCode = newKeyCode
        isRecording = false
        onKeyChanged?(newKeyCode)
    }
}
