import Cocoa
import Carbon.HIToolbox

enum SCSpatialDesktopOverlayPlan: Equatable {
    case unavailable
    case grid(
        entries: [SCDesktopSwitcherController.DesktopEntry],
        frames: [CGRect],
        sourceIndex: Int,
        targetIndex: Int?
    )
}

enum SCSpatialDesktopAttemptAction: Equatable {
    case beep
    case activateRegular(spaceIndex: Int)
    case activateFullscreen(spaceID: UInt64, screenUUID: String)
}

struct SCSpatialDesktopAttemptPlan: Equatable {
    let overlay: SCSpatialDesktopOverlayPlan
    let action: SCSpatialDesktopAttemptAction
}

@MainActor
class SCCoordinator {
    static var shared: SCCoordinator?
    static let spacesPollInterval: TimeInterval = 3.0
    static let activationVerificationAttempts = 4
    static let activationVerificationDelay: TimeInterval = 0.18

    var desktopSwitcherController: SCDesktopSwitcherController?
    var spatialOverlayController: SCSpatialDesktopOverlayController?
    var statusBarController: SCStatusBarController?

    var latestSpacesSnapshot: SpacesSnapshot?
    var spacesCustomNames: [Int: String] = [:]
    var spacesCustomOrder: [Int] = []
    var spacesFullscreenCustomOrder: [UInt64] = []

    var spacesPollTimer: Timer?
    var pendingActivationID: UUID?
    var hasShownConfigurationWarning = false

    var hotKeyManager: SCHotKeyManager?
    var imageCaptureManager: SCDesktopImageCaptureManager?

    func start() {
        spacesCustomNames = SCPreferences.loadSpaceCustomNames()
        spacesCustomOrder = SCPreferences.loadSpaceCustomOrder()
        spacesFullscreenCustomOrder = SCPreferences.loadFullscreenSpaceCustomOrder()
        desktopSwitcherController = SCDesktopSwitcherController()
        spatialOverlayController = SCSpatialDesktopOverlayController()
        statusBarController = SCStatusBarController()
        wireDesktopSwitcherCallbacks()
        statusBarController?.onActivateDesktop = { [weak self] spaceIndex in
            self?.activateDesktop(spaceIndex)
        }
        statusBarController?.onActivateFullscreenDesktop = { [weak self] spaceID, screenUUID in
            self?.activateFullscreenDesktop(spaceID: spaceID, screenUUID: screenUUID)
        }
        statusBarController?.onPreferences = {
            App.app.showSettingsWindow()
        }
        imageCaptureManager = SCDesktopImageCaptureManager()
        hotKeyManager = SCHotKeyManager()
        hotKeyManager?.onDesktopSwitcherToggle = { [weak self] in
            self?.toggleDesktopSwitcher()
        }
        hotKeyManager?.onFirstEmptySpace = { [weak self] in
            self?.jumpToFirstEmptySpace()
        }
        hotKeyManager?.onSpatialNavigation = { [weak self] direction in
            self?.handleSpatialNavigation(direction)
        }
        hotKeyManager?.registerAll()
        startPolling()
    }

    func stop() {
        hotKeyManager?.unregisterAll()
        hotKeyManager = nil
        stopPolling()
        imageCaptureManager?.invalidateAll()
        imageCaptureManager = nil
        desktopSwitcherController?.dismiss()
        desktopSwitcherController = nil
        spatialOverlayController?.cleanup()
        spatialOverlayController = nil
        statusBarController = nil
        latestSpacesSnapshot = nil
    }

