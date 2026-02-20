import AppKit
import Carbon.HIToolbox

enum DesktopPreviewSize: Int, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small:
            return NSLocalizedString("Small", comment: "")
        case .medium:
            return NSLocalizedString("Medium", comment: "")
        case .large:
            return NSLocalizedString("Large", comment: "")
        }
    }

    var cardSize: CGSize {
        switch self {
        case .small:
            return CGSize(width: 220, height: 170)
        case .medium:
            return CGSize(width: 280, height: 206)
        case .large:
            return CGSize(width: 340, height: 246)
        }
    }

    var previewHeight: CGFloat {
        switch self {
        case .small:
            return 108
        case .medium:
            return 132
        case .large:
            return 158
        }
    }

    static var `default`: DesktopPreviewSize {
        .medium
    }
}

enum MenuBarDesktopIndicatorStyle: Int, CaseIterable, Codable, Sendable {
    case boxedNumber
    case largeNumber

    var displayName: String {
        switch self {
        case .boxedNumber:
            return NSLocalizedString("Number in Box", comment: "")
        case .largeNumber:
            return NSLocalizedString("Large Number", comment: "")
        }
    }

    static var `default`: MenuBarDesktopIndicatorStyle {
        .boxedNumber
    }
}

enum SpatialDirection: Equatable, Sendable {
    case left
    case right
    case upward
    case down
}

struct SCCarbonModifiers: OptionSet, Codable, Sendable {
    let rawValue: UInt32

    static let command = SCCarbonModifiers(rawValue: UInt32(cmdKey))
    static let option  = SCCarbonModifiers(rawValue: UInt32(optionKey))
    static let control = SCCarbonModifiers(rawValue: UInt32(controlKey))
    static let shift   = SCCarbonModifiers(rawValue: UInt32(shiftKey))

    init(rawValue: UInt32) { self.rawValue = rawValue }

    init(cocoaFlags: NSEvent.ModifierFlags) {
        var result: SCCarbonModifiers = []
        if cocoaFlags.contains(.command) { result.insert(.command) }
        if cocoaFlags.contains(.option) { result.insert(.option) }
        if cocoaFlags.contains(.control) { result.insert(.control) }
        if cocoaFlags.contains(.shift) { result.insert(.shift) }
        self = result
    }

    var cocoaFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Ctrl") }
        if contains(.option) { parts.append("Opt") }
        if contains(.shift) { parts.append("Shift") }
        if contains(.command) { parts.append("Cmd") }
        return parts.joined(separator: "+")
    }
}

struct SCKeyCombo: Codable, Sendable, Equatable {
    var keyCode: UInt32
    var modifiers: SCCarbonModifiers

    var displayString: String {
        let modStr = modifiers.displayString
        let keyStr = SCKeyCombo.keyCodeToString(keyCode)
        return modStr.isEmpty ? keyStr : "\(modStr)+\(keyStr)"
    }

    static let defaultDesktopSwitcher = SCKeyCombo(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: [.control, .option, .command]
    )

    static let defaultFirstEmptySpace = SCKeyCombo(
        keyCode: UInt32(kVK_ANSI_E),
        modifiers: [.control, .option, .command]
    )

    private static let keyCodeMap: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Return): "Return", UInt32(kVK_Space): "Space",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
        UInt32(kVK_LeftArrow): "Left", UInt32(kVK_RightArrow): "Right",
        UInt32(kVK_UpArrow): "Up", UInt32(kVK_DownArrow): "Down",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Grave): "`"
    ]

    static func keyCodeToString(_ keyCode: UInt32) -> String {
        keyCodeMap[keyCode] ?? "Key\(keyCode)"
    }

    /// Key equivalent string for ShortcutRecorder (e.g. "⌃⌥⌘d")
    var shortcutKeyEquivalent: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += SCKeyCombo.keyCodeToString(keyCode).lowercased()
        return result
    }
}

extension SCKeyCombo {
    init?(shortcutKeyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let carbonMods = SCCarbonModifiers(cocoaFlags: modifierFlags)
        guard !carbonMods.isEmpty else { return nil }
        self.keyCode = UInt32(shortcutKeyCode)
        self.modifiers = carbonMods
    }
}

