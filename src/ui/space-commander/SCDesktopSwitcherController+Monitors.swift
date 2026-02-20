import Cocoa
import Carbon.HIToolbox

@MainActor
extension SCDesktopSwitcherController {
    func installMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.handleMouseDown(event) ? nil : event
        }

        localMouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            return self.handleMouseDragged(event) ? nil : event
        }

        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            return self.handleMouseUp(event) ? nil : event
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleGlobalMouseDown(event)
        }
    }

    func removeMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }
        if let localMouseDraggedMonitor {
            NSEvent.removeMonitor(localMouseDraggedMonitor)
            self.localMouseDraggedMonitor = nil
        }
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
            self.localMouseUpMonitor = nil
        }
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if renameField != nil {
            return handleRenameKeyDown(event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == UInt16(kVK_ANSI_R), modifiers.contains(.command) {
            _ = beginRenameIfNeeded()
            return true
        }

        if Self.isDeleteKey(event.keyCode) {
            return handleDeleteKey()
        }

        if Self.isSearchInputEvent(event) {
            return appendSearchQuery(from: event)
        }

        return handleNavigationKeyDown(event, modifiers: modifiers)
    }

    func handleRenameKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case UInt16(kVK_Return):
            commitRename()
            return true
        case UInt16(kVK_Escape):
            cancelRename()
            return true
        default:
            return false
        }
    }

    func handleNavigationKeyDown(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        if handleDismissOrActivateKeyDown(event) {
            return true
        }
        if handleTabNavigationKeyDown(event, modifiers: modifiers) {
            return true
        }
        if let direction = selectionDirection(for: event.keyCode) {
            moveSelection(direction)
            return true
        }
        return false
    }

    func handleDismissOrActivateKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case UInt16(kVK_Escape):
            if isSearchActive {
                clearSearchQuery()
            } else {
                dismiss()
            }
            return true
        case UInt16(kVK_Return):
            guard !entries.isEmpty else {
                return true
            }
            activateSelected()
            return true
        default:
            return false
        }
    }

    func handleTabNavigationKeyDown(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == UInt16(kVK_Tab) else {
            return false
        }
        if modifiers.contains(.shift) {
            cyclePrev()
        } else {
            cycleNext()
        }
        return true
    }

    func selectionDirection(for keyCode: UInt16) -> SpatialDirection? {
        switch keyCode {
        case UInt16(kVK_RightArrow):
            return .right
        case UInt16(kVK_DownArrow):
            return .down
        case UInt16(kVK_LeftArrow):
            return .left
        case UInt16(kVK_UpArrow):
            return .upward
        default:
            return nil
        }
    }

    func appendSearchQuery(from event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return false
        }

        let appendableCharacters = characters.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
        guard !appendableCharacters.isEmpty else {
            return false
        }

        let selectedDesktopID = selectedDesktopIDForCurrentSelection()
        searchQuery.append(appendableCharacters)
        applyFilterAndRebuild(preserveSelectedDesktopID: selectedDesktopID)
        return true
    }

    func handleDeleteKey() -> Bool {
        guard !searchQuery.isEmpty else {
            return false
        }

        let selectedDesktopID = selectedDesktopIDForCurrentSelection()
        searchQuery = Self.searchQueryAfterBackspace(searchQuery)
        applyFilterAndRebuild(preserveSelectedDesktopID: selectedDesktopID)
        return true
    }

    func clearSearchQuery() {
        guard !searchQuery.isEmpty else {
            return
        }
        let selectedDesktopID = selectedDesktopIDForCurrentSelection()
        searchQuery = ""
        applyFilterAndRebuild(preserveSelectedDesktopID: selectedDesktopID)
    }

    func handleMouseDown(_ event: NSEvent) -> Bool {
        guard isVisible, let panel, event.window === panel else {
            return false
        }

        let windowPoint = event.locationInWindow
        guard let documentView else {
            return false
        }

        let documentPoint = documentView.convert(windowPoint, from: nil)

        let isRenaming = renameField != nil
        let isInsideRenameField = isPointInsideRenameField(windowPoint)
        if Self.shouldCommitRenameOnLocalMouseDown(
            isRenaming: isRenaming,
            isPointInsideRenameField: isInsideRenameField
        ) {
            commitRename()
        } else if isRenaming, isInsideRenameField {
            return false
        }

        guard let index = desktopIndex(at: documentPoint) else {
            dismiss()
            return true
        }

        guard entries.indices.contains(index) else {
            return true
        }

        selectedIndex = index
        updateSelection()

        if titleContains(point: documentPoint, desktopIndex: index) {
            if beginRenameIfNeeded() {
                return true
            }
        }

        let desktop = entries[index]
        let cardFrame = cardViewsByDesktopID[desktop.stableID]?.frame ?? .zero
        dragSession = DragSession(
            sourceIndex: index,
            currentTargetIndex: index,
            startPoint: documentPoint,
            pointerOffsetInCard: CGPoint(
                x: documentPoint.x - cardFrame.minX,
                y: documentPoint.y - cardFrame.minY
            ),
            draggedItemID: desktop.stableID,
            draggedKind: desktop.kind,
            draggedRegularSpaceIndex: desktop.regularSpaceIndex,
            draggedFullscreenSpaceID: desktop.fullscreenSpaceID,
            isActive: false
        )
        return true
    }

    func handleMouseDragged(_ event: NSEvent) -> Bool {
        guard isVisible,
              let panel,
              event.window === panel,
              var dragSession,
              let documentView else {
            return false
        }

        if isSearchActive {
            self.dragSession = dragSession
            return true
        }

        let documentPoint = documentView.convert(event.locationInWindow, from: nil)
        let distance = hypot(documentPoint.x - dragSession.startPoint.x, documentPoint.y - dragSession.startPoint.y)

        if !dragSession.isActive {
            guard distance > dragActivationDistance else {
                return true
            }
            dragSession.isActive = true
            setLifted(true, for: dragSession.draggedItemID)
        }

        if let draggedCard = cardViewsByDesktopID[dragSession.draggedItemID] {
            let newOrigin = CGPoint(
                x: documentPoint.x - dragSession.pointerOffsetInCard.x,
                y: documentPoint.y - dragSession.pointerOffsetInCard.y
            )
            draggedCard.frame.origin = newOrigin
        }

        let targetIndex = Self.nearestInsertionIndex(for: documentPoint, in: baseCardFrames) ?? dragSession.sourceIndex
        if targetIndex != dragSession.currentTargetIndex,
           destinationIsAllowed(
               sourceKind: dragSession.draggedKind,
               sourceIndex: dragSession.sourceIndex,
               destinationIndex: targetIndex
           ) {
            dragSession.currentTargetIndex = targetIndex
            let previewOrder = Self.previewOrder(
                itemCount: entries.count,
                sourceIndex: dragSession.sourceIndex,
                destinationIndex: targetIndex
            )
            applyPreviewLayout(
                order: previewOrder,
                animated: true,
                preserveDraggedCardPosition: true
            )
        }

        self.dragSession = dragSession
        return true
    }

    func handleMouseUp(_ event: NSEvent) -> Bool {
        guard isVisible, let panel, event.window === panel else {
            return false
        }

        guard let dragSession else {
            return true
        }

        self.dragSession = nil

        let sourceIndex = dragSession.sourceIndex
        if !dragSession.isActive {
            return handleMouseUpWithoutDrag(event: event, sourceIndex: sourceIndex, dragSession: dragSession)
        }

        setLifted(false, for: dragSession.draggedItemID)
        handleCompletedDragSession(dragSession, sourceIndex: sourceIndex)
        return true
    }

    func handleMouseUpWithoutDrag(
        event: NSEvent,
        sourceIndex: Int,
        dragSession: DragSession
    ) -> Bool {
        guard entries.indices.contains(sourceIndex) else {
            return true
        }

        let releasedIndex: Int?
        if let documentView {
            let releasedPoint = documentView.convert(event.locationInWindow, from: nil)
            releasedIndex = desktopIndex(at: releasedPoint)
        } else {
            releasedIndex = nil
        }

        if Self.shouldActivateOnMouseUp(
            isDragActive: dragSession.isActive,
            sourceIndex: sourceIndex,
            releasedIndex: releasedIndex
        ) {
            selectedIndex = sourceIndex
            activateSelected()
        }
        return true
    }

    func handleCompletedDragSession(_ dragSession: DragSession, sourceIndex: Int) {
        let targetIndex = dragSession.currentTargetIndex
        guard entries.indices.contains(sourceIndex),
              entries.indices.contains(targetIndex),
              destinationIsAllowed(
                  sourceKind: dragSession.draggedKind,
                  sourceIndex: sourceIndex,
                  destinationIndex: targetIndex
              ) else {
            applyPreviewLayout(order: Array(entries.indices), animated: true)
            applyDeferredSnapshotIfNeeded()
            return
        }

        let didMove = sourceIndex != targetIndex
        applyDragResult(sourceIndex: sourceIndex, targetIndex: targetIndex)
        applyPreviewLayout(order: Array(entries.indices), animated: true)
        updateSelection()

        if didMove {
            publishDragReorder(dragSession: dragSession, targetIndex: targetIndex)
        } else {
            applyDeferredSnapshotIfNeeded()
        }
    }

    func applyDragResult(sourceIndex: Int, targetIndex: Int) {
        if sourceIndex != targetIndex {
            let movedDesktop = entries.remove(at: sourceIndex)
            entries.insert(movedDesktop, at: targetIndex)
            selectedIndex = targetIndex
            return
        }
        selectedIndex = sourceIndex
    }

    func publishDragReorder(dragSession: DragSession, targetIndex: Int) {
        deferredSnapshotAfterDrag = nil
        deferredSnapshotSignatureAfterDrag = nil
        let sectionIDs = entries.map { $0.kind == .fullscreen ? 0 : 1 }
        switch dragSession.draggedKind {
        case .regular:
            guard let spaceIndex = dragSession.draggedRegularSpaceIndex else {
                return
            }
            let destinationPosition = Self.destinationPositionWithinSection(
                sectionIDs: sectionIDs,
                destinationIndex: targetIndex,
                sectionID: 1
            )
            onReorderDesktops?(spaceIndex, destinationPosition)

        case .fullscreen:
            guard let spaceID = dragSession.draggedFullscreenSpaceID else {
                return
            }
            let destinationPosition = Self.destinationPositionWithinSection(
                sectionIDs: sectionIDs,
                destinationIndex: targetIndex,
                sectionID: 0
            )
            onReorderFullscreenDesktops?(spaceID, destinationPosition)
        }
    }

    func handleGlobalMouseDown(_ event: NSEvent) {
        guard isVisible else { return }
        let screenPoint = event.locationInWindow
        guard !isPointInsidePanel(screenPoint) else { return }
        if Self.shouldCommitRenameOnGlobalMouseDown(
            isRenaming: renameField != nil,
            isPointInsidePanel: false
        ) {
            commitRename()
        }
        dismiss()
    }

    nonisolated static func shouldCommitRenameOnLocalMouseDown(
        isRenaming: Bool,
        isPointInsideRenameField: Bool
    ) -> Bool {
        isRenaming && !isPointInsideRenameField
    }

    nonisolated static func shouldCommitRenameOnGlobalMouseDown(
        isRenaming: Bool,
        isPointInsidePanel: Bool
    ) -> Bool {
        isRenaming && !isPointInsidePanel
    }

}