    func startPolling() {
        spacesPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.spacesPollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshSpacesSnapshot()
            }
        }
        timer.tolerance = Self.spacesPollInterval * 0.2
        spacesPollTimer = timer
        refreshSpacesSnapshot()
    }

    func stopPolling() {
        spacesPollTimer?.invalidate()
        spacesPollTimer = nil
        pendingActivationID = nil
    }

    func handleSpaceChange() {
        refreshSpacesSnapshot()
    }

    func refreshSpacesSnapshot() {
        let snapshot = SCSpacesSnapshotBuilder.build(
            customNames: spacesCustomNames,
            preferredOrder: spacesCustomOrder,
            fullscreenPreferredOrder: spacesFullscreenCustomOrder
        )
        let normalizedOrder = snapshot.spaces.map(\.spaceIndex)
        if normalizedOrder != spacesCustomOrder {
            spacesCustomOrder = normalizedOrder
            SCPreferences.saveSpaceCustomOrder(normalizedOrder)
        }
        let normalizedFullscreenOrder = snapshot.fullscreenSpaces.map(\.spaceId)
        if normalizedFullscreenOrder != spacesFullscreenCustomOrder {
            spacesFullscreenCustomOrder = normalizedFullscreenOrder
            SCPreferences.saveFullscreenSpaceCustomOrder(normalizedFullscreenOrder)
        }
        latestSpacesSnapshot = snapshot
        if SCPreferences.loadDesktopPreviewStyle() == .images {
            let isPanelVisible = desktopSwitcherController?.panel?.isVisible == true
            let allSpaceIDs = Set(snapshot.spaces.map(\.spaceId) + snapshot.fullscreenSpaces.map(\.spaceId))
            imageCaptureManager?.pruneStaleEntries(currentSpaceIDs: allSpaceIDs)
            if !isPanelVisible {
                imageCaptureManager?.captureVisibleSpaces()
            }
        }
        statusBarController?.setSpacesSnapshot(snapshot)
        statusBarController?.setActiveDesktopIndex(snapshot.currentSpaceIndex)
        desktopSwitcherController?.refreshIfVisibleCoalesced()
        maybeWarnAboutConfiguration(snapshot)
    }

    func toggleDesktopSwitcher() {
        guard let desktopSwitcherController else { return }
        if desktopSwitcherController.panel?.isVisible == true {
            desktopSwitcherController.dismiss()
        } else {
            refreshSpacesSnapshot()
            desktopSwitcherController.show()
        }
    }

    func jumpToFirstEmptySpace() {
        guard let snapshot = latestSpacesSnapshot else {
            NSSound.beep()
            return
        }
        desktopSwitcherController?.dismiss()
        guard let firstEmpty = snapshot.spaces.first(where: { $0.bundleIDs.isEmpty && !$0.isCurrent }) else {
            NSSound.beep()
            return
        }
        activateDesktop(firstEmpty.spaceIndex)
    }

    func handleSpatialNavigation(_ direction: SpatialDirection) {
        desktopSwitcherController?.dismiss()
        let plan = Self.spatialDesktopAttemptPlan(
            snapshot: latestSpacesSnapshot,
            direction: direction,
            configuredRegularColumns: SCPreferences.loadDesktopColumns(),
            previewSize: SCPreferences.loadDesktopPreviewSize()
        )
        switch plan.overlay {
        case .unavailable:
            spatialOverlayController?.showUnavailableAttempt()
        case .grid(let entries, let frames, let sourceIndex, let targetIndex):
            spatialOverlayController?.show(
                entries: entries,
                frames: frames,
                sourceIndex: sourceIndex,
                targetIndex: targetIndex
            )
        }
        switch plan.action {
        case .beep:
            NSSound.beep()
        case .activateRegular(let spaceIndex):
            activateDesktop(spaceIndex)
        case .activateFullscreen(let spaceID, let screenUUID):
            activateFullscreenDesktop(spaceID: spaceID, screenUUID: screenUUID)
        }
    }

    func activateDesktop(_ spaceIndex: Int) {
        let requestID = UUID()
        pendingActivationID = requestID
        activateRegularDesktopWithVerification(spaceIndex: spaceIndex, requestID: requestID)
    }

    func activateFullscreenDesktop(spaceID: UInt64, screenUUID: String) {
        if activateFullscreenDesktopViaWindowFocus(spaceID: spaceID) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationVerificationDelay) { [weak self] in
                guard let self else { return }
                Spaces.refresh()
                if Spaces.currentSpaceId != spaceID {
                    let _ = SCSpaceActivator.activateSpace(spaceID: spaceID, screenUUID: screenUUID)
                }
                self.refreshSpacesSnapshot()
            }
            return
        }
        let success = SCSpaceActivator.activateSpace(spaceID: spaceID, screenUUID: screenUUID)
        if success {
            Logger.info { "Fullscreen desktop activation via CGS spaceID=\(spaceID) screenUUID=\(screenUUID)" }
        } else {
            NSSound.beep()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationVerificationDelay) { [weak self] in
            self?.refreshSpacesSnapshot()
        }
    }

    func setCustomSpaceName(_ customName: String?, for spaceIndex: Int) {
        guard spaceIndex > 0 else { return }
        let trimmedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty {
            spacesCustomNames.removeValue(forKey: spaceIndex)
        } else {
            spacesCustomNames[spaceIndex] = trimmedName
        }
        SCPreferences.saveSpaceCustomNames(spacesCustomNames)
        refreshSpacesSnapshot()
    }
}