enum SCPreferences {
    private static let enabledKey = "scEnabled"
    private static let desktopColumnsKey = "desktopSwitcherColumns"
    private static let desktopPreviewSizeKey = "desktopSwitcherPreviewSize"
    private static let desktopWindowFrameKey = "desktopSwitcherWindowFrame"
    private static let spaceCustomNamesKey = "spaceCustomNames"
    private static let spaceCustomOrderKey = "spaceCustomOrder"
    private static let fullscreenSpaceCustomOrderKey = "fullscreenSpaceCustomOrder"
    private static let menuBarDesktopIndicatorStyleKey = "menuBarDesktopIndicatorStyle"
    private static let showCustomDesktopTitleInMenuBarKey = "showCustomDesktopTitleInMenuBar"
    private static let spatialModifiersKey = "scSpatialModifiers"
    private static let desktopSwitcherKeyCodeKey = "scDesktopSwitcherKeyCode"
    private static let desktopSwitcherModifiersKey = "scDesktopSwitcherModifiers"
    private static let firstEmptySpaceKeyCodeKey = "scFirstEmptySpaceKeyCode"
    private static let firstEmptySpaceModifiersKey = "scFirstEmptySpaceModifiers"

    static func loadEnabled() -> Bool {
        // Default to true if key has never been set
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    static let defaultDesktopColumns = 3
    static let minimumDesktopColumns = 1
    static let maximumDesktopColumns = 6

    static func loadDesktopColumns() -> Int {
        let stored = UserDefaults.standard.integer(forKey: desktopColumnsKey)
        let resolved = stored == 0 ? defaultDesktopColumns : stored
        return min(max(resolved, minimumDesktopColumns), maximumDesktopColumns)
    }

    static func saveDesktopColumns(_ columns: Int) {
        let clamped = min(max(columns, minimumDesktopColumns), maximumDesktopColumns)
        UserDefaults.standard.set(clamped, forKey: desktopColumnsKey)
    }

    static func loadDesktopPreviewSize() -> DesktopPreviewSize {
        let stored = UserDefaults.standard.integer(forKey: desktopPreviewSizeKey)
        return DesktopPreviewSize(rawValue: stored) ?? .default
    }

    static func saveDesktopPreviewSize(_ size: DesktopPreviewSize) {
        UserDefaults.standard.set(size.rawValue, forKey: desktopPreviewSizeKey)
    }

    static func loadMenuBarDesktopIndicatorStyle() -> MenuBarDesktopIndicatorStyle {
        let storedRawValue = UserDefaults.standard.integer(forKey: menuBarDesktopIndicatorStyleKey)
        return MenuBarDesktopIndicatorStyle(rawValue: storedRawValue) ?? .default
    }

    static func saveMenuBarDesktopIndicatorStyle(_ style: MenuBarDesktopIndicatorStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: menuBarDesktopIndicatorStyleKey)
    }

    static func loadShowCustomDesktopTitleInMenuBar() -> Bool {
        UserDefaults.standard.bool(forKey: showCustomDesktopTitleInMenuBarKey)
    }

