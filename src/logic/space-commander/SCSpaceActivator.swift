import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum SCSpaceActivator {
    static func activateSpace(index: Int) -> Bool {
        guard let keyCode = keyCode(forSpaceIndex: index),
              let source = CGEventSource(stateID: .hidSystemState) ?? CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = [.maskControl]
        keyUp.flags = [.maskControl]

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    static func activateSpace(spaceID: UInt64, screenUUID: String) -> Bool {
        guard spaceID > 0, !screenUUID.isEmpty else {
            Logger.warning { "Fullscreen space activation rejected: invalidInput spaceID=\(spaceID) screenUUID=\(screenUUID)" }
            return false
        }

        guard let display = managedDisplay(matching: screenUUID) else {
            Logger.warning { "Fullscreen space activation rejected: missingDisplay spaceID=\(spaceID) screenUUID=\(screenUUID)" }
            return false
        }
        guard display.spaceIDs.contains(spaceID) else {
            Logger.warning { "Fullscreen space activation rejected: missingSpace spaceID=\(spaceID) display=\(display.identifier)" }
            return false
        }

        let status = CGSManagedDisplaySetCurrentSpace(CGS_CONNECTION, display.identifier as CFString, spaceID)
        if status != .success {
            Logger.warning { "Fullscreen space activation failed: cgsStatus=\(status) spaceID=\(spaceID) display=\(display.identifier)" }
            return false
        }
        return true
    }

    static func keyCode(forSpaceIndex index: Int) -> CGKeyCode? {
        guard (1...9).contains(index) else {
            return nil
        }

        let keyCodes: [CGKeyCode] = [
            CGKeyCode(kVK_ANSI_1),
            CGKeyCode(kVK_ANSI_2),
            CGKeyCode(kVK_ANSI_3),
            CGKeyCode(kVK_ANSI_4),
            CGKeyCode(kVK_ANSI_5),
            CGKeyCode(kVK_ANSI_6),
            CGKeyCode(kVK_ANSI_7),
            CGKeyCode(kVK_ANSI_8),
            CGKeyCode(kVK_ANSI_9)
        ]
        return keyCodes[index - 1]
    }

    private struct ManagedDisplay {
        let identifier: String
        let spaceIDs: Set<UInt64>
    }

    private static func managedDisplay(matching screenUUID: String) -> ManagedDisplay? {
        let normalizedTarget = screenUUID.uppercased()
        let displays = managedDisplays()
        if let exact = displays.first(where: { $0.identifier.uppercased() == normalizedTarget }) {
            return exact
        }
        return displays.first(where: { $0.identifier.caseInsensitiveCompare(screenUUID) == .orderedSame })
    }

    private static func managedDisplays() -> [ManagedDisplay] {
        guard let raw = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [NSDictionary] else {
            return []
        }
        var displays: [ManagedDisplay] = []

        for entry in raw {
            guard let displayIdentifier = displayIdentifier(from: entry) else {
                continue
            }

            let spacesArray = entry["Spaces"] as? [NSDictionary] ?? []
            let spaceIDs = Set(spacesArray.compactMap { spaceID(from: $0) })
            displays.append(ManagedDisplay(identifier: displayIdentifier, spaceIDs: spaceIDs))
        }

        return displays
    }

    private static func displayIdentifier(from dictionary: NSDictionary) -> String? {
        if let id = dictionary["Display Identifier"] as? String, !id.isEmpty {
            return id
        }
        if let id = dictionary["DisplayUUID"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    private static func spaceID(from dictionary: NSDictionary) -> UInt64? {
        if let value = dictionary["id64"] as? NSNumber {
            let id = value.uint64Value
            return id > 0 ? id : nil
        }
        if let value = dictionary["ManagedSpaceID"] as? NSNumber {
            let id = value.uint64Value
            return id > 0 ? id : nil
        }
        return nil
    }
}