// MARK: - Desktop Switcher Wiring

@MainActor
extension SCCoordinator {
    func wireDesktopSwitcherCallbacks() {
        guard let controller = desktopSwitcherController else { return }
        controller.snapshotProvider = { [weak self] in
            self?.latestSpacesSnapshot
        }
        controller.onActivateDesktop = { [weak self] spaceIndex in
            self?.activateDesktop(spaceIndex)
        }
        controller.onActivateFullscreenDesktop = { [weak self] spaceID, screenUUID in
            self?.activateFullscreenDesktop(spaceID: spaceID, screenUUID: screenUUID)
        }
        controller.onRenameDesktop = { [weak self] spaceIndex, name in
            self?.setCustomSpaceName(name, for: spaceIndex)
        }
        controller.onReorderDesktops = { [weak self] spaceIndex, targetIndex in
            self?.reorderDesktop(spaceIndex: spaceIndex, targetIndex: targetIndex)
        }
        controller.onReorderFullscreenDesktops = { [weak self] spaceID, targetIndex in
            self?.reorderFullscreenDesktop(spaceID: spaceID, targetIndex: targetIndex)
        }
        controller.imageProvider = { [weak self] spaceID in
            self?.imageCaptureManager?.cachedImage(for: spaceID)
        }
    }

    func reorderDesktop(spaceIndex: Int, targetIndex: Int) {
        guard let oldIndex = spacesCustomOrder.firstIndex(of: spaceIndex) else { return }
        let safeTarget = max(0, min(targetIndex, spacesCustomOrder.count - 1))
        spacesCustomOrder.remove(at: oldIndex)
        spacesCustomOrder.insert(spaceIndex, at: safeTarget)
        SCPreferences.saveSpaceCustomOrder(spacesCustomOrder)
        refreshSpacesSnapshot()
    }

    func reorderFullscreenDesktop(spaceID: UInt64, targetIndex: Int) {
        guard let oldIndex = spacesFullscreenCustomOrder.firstIndex(of: spaceID) else { return }
        let safeTarget = max(0, min(targetIndex, spacesFullscreenCustomOrder.count - 1))
        spacesFullscreenCustomOrder.remove(at: oldIndex)
        spacesFullscreenCustomOrder.insert(spaceID, at: safeTarget)
        SCPreferences.saveFullscreenSpaceCustomOrder(spacesFullscreenCustomOrder)
        refreshSpacesSnapshot()
    }
}

// MARK: - Regular Desktop Activation

@MainActor
extension SCCoordinator {
    func activateRegularDesktopWithVerification(spaceIndex: Int, requestID: UUID) {
        if activateRegularDesktopViaWindowFocus(spaceIndex: spaceIndex) {
            verifyDesktopSwitch(spaceIndex: spaceIndex, requestID: requestID, attempt: 1, fallbackUsed: false)
            return
        }
        if activateRegularDesktopViaShortcut(spaceIndex: spaceIndex) {
            verifyDesktopSwitch(spaceIndex: spaceIndex, requestID: requestID, attempt: 1, fallbackUsed: true)
            return
        }
        Logger.warning { "Regular desktop activation failed spaceIndex=\(spaceIndex)" }
        NSSound.beep()
        refreshSpacesSnapshot()
    }

    func activateRegularDesktopViaWindowFocus(spaceIndex: Int) -> Bool {
        guard let snapshot = latestSpacesSnapshot,
              let targetSpace = snapshot.spaces.first(where: { $0.spaceIndex == spaceIndex }) else {
            return false
        }
        guard let topBundleID = targetSpace.bundleIDs.first else {
            return false
        }
        let targetWindow = Windows.list.first { window in
            guard !window.isWindowlessApp,
                  !window.isMinimized,
                  !window.isHidden,
                  window.application.bundleIdentifier == topBundleID else {
                return false
            }
            let rawSpaceIndex = spaceIndexForNormalized(spaceIndex)
            return window.spaceIndexes.contains(rawSpaceIndex ?? spaceIndex)
        }
        guard let targetWindow else { return false }
        targetWindow.focus()
        Logger.info { "Regular desktop activation via window focus spaceIndex=\(spaceIndex) bundleID=\(topBundleID)" }
        return true
    }

    func activateRegularDesktopViaShortcut(spaceIndex: Int) -> Bool {
        let success = SCSpaceActivator.activateSpace(index: spaceIndex)
        if success {
            Logger.info { "Regular desktop activation via shortcut spaceIndex=\(spaceIndex)" }
        }
        return success
    }

