import Cocoa

@MainActor
extension SCDesktopSwitcherController {
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func cleanup() {
        dismiss()
    }

    func toggle() {
        let now = ProcessInfo.processInfo.systemUptime
        if let panel, panel.isVisible {
            if now - lastShowUptime < duplicateToggleSuppressionInterval {
                return
            }

            if !panel.occlusionState.contains(.visible) {
                NSApp.activate(ignoringOtherApps: true)
                panel.orderFrontRegardless()
                panel.makeKey()
                lastShowUptime = now
                return
            }

            dismiss()
            return
        }
        show()
    }

    func show() {
        guard let snapshot = snapshotProvider?(),
              !(snapshot.spaces.isEmpty && snapshot.fullscreenSpaces.isEmpty) else {
            Logger.info { "Desktop switcher has no spaces to display" }
            return
        }

        searchQuery = ""
        let preferredSelectedDesktopID = Self.preferredInitialDesktopStableID(snapshot: snapshot)
        applySnapshot(
            snapshot,
            signature: Self.snapshotSignature(for: snapshot),
            preferredSelectedDesktopID: preferredSelectedDesktopID
        )

        guard panel != nil else {
            allEntries = []
            entries = []
            return
        }

        lastShowUptime = ProcessInfo.processInfo.systemUptime
        updateSelection()
        installMonitors()
    }

    func refreshIfVisible() {
        refreshIfVisible(force: false)
    }

    func refreshIfVisible(force: Bool) {
        guard isVisible else { return }
        guard let snapshot = snapshotProvider?(),
              !(snapshot.spaces.isEmpty && snapshot.fullscreenSpaces.isEmpty) else {
            dismiss()
            return
        }

        let snapshotSignature = Self.snapshotSignature(for: snapshot)
        if !force, snapshotSignature == lastSnapshotSignature {
            return
        }

        if dragSession?.isActive == true {
            deferredSnapshotAfterDrag = snapshot
            deferredSnapshotSignatureAfterDrag = snapshotSignature
            return
        }

        applySnapshot(snapshot, signature: snapshotSignature)
    }

    func refreshIfVisibleCoalesced() {
        guard isVisible else { return }
        guard coalescedRefreshWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.coalescedRefreshWorkItem = nil
            self.refreshIfVisible()
        }
        coalescedRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshCoalescingInterval, execute: workItem)
    }

    func dismiss() {
        coalescedRefreshWorkItem?.cancel()
        coalescedRefreshWorkItem = nil
        savePanelFrame()
        endRenameMode(refresh: false)
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        scrollView = nil
        documentView = nil
        allEntries = []
        entries = []
        searchQuery = ""
        fullscreenVisibleCount = 0
        regularVisibleCount = 0
        cardViewsByDesktopID = [:]
        titleLabelsByDesktopID = [:]
        searchQueryPillView = nil
        searchQueryLabel = nil
        noResultsLabel = nil
        baseCardFrames = []
        displayOrder = []
        dragSession = nil
        deferredSnapshotAfterDrag = nil
        deferredSnapshotSignatureAfterDrag = nil
        lastSnapshotSignature = nil
    }

    func applySnapshot(
        _ snapshot: SpacesSnapshot,
        signature: DesktopSnapshotSignature,
        preferredSelectedDesktopID: String? = nil
    ) {
        lastSnapshotSignature = signature

        allEntries = snapshot.fullscreenSpaces.map(DesktopEntry.fullscreen) + snapshot.spaces.map(DesktopEntry.regular)
        let selectedDesktopID = preferredSelectedDesktopID ?? selectedDesktopIDForCurrentSelection()
        applyFilterAndRebuild(preserveSelectedDesktopID: selectedDesktopID)
    }

    func selectedDesktopIDForCurrentSelection() -> String? {
        guard entries.indices.contains(selectedIndex) else {
            return nil
        }
        return entries[selectedIndex].stableID
    }

    func applyFilterAndRebuild(preserveSelectedDesktopID: String?) {
        let indices = Self.filteredDesktopIndices(desktops: allEntries, query: searchQuery)
        entries = indices.map { allEntries[$0] }
        displayOrder = Array(entries.indices)
        fullscreenVisibleCount = entries.filter { $0.kind == .fullscreen }.count
        regularVisibleCount = entries.count - fullscreenVisibleCount

        if let preserveSelectedDesktopID,
           let preservedIndex = entries.firstIndex(where: { $0.stableID == preserveSelectedDesktopID }) {
            selectedIndex = preservedIndex
        } else {
            selectedIndex = 0
        }

        buildPanel()
        updateSelection()
    }

    func applyDeferredSnapshotIfNeeded() {
        guard let deferredSnapshotAfterDrag,
              let deferredSnapshotSignatureAfterDrag else {
            return
        }

        self.deferredSnapshotAfterDrag = nil
        self.deferredSnapshotSignatureAfterDrag = nil
        applySnapshot(deferredSnapshotAfterDrag, signature: deferredSnapshotSignatureAfterDrag)
    }
}
