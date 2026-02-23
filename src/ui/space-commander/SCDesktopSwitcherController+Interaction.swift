import Cocoa

@MainActor
extension SCDesktopSwitcherController {
    func beginRenameIfNeeded() -> Bool {
        guard entries.indices.contains(selectedIndex),
              Self.canRenameDesktop(isFullscreen: entries[selectedIndex].kind == .fullscreen),
              let titleLabel = titleLabel(for: selectedIndex),
              let cardView = titleLabel.superview else {
            return false
        }

        endRenameMode(refresh: false)

        let field = NSTextField(frame: titleLabel.frame)
        field.font = titleLabel.font
        field.stringValue = entries[selectedIndex].title
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel

        titleLabel.isHidden = true
        cardView.addSubview(field)
        cardView.window?.makeFirstResponder(field)

        renameField = field
        renamingSpaceIndex = entries[selectedIndex].regularSpaceIndex
        renamingTitleLabel = titleLabel
        return true
    }

    func commitRename() {
        guard let spaceIndex = renamingSpaceIndex,
              let renameField else {
            endRenameMode(refresh: false)
            return
        }

        let trimmed = renameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let customNameOrNil = trimmed.isEmpty ? nil : trimmed
        applyOptimisticRename(spaceIndex: spaceIndex, customName: customNameOrNil)
        onRenameDesktop?(spaceIndex, customNameOrNil)
        endRenameMode(refresh: false)
    }

    func cancelRename() {
        endRenameMode(refresh: false)
    }

    func applyOptimisticRename(spaceIndex: Int, customName: String?) {
        let resolvedTitle = Self.resolvedRenamedDesktopTitle(spaceIndex: spaceIndex, customName: customName)

        allEntries = allEntries.map { entry in
            Self.entryByApplyingOptimisticTitle(entry, spaceIndex: spaceIndex, title: resolvedTitle)
        }
        entries = entries.map { entry in
            Self.entryByApplyingOptimisticTitle(entry, spaceIndex: spaceIndex, title: resolvedTitle)
        }

        guard let entryIndex = entries.firstIndex(where: {
            if case .regular(let desktop) = $0 {
                return desktop.spaceIndex == spaceIndex
            }
            return false
        }) else {
            return
        }

        let desktop = entries[entryIndex]
        let desktopID = desktop.stableID
        if let titleLabel = titleLabelsByDesktopID[desktopID] {
            titleLabel.stringValue = resolvedTitle
        }
        if let card = cardViewsByDesktopID[desktopID] {
            card.setAccessibilityLabel("\(resolvedTitle) \(desktop.subtitle)")
        }
    }

    func endRenameMode(refresh: Bool) {
        renameField?.removeFromSuperview()
        renameField = nil
        renamingTitleLabel?.isHidden = false
        renamingTitleLabel = nil
        renamingSpaceIndex = nil

        if refresh {
            refreshIfVisible()
        }
    }

    func activateSelected() {
        guard entries.indices.contains(selectedIndex) else {
            dismiss()
            return
        }

        let selectedDesktop = entries[selectedIndex]
        switch selectedDesktop {
        case .regular(let desktop):
            onActivateDesktop?(desktop.spaceIndex)
        case .fullscreen(let desktop):
            onActivateFullscreenDesktop?(desktop.spaceId, desktop.screenUUID)
        }
        dismiss()
    }

    func cycleNext() {
        guard !entries.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % entries.count
        updateSelection()
    }

    func cyclePrev() {
        guard !entries.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + entries.count) % entries.count
        updateSelection()
    }

    func moveSelection(_ direction: SpatialDirection) {
        guard entries.indices.contains(selectedIndex) else {
            return
        }

        let itemFrames = entries.compactMap { cardViewsByDesktopID[$0.stableID]?.frame }
        let moveForward = direction == .right || direction == .down

        if itemFrames.count == entries.count,
           let targetIndex = Self.directionalMoveTargetIndex(
               currentIndex: selectedIndex,
               itemFrames: itemFrames,
               direction: direction
           ) {
            selectedIndex = targetIndex
            updateSelection()
            return
        }

        guard let fallbackIndex = Self.linearMoveTargetIndex(
            currentIndex: selectedIndex,
            itemCount: entries.count,
            forward: moveForward
        ) else {
            return
        }

        selectedIndex = fallbackIndex
        updateSelection()
    }

    func desktopIndex(at point: CGPoint) -> Int? {
        guard let slotIndex = Self.cardIndex(for: point, frames: baseCardFrames),
              displayOrder.indices.contains(slotIndex) else {
            return nil
        }
        return displayOrder[slotIndex]
    }

    func titleLabel(for desktopIndex: Int) -> NSTextField? {
        guard entries.indices.contains(desktopIndex) else {
            return nil
        }
        return titleLabelsByDesktopID[entries[desktopIndex].stableID]
    }

    func titleContains(point: CGPoint, desktopIndex: Int) -> Bool {
        guard let titleLabel = titleLabel(for: desktopIndex),
              let documentView else {
            return false
        }
        let frame = titleLabel.convert(titleLabel.bounds, to: documentView)
        return Self.frameContainsInclusive(frame, point: point)
    }

    func destinationIsAllowed(
        sourceKind: DesktopKind,
        sourceIndex: Int,
        destinationIndex: Int
    ) -> Bool {
        guard entries.indices.contains(sourceIndex),
              entries.indices.contains(destinationIndex) else {
            return false
        }

        let sourceDesktop = entries[sourceIndex]
        let sectionIDs = entries.map { $0.kind == .fullscreen ? 0 : 1 }
        return sourceDesktop.kind == sourceKind
            && Self.canMoveWithinSection(
                sectionIDs: sectionIDs,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex
            )
    }

    func setLifted(_ isLifted: Bool, for desktopID: String) {
        guard let card = cardViewsByDesktopID[desktopID] else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = dragLiftAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            card.animator().alphaValue = isLifted ? 0.97 : 1
        }
        card.isLifted = isLifted
    }

    func isPointInsidePanel(_ screenPoint: CGPoint) -> Bool {
        guard let panel else { return false }
        return Self.frameContainsInclusive(panel.frame, point: screenPoint)
    }

    func isPointInsideRenameField(_ windowPoint: CGPoint) -> Bool {
        guard let renameField else { return false }
        let frame = renameField.convert(renameField.bounds, to: nil)
        return Self.frameContainsInclusive(frame, point: windowPoint)
    }

    func savePanelFrame() {
        guard let panel else { return }
        guard !SCPreferences.loadDesktopFullscreenMode() else { return }
        SCPreferences.saveDesktopSwitcherFrame(panel.frame)
    }

    func icon(for bundleID: String, size: CGFloat) -> NSImage? {
        let cacheKey = bundleID as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            let resized = (cached.copy() as? NSImage) ?? cached
            resized.size = NSSize(width: size, height: size)
            return resized
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let source = NSWorkspace.shared.icon(forFile: appURL.path)
        iconCache.setObject(source, forKey: cacheKey)
        let resized = (source.copy() as? NSImage) ?? source
        resized.size = NSSize(width: size, height: size)
        return resized
    }
}