    func verifyDesktopSwitch(spaceIndex: Int, requestID: UUID, attempt: Int, fallbackUsed: Bool) {
        guard pendingActivationID == requestID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationVerificationDelay) { [weak self] in
            guard let self, self.pendingActivationID == requestID else { return }
            Spaces.refresh()
            let snapshot = SCSpacesSnapshotBuilder.build(
                customNames: self.spacesCustomNames,
                preferredOrder: self.spacesCustomOrder,
                fullscreenPreferredOrder: self.spacesFullscreenCustomOrder
            )
            if snapshot.currentSpaceIndex == spaceIndex {
                self.latestSpacesSnapshot = snapshot
                self.pendingActivationID = nil
                self.refreshSpacesSnapshot()
                return
            }
            if attempt < Self.activationVerificationAttempts {
                self.verifyDesktopSwitch(spaceIndex: spaceIndex, requestID: requestID, attempt: attempt + 1, fallbackUsed: fallbackUsed)
                return
            }
            Logger.warning { "Desktop switch verification failed after \(attempt) attempts spaceIndex=\(spaceIndex)" }
            if !fallbackUsed {
                if self.activateRegularDesktopViaShortcut(spaceIndex: spaceIndex) {
                    self.verifyDesktopSwitch(spaceIndex: spaceIndex, requestID: requestID, attempt: 1, fallbackUsed: true)
                    return
                }
            }
            if fallbackUsed {
                self.pendingActivationID = nil
                self.refreshSpacesSnapshot()
                return
            }
            NSSound.beep()
            self.pendingActivationID = nil
            self.refreshSpacesSnapshot()
        }
    }

    func spaceIndexForNormalized(_ normalizedIndex: Int) -> Int? {
        let allSpaces = Spaces.idsAndIndexes
        let fullscreenIds = Spaces.fullscreenSpaceIds
        let nonFullscreen = allSpaces.filter { !fullscreenIds.contains($0.0) }
            .sorted(by: { $0.1 < $1.1 })
        guard (normalizedIndex - 1) >= 0, (normalizedIndex - 1) < nonFullscreen.count else {
            return nil
        }
        return nonFullscreen[normalizedIndex - 1].1
    }
}

// MARK: - Fullscreen Desktop Activation

@MainActor
extension SCCoordinator {
    func activateFullscreenDesktopViaWindowFocus(spaceID: UInt64) -> Bool {
        guard let rawSpaceIndex = Spaces.idsAndIndexes.first(where: { $0.0 == spaceID })?.1 else {
            return false
        }
        let targetWindow = Windows.list.first { window in
            guard !window.isWindowlessApp,
                  !window.isMinimized,
                  !window.isHidden else {
                return false
            }
            return window.spaceIndexes.contains(rawSpaceIndex)
        }
        guard let targetWindow else { return false }
        targetWindow.focus()
        Logger.info { "Fullscreen desktop activation via window focus spaceID=\(spaceID)" }
        return true
    }
}

// MARK: - Spatial Navigation

@MainActor
extension SCCoordinator {
    nonisolated static func spatialDesktopAttemptPlan(
        snapshot: SpacesSnapshot?,
        direction: SpatialDirection,
        configuredRegularColumns: Int,
        previewSize: DesktopPreviewSize
    ) -> SCSpatialDesktopAttemptPlan {
        guard let snapshot else {
            return SCSpatialDesktopAttemptPlan(overlay: .unavailable, action: .beep)
        }
        guard let resolution = SCDesktopSwitcherController.spatialMoveResolution(
            snapshot: snapshot,
            direction: direction,
            configuredRegularColumns: configuredRegularColumns,
            previewSize: previewSize
        ) else {
            return SCSpatialDesktopAttemptPlan(overlay: .unavailable, action: .beep)
        }
        let overlayPlan = SCSpatialDesktopOverlayPlan.grid(
            entries: resolution.entries,
            frames: resolution.frames,
            sourceIndex: resolution.sourceIndex,
            targetIndex: resolution.targetIndex
        )
        guard let targetIndex = resolution.targetIndex,
              resolution.entries.indices.contains(targetIndex) else {
            return SCSpatialDesktopAttemptPlan(overlay: overlayPlan, action: .beep)
        }
        switch resolution.entries[targetIndex] {
        case .regular(let desktop):
            return SCSpatialDesktopAttemptPlan(
                overlay: overlayPlan,
                action: .activateRegular(spaceIndex: desktop.spaceIndex)
            )
        case .fullscreen(let desktop):
            return SCSpatialDesktopAttemptPlan(
                overlay: overlayPlan,
                action: .activateFullscreen(spaceID: desktop.spaceId, screenUUID: desktop.screenUUID)
            )
        }
    }
}

