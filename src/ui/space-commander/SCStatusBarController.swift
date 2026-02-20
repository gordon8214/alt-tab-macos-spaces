//
//  SCStatusBarController.swift
//  alt-tab-macos
//

import Cocoa

enum SCStatusBarActivationTarget: Equatable {
    case desktop(spaceIndex: Int)
    case fullscreen(spaceID: UInt64, screenUUID: String)
}

enum SCStatusBarSpacesMenuEntry: Equatable {
    case item(
        title: String,
        activationTarget: SCStatusBarActivationTarget?,
        isEnabled: Bool,
        isCurrent: Bool
    )
    case separator
}

struct SCStatusBarMenuModel: Equatable {
    let spacesEntries: [SCStatusBarSpacesMenuEntry]
}

struct SCStatusBarIconState: Equatable {
    let symbolName: String
    let accessibilityDescription: String
}

@MainActor
class SCStatusBarController {
    private let statusItem: NSStatusItem
    private var activeDesktopIndex: Int?
    private var spacesSnapshot: SpacesSnapshot?
    private static let boxedIndicatorSuffixMaxWidth: CGFloat = 156
    private static let largeIndicatorTextMaxWidth: CGFloat = 190
    var onPreferences: (() -> Void)?
    var onActivateDesktop: ((Int) -> Void)?
    var onActivateFullscreenDesktop: ((UInt64, String) -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()
        buildMenu()
    }

    func setActiveDesktopIndex(_ desktopIndex: Int?) {
        if let desktopIndex, (1...9).contains(desktopIndex) {
            activeDesktopIndex = desktopIndex
        } else {
            activeDesktopIndex = nil
        }
        updateStatusIcon()
    }

    func setSpacesSnapshot(_ snapshot: SpacesSnapshot?) {
        spacesSnapshot = snapshot
        buildMenu()
        updateStatusIcon()
    }

