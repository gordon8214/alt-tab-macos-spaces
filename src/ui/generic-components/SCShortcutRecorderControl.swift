import Cocoa
import ShortcutRecorder

class SCShortcutRecorderControl: RecorderControl {
    var onShortcutChanged: ((SCKeyCombo?) -> Void)?

    convenience init(keyCombo: SCKeyCombo?) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsModifierFlagsOnlyShortcut = false
        set(allowedModifierFlags: [.command, .control, .option, .shift], requiredModifierFlags: [], allowsEmptyModifierFlags: false)
        if let keyCombo {
            objectValue = Shortcut(keyEquivalent: keyCombo.shortcutKeyEquivalent)
        }
        addOrUpdateConstraint(widthAnchor, 100)
    }
}

extension SCShortcutRecorderControl: RecorderControlDelegate {
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        guard let combo = SCKeyCombo(
            shortcutKeyCode: UInt16(shortcut.carbonKeyCode),
            modifierFlags: shortcut.modifierFlags
        ) else {
            return false
        }
        onShortcutChanged?(combo)
        return true
    }

    func recorderControlDidEndRecording(_ control: RecorderControl) {
        if control.objectValue == nil {
            onShortcutChanged?(nil)
        }
    }
}