// MARK: - Configuration Warning

@MainActor
extension SCCoordinator {
    func maybeWarnAboutConfiguration(_ snapshot: SpacesSnapshot) {
        guard !snapshot.hasExpectedConfiguration else { return }
        guard !hasShownConfigurationWarning else { return }
        hasShownConfigurationWarning = true
        let missing = snapshot.missingExpectedIndices.map(String.init).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Spaces Configuration Warning", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString(
                "Space Commander expects desktops 1-9 to have Ctrl+1...9 shortcuts configured in System Settings > Keyboard > Keyboard Shortcuts > Mission Control. Missing desktop indexes: %@.",
                comment: ""
            ),
            missing
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { _ in }
    }
}

// MARK: - Hotkey Manager

private let scHotKeySignature: OSType = "spcm".utf8.reduce(0) { ($0 << 8) + OSType($1) }

@MainActor
class SCHotKeyManager {
    private static let signature: OSType = scHotKeySignature
    private static let shortcutEventTarget = GetEventDispatcherTarget()

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var pressedEventHandler: EventHandlerRef?

    var onDesktopSwitcherToggle: (() -> Void)?
    var onFirstEmptySpace: (() -> Void)?
    var onSpatialNavigation: ((SpatialDirection) -> Void)?

    private enum HotKeyID: UInt32 {
        case desktopSwitcher = 1
        case firstEmptySpace = 2
        case spatialLeft = 10
        case spatialRight = 11
        case spatialUp = 12
        case spatialDown = 13
    }

    func registerAll() {
        installHandler()
        let desktopCombo = SCPreferences.loadDesktopSwitcherShortcut()
        registerHotKey(
            id: .desktopSwitcher,
            keyCode: desktopCombo.keyCode,
            modifiers: desktopCombo.modifiers
        )
        let emptyCombo = SCPreferences.loadFirstEmptySpaceShortcut()
        registerHotKey(
            id: .firstEmptySpace,
            keyCode: emptyCombo.keyCode,
            modifiers: emptyCombo.modifiers
        )
        let spatialModifiers = SCPreferences.loadSpatialModifiers()
        registerHotKey(id: .spatialLeft, keyCode: UInt32(kVK_LeftArrow), modifiers: spatialModifiers)
        registerHotKey(id: .spatialRight, keyCode: UInt32(kVK_RightArrow), modifiers: spatialModifiers)
        registerHotKey(id: .spatialUp, keyCode: UInt32(kVK_UpArrow), modifiers: spatialModifiers)
        registerHotKey(id: .spatialDown, keyCode: UInt32(kVK_DownArrow), modifiers: spatialModifiers)
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = pressedEventHandler {
            RemoveEventHandler(handler)
            pressedEventHandler = nil
            // Balance the passRetained from installHandler()
            Unmanaged.passUnretained(self).release()
        }
    }

    private func registerHotKey(id: HotKeyID, keyCode: UInt32, modifiers: SCCarbonModifiers) {
        let hotkeyId = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        let carbonMods = carbonModifierFlags(from: modifiers)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hotkeyId, Self.shortcutEventTarget, UInt32(kEventHotKeyNoOptions), &ref)
        if status == noErr, let ref {
            hotKeyRefs[id.rawValue] = ref
        }
    }

    private func installHandler() {
        guard pressedEventHandler == nil else { return }
        var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))]
        let handlerRef = Unmanaged.passRetained(self).toOpaque()
        InstallEventHandler(Self.shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == scHotKeySignature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<SCHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.handleHotKeyPress(id: id.id)
            }
            return noErr
        }, eventTypes.count, &eventTypes, handlerRef, &pressedEventHandler)
    }

    private func handleHotKeyPress(id: UInt32) {
        guard let hotKeyID = HotKeyID(rawValue: id) else { return }
        switch hotKeyID {
        case .desktopSwitcher:
            onDesktopSwitcherToggle?()
        case .firstEmptySpace:
            onFirstEmptySpace?()
        case .spatialLeft:
            onSpatialNavigation?(.left)
        case .spatialRight:
            onSpatialNavigation?(.right)
        case .spatialUp:
            onSpatialNavigation?(.upward)
        case .spatialDown:
            onSpatialNavigation?(.down)
        }
    }

    private func carbonModifierFlags(from modifiers: SCCarbonModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