    func refreshAppearance() {
        updateStatusIcon()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let menuModel = Self.menuModel(spacesSnapshot: spacesSnapshot)

        for entry in menuModel.spacesEntries {
            switch entry {
            case .separator:
                menu.addItem(.separator())

            case .item(let title, let activationTarget, let isEnabled, let isCurrent):
                let item = NSMenuItem(
                    title: title,
                    action: (isEnabled && activationTarget != nil) ? #selector(activateSpaceClicked(_:)) : nil,
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = isEnabled
                item.state = isCurrent ? .on : .off
                item.representedObject = activationTarget
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: NSLocalizedString("Preferences...", comment: ""), action: #selector(preferencesClicked), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        statusItem.length = NSStatusItem.squareLength

        let iconState = Self.iconState(
            activeDesktopIndex: activeDesktopIndex,
            hasCurrentFullscreenSpace: spacesSnapshot?.currentFullscreenSpace != nil
        )

        if applyDesktopIndicatorIfNeeded(button: button, iconState: iconState) {
            return
        }

        applyImage(iconState, to: button)
    }

    private func applyDesktopIndicatorIfNeeded(
        button: NSStatusBarButton,
        iconState: SCStatusBarIconState
    ) -> Bool {
        guard spacesSnapshot?.currentFullscreenSpace == nil,
              let activeDesktopIndex else {
            return false
        }

        let indicatorStyle = SCPreferences.loadMenuBarDesktopIndicatorStyle()
        let customTitle = Self.customDesktopTitle(
            snapshot: spacesSnapshot,
            activeDesktopIndex: activeDesktopIndex,
            showCustomDesktopTitle: SCPreferences.loadShowCustomDesktopTitleInMenuBar()
        )

        switch indicatorStyle {
        case .boxedNumber:
            applyBoxedDesktopIndicator(
                button: button,
                iconState: iconState,
                activeDesktopIndex: activeDesktopIndex,
                customTitle: customTitle
            )
        case .largeNumber:
            applyLargeDesktopIndicator(
                button: button,
                iconState: iconState,
                activeDesktopIndex: activeDesktopIndex,
                customTitle: customTitle
            )
        }
        return true
    }

    private func applyBoxedDesktopIndicator(
        button: NSStatusBarButton,
        iconState: SCStatusBarIconState,
        activeDesktopIndex: Int,
        customTitle: String?
    ) {
        applyImage(iconState, to: button)
        let suffixText = Self.desktopIndicatorText(
            style: .boxedNumber,
            activeDesktopIndex: activeDesktopIndex,
            customTitle: customTitle
        )
        guard !suffixText.isEmpty else {
            return
        }

        let font = NSFont.menuBarFont(ofSize: 0)
        let truncatedSuffix = Self.truncatedText(
            suffixText,
            maxWidth: Self.boxedIndicatorSuffixMaxWidth,
            font: font
        )
        guard !truncatedSuffix.isEmpty else {
            return
        }

        button.title = truncatedSuffix
        button.imagePosition = .imageLeading
        statusItem.length = NSStatusItem.variableLength
    }

    private func applyLargeDesktopIndicator(
        button: NSStatusBarButton,
        iconState: SCStatusBarIconState,
        activeDesktopIndex: Int,
        customTitle: String?
    ) {
        let baseText = Self.desktopIndicatorText(
            style: .largeNumber,
            activeDesktopIndex: activeDesktopIndex,
            customTitle: customTitle
        )
        guard !baseText.isEmpty else {
            applyImage(iconState, to: button)
            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let truncatedText = Self.truncatedText(
            baseText,
            maxWidth: Self.largeIndicatorTextMaxWidth,
            font: font
        )
        guard !truncatedText.isEmpty else {
            applyImage(iconState, to: button)
            return
        }

        button.attributedTitle = NSAttributedString(
            string: truncatedText,
            attributes: [.font: font]
        )
        button.imagePosition = .noImage
        statusItem.length = NSStatusItem.variableLength
    }

    private func applyImage(_ iconState: SCStatusBarIconState, to button: NSStatusBarButton) {
        if #available(macOS 11.0, *) {
            if let image = NSImage(
                systemSymbolName: iconState.symbolName,
                accessibilityDescription: iconState.accessibilityDescription
            ) {
                button.image = image
                return
            }
            if iconState.symbolName == "rectangle.inset.filled.and.person.filled" {
                button.image = NSImage(
                    systemSymbolName: "rectangle.inset.filled",
                    accessibilityDescription: iconState.accessibilityDescription
                )
                return
            }
        }
        button.title = iconState.accessibilityDescription
        button.imagePosition = .noImage
        statusItem.length = NSStatusItem.variableLength
    }

    private nonisolated static func truncatedText(
        _ text: String,
        maxWidth: CGFloat,
        font: NSFont
    ) -> String {
        truncatedText(text, maxWidth: maxWidth) { candidate in
            measuredWidth(of: candidate, font: font)
        }
    }

    private nonisolated static func measuredWidth(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    @objc private func preferencesClicked() {
        onPreferences?()
    }

    @objc private func activateSpaceClicked(_ sender: NSMenuItem) {
        Self.dispatchSpaceActivation(
            representedObject: sender.representedObject,
            onActivateDesktop: onActivateDesktop,
            onActivateFullscreenDesktop: onActivateFullscreenDesktop
        )
    }
}

// MARK: - Modeling

extension SCStatusBarController {
    nonisolated static func spaceMenuTitle(for spaceIndex: Int, name: String) -> String {
        "\(spaceIndex): \(name)"
    }

    nonisolated static func fullscreenMenuTitle(name: String) -> String {
        String(format: NSLocalizedString("Fullscreen: %@", comment: ""), name)
    }

    nonisolated static func spacesMenuEntries(snapshot: SpacesSnapshot?) -> [SCStatusBarSpacesMenuEntry] {
        guard let snapshot else {
            return [
                .item(
                    title: NSLocalizedString("No spaces available", comment: ""),
                    activationTarget: nil,
                    isEnabled: false,
                    isCurrent: false
                )
            ]
        }

        var entries: [SCStatusBarSpacesMenuEntry] = []

        if !snapshot.fullscreenSpaces.isEmpty {
            entries.append(contentsOf: snapshot.fullscreenSpaces.map { fullscreenSpace in
                .item(
                    title: fullscreenMenuTitle(name: fullscreenSpace.title),
                    activationTarget: .fullscreen(
                        spaceID: fullscreenSpace.spaceId,
                        screenUUID: fullscreenSpace.screenUUID
                    ),
                    isEnabled: true,
                    isCurrent: fullscreenSpace.isCurrent
                )
            })
        }

        if !snapshot.fullscreenSpaces.isEmpty, !snapshot.spaces.isEmpty {
            entries.append(.separator)
        }

        entries.append(contentsOf: snapshot.spaces.map { space in
            .item(
                title: spaceMenuTitle(for: space.spaceIndex, name: space.title),
                activationTarget: .desktop(spaceIndex: space.spaceIndex),
                isEnabled: true,
                isCurrent: space.isCurrent
            )
        })

        if entries.isEmpty {
            return [
                .item(
                    title: NSLocalizedString("No spaces available", comment: ""),
                    activationTarget: nil,
                    isEnabled: false,
                    isCurrent: false
                )
            ]
        }

        return entries
    }

    nonisolated static func menuModel(
        spacesSnapshot: SpacesSnapshot?
    ) -> SCStatusBarMenuModel {
        SCStatusBarMenuModel(
            spacesEntries: spacesMenuEntries(snapshot: spacesSnapshot)
        )
    }

    nonisolated static func iconState(
        activeDesktopIndex: Int?,
        hasCurrentFullscreenSpace: Bool
    ) -> SCStatusBarIconState {
        if hasCurrentFullscreenSpace {
            return SCStatusBarIconState(
                symbolName: "rectangle.inset.filled.and.person.filled",
                accessibilityDescription: NSLocalizedString("Current Fullscreen Space", comment: "")
            )
        }
        if let activeDesktopIndex {
            return SCStatusBarIconState(
                symbolName: "\(activeDesktopIndex).square.fill",
                accessibilityDescription: String(format: NSLocalizedString("Current Desktop %d", comment: ""), activeDesktopIndex)
            )
        }
        return SCStatusBarIconState(
            symbolName: "rectangle.3.group",
            accessibilityDescription: NSLocalizedString("Spaces Mode", comment: "")
        )
    }

    nonisolated static func customDesktopTitle(
        snapshot: SpacesSnapshot?,
        activeDesktopIndex: Int?,
        showCustomDesktopTitle: Bool
    ) -> String? {
        guard showCustomDesktopTitle,
              let activeDesktopIndex,
              let currentSpace = snapshot?.spaces.first(where: { $0.spaceIndex == activeDesktopIndex }) else {
            return nil
        }

        let trimmedTitle = currentSpace.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return nil
        }
        guard trimmedTitle != defaultDesktopTitle(spaceIndex: activeDesktopIndex) else {
            return nil
        }
        return trimmedTitle
    }

    nonisolated static func desktopIndicatorText(
        style: MenuBarDesktopIndicatorStyle,
        activeDesktopIndex: Int?,
        customTitle: String?
    ) -> String {
        switch style {
        case .boxedNumber:
            guard let customTitle else {
                return ""
            }
            return " \u{00B7} \(customTitle)"

        case .largeNumber:
            guard let activeDesktopIndex else {
                return ""
            }
            guard let customTitle else {
                return "\(activeDesktopIndex)"
            }
            return "\(activeDesktopIndex) \u{00B7} \(customTitle)"
        }
    }

    nonisolated static func truncatedText(
        _ text: String,
        maxWidth: CGFloat,
        measuredWidth: (String) -> CGFloat
    ) -> String {
        guard !text.isEmpty else {
            return ""
        }
        guard measuredWidth(text) > maxWidth else {
            return text
        }

        let ellipsis = "\u{2026}"
        guard measuredWidth(ellipsis) <= maxWidth else {
            return ""
        }

        let characters = Array(text)
        var lowerBound = 0
        var upperBound = characters.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound + 1) / 2
            let candidate = String(characters.prefix(middle)) + ellipsis
            if measuredWidth(candidate) <= maxWidth {
                lowerBound = middle
            } else {
                upperBound = middle - 1
            }
        }

        guard lowerBound > 0 else {
            return ellipsis
        }
        return String(characters.prefix(lowerBound)) + ellipsis
    }

    nonisolated static func dispatchSpaceActivation(
        representedObject: Any?,
        onActivateDesktop: ((Int) -> Void)?,
        onActivateFullscreenDesktop: ((UInt64, String) -> Void)?
    ) {
        guard let target = representedObject as? SCStatusBarActivationTarget else {
            return
        }

        switch target {
        case .desktop(let spaceIndex):
            onActivateDesktop?(spaceIndex)
        case .fullscreen(let spaceID, let screenUUID):
            onActivateFullscreenDesktop?(spaceID, screenUUID)
        }
    }

    nonisolated static func dispatchDesktopActivation(
        representedObject: Any?,
        onActivateDesktop: ((Int) -> Void)?
    ) {
        if let spaceIndex = representedObject as? Int {
            onActivateDesktop?(spaceIndex)
            return
        }
        dispatchSpaceActivation(
            representedObject: representedObject,
            onActivateDesktop: onActivateDesktop,
            onActivateFullscreenDesktop: nil
        )
    }

    private nonisolated static func defaultDesktopTitle(spaceIndex: Int) -> String {
        String(format: NSLocalizedString("Desktop %d", comment: ""), spaceIndex)
    }
}