    static func saveShowCustomDesktopTitleInMenuBar(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: showCustomDesktopTitleInMenuBarKey)
    }

    static func loadSpatialModifiers() -> SCCarbonModifiers {
        let stored = UserDefaults.standard.integer(forKey: spatialModifiersKey)
        if stored == 0 {
            return [.control, .option]
        }
        return SCCarbonModifiers(rawValue: UInt32(stored))
    }

    static func saveSpatialModifiers(_ modifiers: SCCarbonModifiers) {
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: spatialModifiersKey)
    }

    static func loadDesktopSwitcherShortcut() -> SCKeyCombo {
        let keyCode = UserDefaults.standard.object(forKey: desktopSwitcherKeyCodeKey) as? Int
        let modifiers = UserDefaults.standard.object(forKey: desktopSwitcherModifiersKey) as? Int
        guard let keyCode, let modifiers else { return .defaultDesktopSwitcher }
        return SCKeyCombo(keyCode: UInt32(keyCode), modifiers: SCCarbonModifiers(rawValue: UInt32(modifiers)))
    }

    static func saveDesktopSwitcherShortcut(_ combo: SCKeyCombo?) {
        if let combo {
            UserDefaults.standard.set(Int(combo.keyCode), forKey: desktopSwitcherKeyCodeKey)
            UserDefaults.standard.set(Int(combo.modifiers.rawValue), forKey: desktopSwitcherModifiersKey)
        } else {
            UserDefaults.standard.removeObject(forKey: desktopSwitcherKeyCodeKey)
            UserDefaults.standard.removeObject(forKey: desktopSwitcherModifiersKey)
        }
    }

    static func loadFirstEmptySpaceShortcut() -> SCKeyCombo {
        let keyCode = UserDefaults.standard.object(forKey: firstEmptySpaceKeyCodeKey) as? Int
        let modifiers = UserDefaults.standard.object(forKey: firstEmptySpaceModifiersKey) as? Int
        guard let keyCode, let modifiers else { return .defaultFirstEmptySpace }
        return SCKeyCombo(keyCode: UInt32(keyCode), modifiers: SCCarbonModifiers(rawValue: UInt32(modifiers)))
    }

    static func saveFirstEmptySpaceShortcut(_ combo: SCKeyCombo?) {
        if let combo {
            UserDefaults.standard.set(Int(combo.keyCode), forKey: firstEmptySpaceKeyCodeKey)
            UserDefaults.standard.set(Int(combo.modifiers.rawValue), forKey: firstEmptySpaceModifiersKey)
        } else {
            UserDefaults.standard.removeObject(forKey: firstEmptySpaceKeyCodeKey)
            UserDefaults.standard.removeObject(forKey: firstEmptySpaceModifiersKey)
        }
    }

    static func loadDesktopSwitcherFrame() -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: desktopWindowFrameKey),
              !frameString.isEmpty else {
            return nil
        }
        let frame = NSRectFromString(frameString)
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }
        return frame
    }

    static func saveDesktopSwitcherFrame(_ frame: NSRect) {
        guard frame.width > 0, frame.height > 0 else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: desktopWindowFrameKey)
    }

    static func loadSpaceCustomNames() -> [Int: String] {
        guard let stored = UserDefaults.standard.dictionary(forKey: spaceCustomNamesKey) as? [String: String] else {
            return [:]
        }
        var decoded: [Int: String] = [:]
        for (spaceIndexString, name) in stored {
            guard let spaceIndex = Int(spaceIndexString), spaceIndex > 0 else {
                continue
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            decoded[spaceIndex] = trimmed
        }
        return decoded
    }

    static func saveSpaceCustomNames(_ names: [Int: String]) {
        let encoded = Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(encoded, forKey: spaceCustomNamesKey)
    }

    static func loadSpaceCustomOrder() -> [Int] {
        guard let stored = UserDefaults.standard.array(forKey: spaceCustomOrderKey) as? [Int] else {
            return []
        }
        var seen = Set<Int>()
        return stored.filter { value in
            guard value > 0 else { return false }
            return seen.insert(value).inserted
        }
    }

    static func saveSpaceCustomOrder(_ order: [Int]) {
        var seen = Set<Int>()
        let encoded = order.filter { value in
            guard value > 0 else { return false }
            return seen.insert(value).inserted
        }
        UserDefaults.standard.set(encoded, forKey: spaceCustomOrderKey)
    }

    static func loadFullscreenSpaceCustomOrder() -> [UInt64] {
        guard let stored = UserDefaults.standard.array(forKey: fullscreenSpaceCustomOrderKey) else {
            return []
        }
        var decoded: [UInt64] = []
        var seen = Set<UInt64>()
        for raw in stored {
            let value: UInt64?
            if let number = raw as? NSNumber {
                value = number.uint64Value
            } else if let string = raw as? String {
                value = UInt64(string)
            } else {
                value = nil
            }
            guard let value, value > 0, seen.insert(value).inserted else {
                continue
            }
            decoded.append(value)
        }
        return decoded
    }

    static func saveFullscreenSpaceCustomOrder(_ order: [UInt64]) {
        var seen = Set<UInt64>()
        let encoded = order.filter { value in
            guard value > 0 else { return false }
            return seen.insert(value).inserted
        }
        UserDefaults.standard.set(encoded, forKey: fullscreenSpaceCustomOrderKey)
    }
}
