import Cocoa
import Carbon.HIToolbox

enum SCSpatialDesktopAttemptAction: Equatable {
    case beep
    case activateRegular(spaceIndex: Int)
    case activateFullscreen(spaceID: UInt64, screenUUID: String)
}

@MainActor
class SCCoordinator {
    static var shared: SCCoordinator?
    static let spacesPollInterval: TimeInterval = 3.0
    static let activationVerificationAttempts = 4
    static let activationVerificationDelay: TimeInterval = 0.18

    var desktopSwitcherController: SCDesktopSwitcherController?
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
    var lastFocusedWindowBySpace: [CGSSpaceID: CGWindowID] = [:]

    func start() {
        spacesCustomNames = SCPreferences.loadSpaceCustomNames()
        spacesCustomOrder = SCPreferences.loadSpaceCustomOrder()
        spacesFullscreenCustomOrder = SCPreferences.loadFullscreenSpaceCustomOrder()
        desktopSwitcherController = SCDesktopSwitcherController()
        statusBarController = SCStatusBarController()
        wireDesktopSwitcherCallbacks()
        statusBarController?.onActivateDesktop = { [weak self] spaceIndex in
            self?.activateDesktop(spaceIndex)
        }
        statusBarController?.onActivateFullscreenDesktop = { [weak self] spaceID, screenUUID in
            self?.activateFullscreenDesktop(spaceID: spaceID, screenUUID: screenUUID)
        }
        statusBarController?.onPreferences = {
            App.showSettingsWindow()
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
        hotKeyManager?.onFullscreenNumberedShortcut = { [weak self] shortcutIndex in
            self?.activateFullscreenDesktopForShortcutIndex(shortcutIndex)
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
        statusBarController = nil
        latestSpacesSnapshot = nil
        lastFocusedWindowBySpace.removeAll()
    }

    func recordFocusedWindow(_ cgWindowId: CGWindowID, spaceId: CGSSpaceID) {
        guard let rawSpaceIndex = Spaces.idsAndIndexes.first(where: { $0.0 == spaceId })?.1,
              let window = Windows.list.first(where: { $0.cgWindowId == cgWindowId }),
              window.spaceIndexes.contains(rawSpaceIndex) else {
            return
        }
        lastFocusedWindowBySpace[spaceId] = cgWindowId
    }

    private func lastFocusedWindow(forSpaceId spaceId: CGSSpaceID, rawSpaceIndex: Int) -> Window? {
        guard let savedWindowId = lastFocusedWindowBySpace[spaceId] else { return nil }
        let match = Windows.list.first { window in
            guard window.cgWindowId == savedWindowId,
                  !window.isWindowlessApp,
                  !window.isMinimized,
                  !window.isHidden,
                  window.spaceIndexes.contains(rawSpaceIndex) else {
                return false
            }
            return true
        }
        if match == nil {
            lastFocusedWindowBySpace.removeValue(forKey: spaceId)
        }
        return match
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
        recordCurrentFocusedWindowForDepartingSpace()
        refreshSpacesSnapshot()
    }

    private func recordCurrentFocusedWindowForDepartingSpace() {
        guard let frontmostPid = Applications.frontmostPid,
              let frontmostApp = Applications.findOrCreate(frontmostPid, false),
              let focusedWindow = frontmostApp.focusedWindow,
              let cgWindowId = focusedWindow.cgWindowId else { return }
        let departingSpaceId = Spaces.currentSpaceId
        lastFocusedWindowBySpace[departingSpaceId] = cgWindowId
    }

    func refreshSpacesSnapshot() {
        Spaces.refresh()
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
        hotKeyManager?.updateFullscreenNumberedShortcuts(count: snapshot.fullscreenSpaces.count)
        if SCPreferences.loadDesktopPreviewStyle() == .images {
            let allSpaceIDs = Set(snapshot.spaces.map(\.spaceId) + snapshot.fullscreenSpaces.map(\.spaceId))
            imageCaptureManager?.pruneStaleEntries(currentSpaceIDs: allSpaceIDs)
            imageCaptureManager?.captureVisibleSpaces(excludingWindowNumbers: panelWindowNumbers())
        }
        statusBarController?.setSpacesSnapshot(snapshot)
        statusBarController?.setActiveDesktopIndex(snapshot.currentSpaceIndex)
        desktopSwitcherController?.refreshIfVisibleCoalesced()
        maybeWarnAboutConfiguration(snapshot)
    }

    func panelWindowNumbers() -> [Int] {
        var numbers = [Int]()
        if let wn = desktopSwitcherController?.panel?.windowNumber, wn > 0 {
            numbers.append(wn)
        }
        return numbers
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
        guard let firstEmpty = Self.firstEmptyRegularDesktop(in: snapshot) else {
            NSSound.beep()
            return
        }
        activateDesktop(firstEmpty.spaceIndex)
    }

    func handleSpatialNavigation(_ direction: SpatialDirection) {
        desktopSwitcherController?.dismiss()
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screenAspectRatio = screen?.ratio() ?? (16.0 / 9.0)
        let screenSize = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let fullscreenCount = latestSpacesSnapshot?.fullscreenSpaces.count ?? 0
        let regularCount = latestSpacesSnapshot?.spaces.count ?? 0
        let cardWidth = SCDesktopSwitcherController.resolvedCardWidth(
            screenSize: screenSize,
            screenAspectRatio: screenAspectRatio,
            fullscreenCount: fullscreenCount,
            regularCount: regularCount,
            configuredColumns: SCPreferences.loadDesktopColumns(),
            isSearchActive: false
        )
        let action = Self.spatialDesktopAttemptAction(
            snapshot: latestSpacesSnapshot,
            direction: direction,
            configuredRegularColumns: SCPreferences.loadDesktopColumns(),
            cardWidth: cardWidth,
            screenAspectRatio: screenAspectRatio
        )
        switch action {
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

    func activateFullscreenDesktopForShortcutIndex(_ shortcutIndex: Int) {
        guard shortcutIndex >= 1,
              let fullscreenSpace = latestSpacesSnapshot?.fullscreenSpaces[safe: shortcutIndex - 1] else {
            return
        }
        activateFullscreenDesktop(spaceID: fullscreenSpace.spaceId, screenUUID: fullscreenSpace.screenUUID)
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
        let rawSpaceIndex = spaceIndexForNormalized(spaceIndex) ?? spaceIndex
        if let lastFocused = lastFocusedWindow(forSpaceId: targetSpace.spaceId, rawSpaceIndex: rawSpaceIndex) {
            lastFocused.focus()
            Logger.info { "Regular desktop activation via last-focused window spaceIndex=\(spaceIndex) wid=\(lastFocused.cgWindowId ?? 0)" }
            return true
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
            return window.spaceIndexes.contains(rawSpaceIndex)
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
            Logger.warning { "Desktop switch verification failed after \(attempt) attempts targetSpaceIndex=\(spaceIndex) currentSpaceIndex=\(snapshot.currentSpaceIndex)" }
            if !fallbackUsed {
                if self.activateRegularDesktopViaShortcut(spaceIndex: spaceIndex) {
                    self.verifyDesktopSwitch(spaceIndex: spaceIndex, requestID: requestID, attempt: 1, fallbackUsed: true)
                    return
                }
            }
            if fallbackUsed {
                NSSound.beep()
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

    nonisolated static func firstEmptyRegularDesktop(in snapshot: SpacesSnapshot) -> SpaceSnapshotItem? {
        if let currentScreenUUID = snapshot.currentSpace?.screenUUID,
           let firstOnCurrent = snapshot.spaces.first(where: { $0.bundleIDs.isEmpty && !$0.isCurrent && $0.screenUUID == currentScreenUUID }) {
            return firstOnCurrent
        }
        return snapshot.spaces.first(where: { $0.bundleIDs.isEmpty && !$0.isCurrent })
    }
}

// MARK: - Fullscreen Desktop Activation

@MainActor
extension SCCoordinator {
    func activateFullscreenDesktopViaWindowFocus(spaceID: UInt64) -> Bool {
        guard let rawSpaceIndex = Spaces.idsAndIndexes.first(where: { $0.0 == spaceID })?.1 else {
            return false
        }
        if let lastFocused = lastFocusedWindow(forSpaceId: spaceID, rawSpaceIndex: rawSpaceIndex) {
            lastFocused.focus()
            Logger.info { "Fullscreen desktop activation via last-focused window spaceID=\(spaceID) wid=\(lastFocused.cgWindowId ?? 0)" }
            return true
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
    nonisolated static func spatialDesktopAttemptAction(
        snapshot: SpacesSnapshot?,
        direction: SpatialDirection,
        configuredRegularColumns: Int,
        cardWidth: CGFloat,
        screenAspectRatio: CGFloat
    ) -> SCSpatialDesktopAttemptAction {
        guard let snapshot else {
            return .beep
        }
        guard let resolution = SCDesktopSwitcherController.spatialMoveResolution(
            snapshot: snapshot,
            direction: direction,
            configuredRegularColumns: configuredRegularColumns,
            cardWidth: cardWidth,
            screenAspectRatio: screenAspectRatio
        ) else {
            return .beep
        }
        guard let targetIndex = resolution.targetIndex,
              resolution.entries.indices.contains(targetIndex) else {
            return .beep
        }
        switch resolution.entries[targetIndex] {
        case .regular(let desktop):
            return .activateRegular(spaceIndex: desktop.spaceIndex)
        case .fullscreen(let desktop):
            return .activateFullscreen(spaceID: desktop.spaceId, screenUUID: desktop.screenUUID)
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
    nonisolated private static let maxFullscreenShortcutCount = 9
    nonisolated private static let fullscreenShortcutHotKeyBaseID: UInt32 = 100

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var pressedEventHandler: EventHandlerRef?
    private var registeredFullscreenShortcutCount = 0
    private var registeredFullscreenShortcutModifiers: SCCarbonModifiers = []
    private var registeredFullscreenShortcutHotKeyIDs = Set<UInt32>()
    nonisolated(unsafe) private var firstEmptyHotKeyIsPressed = false

    // nonisolated(unsafe) so the Carbon callback can invoke them synchronously
    // (Carbon delivers hotkey events on the main thread, so access is safe)
    nonisolated(unsafe) var onDesktopSwitcherToggle: (() -> Void)?
    nonisolated(unsafe) var onFirstEmptySpace: (() -> Void)?
    nonisolated(unsafe) var onSpatialNavigation: ((SpatialDirection) -> Void)?
    nonisolated(unsafe) var onFullscreenNumberedShortcut: ((Int) -> Void)?

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

    func updateFullscreenNumberedShortcuts(count: Int) {
        let clampedCount = max(0, min(Self.maxFullscreenShortcutCount, count))
        let modifiers = SCPreferences.loadFullscreenShortcutModifiers()
        let expectedHotKeyIDs = Self.fullscreenShortcutHotKeyIDs(forCount: clampedCount)
        if clampedCount == registeredFullscreenShortcutCount,
           modifiers == registeredFullscreenShortcutModifiers,
           registeredFullscreenShortcutHotKeyIDs == expectedHotKeyIDs,
           expectedHotKeyIDs.allSatisfy({ hotKeyRefs[$0] != nil }) {
            return
        }
        unregisterFullscreenNumberedHotKeys()
        guard clampedCount > 0 else {
            registeredFullscreenShortcutModifiers = modifiers
            return
        }
        var successfulHotKeyIDs = Set<UInt32>()
        for shortcutIndex in 1...clampedCount {
            guard let hotKeyID = registerFullscreenNumberedHotKey(shortcutIndex: shortcutIndex, modifiers: modifiers) else {
                continue
            }
            successfulHotKeyIDs.insert(hotKeyID)
        }
        registeredFullscreenShortcutHotKeyIDs = successfulHotKeyIDs
        registeredFullscreenShortcutCount = clampedCount
        registeredFullscreenShortcutModifiers = modifiers
        if successfulHotKeyIDs.count != clampedCount {
            Logger.warning { "Fullscreen numbered hotkey registration incomplete requested=\(clampedCount) registered=\(successfulHotKeyIDs.count) modifiers=\(modifiers.rawValue)" }
        }
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredFullscreenShortcutCount = 0
        registeredFullscreenShortcutModifiers = []
        registeredFullscreenShortcutHotKeyIDs.removeAll()
        firstEmptyHotKeyIsPressed = false
        if let handler = pressedEventHandler {
            RemoveEventHandler(handler)
            pressedEventHandler = nil
            // Balance the passRetained from installHandler()
            Unmanaged.passUnretained(self).release()
        }
    }

    @discardableResult
    private func registerHotKey(id: HotKeyID, keyCode: UInt32, modifiers: SCCarbonModifiers) -> Bool {
        registerHotKey(rawID: id.rawValue, keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    private func registerHotKey(rawID: UInt32, keyCode: UInt32, modifiers: SCCarbonModifiers) -> Bool {
        let hotkeyId = EventHotKeyID(signature: Self.signature, id: rawID)
        let carbonMods = carbonModifierFlags(from: modifiers)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hotkeyId, Self.shortcutEventTarget, UInt32(kEventHotKeyNoOptions), &ref)
        if status == noErr, let ref {
            hotKeyRefs[rawID] = ref
            return true
        }
        Logger.warning { "Space Commander hotkey registration failed id=\(rawID) keyCode=\(keyCode) modifiers=\(modifiers.rawValue) status=\(status)" }
        return false
    }

    private func unregisterHotKey(rawID: UInt32) {
        guard let ref = hotKeyRefs.removeValue(forKey: rawID) else { return }
        UnregisterEventHotKey(ref)
    }

    private func installHandler() {
        guard pressedEventHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))
        ]
        let handlerRef = Unmanaged.passRetained(self).toOpaque()
        InstallEventHandler(Self.shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == scHotKeySignature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<SCHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKeyEvent(id: id.id, eventKind: GetEventKind(event))
            return noErr
        }, eventTypes.count, &eventTypes, handlerRef, &pressedEventHandler)
    }

    // nonisolated because this is called directly from the Carbon event handler
    nonisolated private func handleHotKeyEvent(id: UInt32, eventKind: UInt32) {
        let isPressed = eventKind == UInt32(kEventHotKeyPressed)
        let isReleased = eventKind == UInt32(kEventHotKeyReleased)
        if let shortcutIndex = Self.fullscreenShortcutIndex(for: id) {
            if isPressed {
                onFullscreenNumberedShortcut?(shortcutIndex)
            }
            return
        }
        guard let hotKeyID = HotKeyID(rawValue: id) else { return }
        switch hotKeyID {
        case .desktopSwitcher:
            if isPressed { onDesktopSwitcherToggle?() }
        case .firstEmptySpace:
            if isPressed {
                firstEmptyHotKeyIsPressed = true
                return
            }
            guard isReleased, firstEmptyHotKeyIsPressed else { return }
            firstEmptyHotKeyIsPressed = false
            triggerFirstEmptySpaceWhenModifierKeysReleased()
        case .spatialLeft:
            if isPressed { onSpatialNavigation?(.left) }
        case .spatialRight:
            if isPressed { onSpatialNavigation?(.right) }
        case .spatialUp:
            if isPressed { onSpatialNavigation?(.upward) }
        case .spatialDown:
            if isPressed { onSpatialNavigation?(.down) }
        }
    }

    private func registerFullscreenNumberedHotKey(shortcutIndex: Int, modifiers: SCCarbonModifiers) -> UInt32? {
        guard let hotKeyID = Self.fullscreenShortcutHotKeyID(for: shortcutIndex),
              let keyCode = SCSpaceActivator.keyCode(forSpaceIndex: shortcutIndex) else {
            return nil
        }
        return registerHotKey(rawID: hotKeyID, keyCode: UInt32(keyCode), modifiers: modifiers) ? hotKeyID : nil
    }

    private func unregisterFullscreenNumberedHotKeys() {
        guard !registeredFullscreenShortcutHotKeyIDs.isEmpty else {
            registeredFullscreenShortcutCount = 0
            return
        }
        for hotKeyID in registeredFullscreenShortcutHotKeyIDs {
            unregisterHotKey(rawID: hotKeyID)
        }
        registeredFullscreenShortcutHotKeyIDs.removeAll()
        registeredFullscreenShortcutCount = 0
    }

    nonisolated private static func fullscreenShortcutHotKeyID(for shortcutIndex: Int) -> UInt32? {
        guard (1...maxFullscreenShortcutCount).contains(shortcutIndex) else { return nil }
        return fullscreenShortcutHotKeyBaseID + UInt32(shortcutIndex - 1)
    }

    nonisolated private static func fullscreenShortcutIndex(for hotKeyID: UInt32) -> Int? {
        let maxHotKeyID = fullscreenShortcutHotKeyBaseID + UInt32(maxFullscreenShortcutCount - 1)
        guard hotKeyID >= fullscreenShortcutHotKeyBaseID, hotKeyID <= maxHotKeyID else { return nil }
        return Int(hotKeyID - fullscreenShortcutHotKeyBaseID) + 1
    }

    nonisolated private static func fullscreenShortcutHotKeyIDs(forCount count: Int) -> Set<UInt32> {
        guard count > 0 else { return [] }
        return Set((1...count).compactMap { fullscreenShortcutHotKeyID(for: $0) })
    }

    nonisolated private func triggerFirstEmptySpaceWhenModifierKeysReleased(retryCount: Int = 0) {
        let blockingMask = UInt32(cmdKey | optionKey | shiftKey)
        var retries = retryCount
        var blocking = GetCurrentKeyModifiers() & blockingMask
        while blocking != 0, retries < 25 {
            usleep(20_000)
            retries += 1
            blocking = GetCurrentKeyModifiers() & blockingMask
        }
        Logger.info { "First empty space hotkey released; triggering desktop activation retries=\(retries) blockingModifiers=\(blocking)" }
        onFirstEmptySpace?()
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
