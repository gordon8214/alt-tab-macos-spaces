import Cocoa
import Carbon.HIToolbox

extension SCDesktopSwitcherController {
    struct GridLayoutMetrics {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
    }

    struct PanelSpacingConstants {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let sectionSpacing: CGFloat
        let dividerWidth: CGFloat
    }

    struct SpatialMoveResolution {
        let entries: [DesktopEntry]
        let frames: [CGRect]
        let sourceIndex: Int
        let targetIndex: Int?
    }

    nonisolated static func panelSpacingConstants() -> PanelSpacingConstants {
        PanelSpacingConstants(
            horizontalPadding: 20,
            verticalPadding: 20,
            horizontalSpacing: 14,
            verticalSpacing: 16,
            sectionSpacing: 14,
            dividerWidth: 1
        )
    }

    nonisolated static func cardIndex(for point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex(where: { frameContainsInclusive($0, point: point) })
    }

    nonisolated static func nearestInsertionIndex(for point: CGPoint, in frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else {
            return nil
        }

        var nearestIndex = 0
        var nearestSquaredDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in frames.enumerated() {
            let deltaX = point.x - frame.midX
            let deltaY = point.y - frame.midY
            let squaredDistance = (deltaX * deltaX) + (deltaY * deltaY)
            if squaredDistance < nearestSquaredDistance {
                nearestIndex = index
                nearestSquaredDistance = squaredDistance
            }
        }
        return nearestIndex
    }

    nonisolated static func previewOrder(itemCount: Int, sourceIndex: Int, destinationIndex: Int) -> [Int] {
        guard itemCount > 0 else {
            return []
        }

        var order = Array(0 ..< itemCount)
        guard order.indices.contains(sourceIndex),
              order.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return order
        }

        let movedIndex = order.remove(at: sourceIndex)
        order.insert(movedIndex, at: destinationIndex)
        return order
    }

    nonisolated static func shouldActivateOnMouseUp(
        isDragActive: Bool,
        sourceIndex: Int,
        releasedIndex: Int?
    ) -> Bool {
        guard !isDragActive, sourceIndex >= 0, let releasedIndex else {
            return false
        }
        return sourceIndex == releasedIndex
    }

    nonisolated static func canMoveWithinSection(
        sectionIDs: [Int],
        sourceIndex: Int,
        destinationIndex: Int
    ) -> Bool {
        guard sectionIDs.indices.contains(sourceIndex),
              sectionIDs.indices.contains(destinationIndex) else {
            return false
        }
        return sectionIDs[sourceIndex] == sectionIDs[destinationIndex]
    }

    nonisolated static func linearMoveTargetIndex(
        currentIndex: Int,
        itemCount: Int,
        forward: Bool
    ) -> Int? {
        guard itemCount > 0, currentIndex >= 0, currentIndex < itemCount else {
            return nil
        }

        if forward {
            return (currentIndex + 1) % itemCount
        }
        return (currentIndex - 1 + itemCount) % itemCount
    }

    nonisolated static func directionalMoveTargetIndex(
        currentIndex: Int,
        itemFrames: [CGRect],
        direction: SpatialDirection
    ) -> Int? {
        guard itemFrames.indices.contains(currentIndex) else {
            return nil
        }

        let currentFrame = itemFrames[currentIndex]
        let currentCenter = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        var bestIndex: Int?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for (index, frame) in itemFrames.enumerated() where index != currentIndex {
            let candidateCenter = CGPoint(x: frame.midX, y: frame.midY)
            let deltaX = candidateCenter.x - currentCenter.x
            let deltaY = candidateCenter.y - currentCenter.y

            switch direction {
            case .left where deltaX >= -1:
                continue
            case .right where deltaX <= 1:
                continue
            case .upward where deltaY >= -1:
                continue
            case .down where deltaY <= 1:
                continue
            default:
                break
            }

            let primaryDistance: CGFloat
            let secondaryDistance: CGFloat
            switch direction {
            case .left, .right:
                primaryDistance = abs(deltaX)
                secondaryDistance = abs(deltaY)
            case .upward, .down:
                primaryDistance = abs(deltaY)
                secondaryDistance = abs(deltaX)
            }

            let score = (primaryDistance * 1000) + secondaryDistance
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    nonisolated static func destinationPositionWithinSection(
        sectionIDs: [Int],
        destinationIndex: Int,
        sectionID: Int
    ) -> Int {
        guard destinationIndex >= 0, destinationIndex < sectionIDs.count else {
            return 0
        }
        return sectionIDs[..<destinationIndex].filter { $0 == sectionID }.count
    }

    nonisolated static func reorderCallbackDestinationPosition(
        sectionIDs: [Int],
        sourceIndex: Int,
        destinationIndex: Int
    ) -> Int? {
        guard canMoveWithinSection(
            sectionIDs: sectionIDs,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex
        ) else {
            return nil
        }

        var reordered = sectionIDs
        let movedSectionID = reordered.remove(at: sourceIndex)
        reordered.insert(movedSectionID, at: destinationIndex)
        return destinationPositionWithinSection(
            sectionIDs: reordered,
            destinationIndex: destinationIndex,
            sectionID: movedSectionID
        )
    }

    nonisolated static func canRenameDesktop(isFullscreen: Bool) -> Bool {
        !isFullscreen
    }

    nonisolated static func resolvedRenamedDesktopTitle(spaceIndex: Int, customName: String?) -> String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Desktop \(spaceIndex)"
    }

    nonisolated static func filteredDesktopIndices(
        desktops: [SpaceSnapshotItem],
        query: String
    ) -> [Int] {
        guard !query.isEmpty else {
            return Array(desktops.indices)
        }

        return desktops.enumerated().compactMap { index, desktop in
            desktop.title.localizedCaseInsensitiveContains(query) ? index : nil
        }
    }

    nonisolated static func preferredInitialDesktopStableID(snapshot: SpacesSnapshot) -> String? {
        if let fullscreenSpace = snapshot.fullscreenSpaces.first(where: \.isCurrent) {
            return "fullscreen:\(fullscreenSpace.spaceId)"
        }
        if let regularSpace = snapshot.spaces.first(where: \.isCurrent) {
            return "regular:\(regularSpace.spaceIndex)"
        }
        if snapshot.currentSpaceIndex > 0,
           snapshot.spaces.contains(where: { $0.spaceIndex == snapshot.currentSpaceIndex }) {
            return "regular:\(snapshot.currentSpaceIndex)"
        }
        return nil
    }

    static func filteredDesktopIndices(
        desktops: [DesktopEntry],
        query: String
    ) -> [Int] {
        guard !query.isEmpty else {
            return Array(desktops.indices)
        }

        return desktops.enumerated().compactMap { index, desktop in
            desktop.title.localizedCaseInsensitiveContains(query) ? index : nil
        }
    }

    nonisolated static func isSearchInputEvent(_ event: NSEvent) -> Bool {
        isSearchInputEvent(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        )
    }

    nonisolated static func isSearchInputEvent(
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let effectiveModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        if effectiveModifiers.contains(.command)
            || effectiveModifiers.contains(.option)
            || effectiveModifiers.contains(.control) {
            return false
        }

        if isDeleteKey(keyCode) {
            return false
        }

        switch keyCode {
        case UInt16(kVK_Escape),
             UInt16(kVK_Return),
             UInt16(kVK_Tab),
             UInt16(kVK_LeftArrow),
             UInt16(kVK_RightArrow),
             UInt16(kVK_UpArrow),
             UInt16(kVK_DownArrow):
            return false
        default:
            break
        }

        guard let characters,
              !characters.isEmpty else {
            return false
        }
        return characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) })
    }

    nonisolated static func searchQueryAfterBackspace(_ query: String) -> String {
        guard !query.isEmpty else {
            return ""
        }
        return String(query.dropLast())
    }

    nonisolated static func isDeleteKey(_ keyCode: UInt16) -> Bool {
        keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete)
    }

    nonisolated static func frameContainsInclusive(_ frame: CGRect, point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    nonisolated static func verticalMoveTargetIndex(
        currentIndex: Int,
        itemCount: Int,
        columnCount: Int,
        upward: Bool
    ) -> Int? {
        guard itemCount > 0, currentIndex >= 0, currentIndex < itemCount else {
            return nil
        }

        let normalizedColumnCount = max(1, columnCount)
        let candidate = upward
            ? currentIndex - normalizedColumnCount
            : currentIndex + normalizedColumnCount
        if candidate >= 0, candidate < itemCount {
            return candidate
        }

        if upward {
            return (currentIndex - 1 + itemCount) % itemCount
        }
        return (currentIndex + 1) % itemCount
    }

    nonisolated static func resolvedCardWidth(
        screenSize: CGSize,
        screenAspectRatio: CGFloat,
        fullscreenCount: Int,
        regularCount: Int,
        configuredColumns: Int,
        isSearchActive: Bool
    ) -> CGFloat {
        if SCPreferences.loadDesktopFullscreenMode() {
            return autoScaledCardWidth(
                screenSize: screenSize,
                screenAspectRatio: screenAspectRatio,
                fullscreenCount: fullscreenCount,
                regularCount: regularCount,
                configuredColumns: configuredColumns,
                isSearchActive: isSearchActive
            )
        }
        return SCPreferences.loadDesktopCardWidth()
    }

    nonisolated static func autoScaledCardWidth(
        screenSize: CGSize,
        screenAspectRatio: CGFloat,
        fullscreenCount: Int,
        regularCount: Int,
        configuredColumns: Int,
        isSearchActive: Bool
    ) -> CGFloat {
        let spacing = panelSpacingConstants()
        let regularColumnCount = effectiveColumnCount(configuredColumns: configuredColumns, itemCount: regularCount)
        let hasBothSections = fullscreenCount > 0 && regularCount > 0

        // Total columns across all sections
        let totalColumns = (fullscreenCount > 0 ? 1 : 0) + regularColumnCount
        guard totalColumns > 0 else { return SCPreferences.defaultCardWidth }

        // Available width after padding, section spacing, and divider
        var availableWidth = screenSize.width - spacing.horizontalPadding * 2
        if hasBothSections {
            availableWidth -= spacing.sectionSpacing * 2 + spacing.dividerWidth
        }
        // Horizontal spacing between columns within the regular section
        let regularInternalSpacing = CGFloat(max(0, regularColumnCount - 1)) * spacing.horizontalSpacing
        availableWidth -= regularInternalSpacing

        let widthDerived = availableWidth / CGFloat(totalColumns)

        // Available height after padding
        let searchInset: CGFloat = isSearchActive ? (searchPillHeight + searchToGridSpacing) : 0
        let availableHeight = screenSize.height - spacing.verticalPadding * 2 - searchInset
        let regularRowCount = regularCount > 0 ? Int(ceil(Double(regularCount) / Double(max(1, regularColumnCount)))) : 0
        let maxRows = max(fullscreenCount, regularRowCount)
        guard maxRows > 0 else { return SCPreferences.defaultCardWidth }

        let verticalInternalSpacing = CGFloat(max(0, maxRows - 1)) * spacing.verticalSpacing
        let availableRowHeight = (availableHeight - verticalInternalSpacing) / CGFloat(maxRows)

        // Card height = previewHeight + cardNonPreviewHeight
        // previewHeight = (cardWidth - 2*inset) / aspectRatio
        // So: availableRowHeight = (cardWidth - 2*inset) / aspectRatio + nonPreviewHeight
        // Solving for cardWidth:
        let safeRatio = max(screenAspectRatio, 0.5)
        let heightDerived = (availableRowHeight - SCPreferences.cardNonPreviewHeight) * safeRatio + SCPreferences.previewInset * 2

        let result = min(widthDerived, heightDerived)
        return max(result, SCPreferences.minimumCardWidth)
    }

    nonisolated static func effectiveColumnCount(configuredColumns: Int, itemCount: Int) -> Int {
        let normalizedConfiguredColumns = max(1, configuredColumns)
        guard itemCount > 0 else {
            return 1
        }
        return min(normalizedConfiguredColumns, itemCount)
    }

    nonisolated static func gridContentSize(
        itemCount: Int,
        columnCount: Int,
        cardSize: CGSize,
        metrics: GridLayoutMetrics
    ) -> CGSize {
        guard itemCount > 0 else {
            return CGSize(
                width: metrics.horizontalPadding * 2,
                height: metrics.verticalPadding * 2
            )
        }

        let normalizedColumnCount = max(1, columnCount)
        let rowCount = Int(ceil(Double(itemCount) / Double(normalizedColumnCount)))

        let width = (CGFloat(normalizedColumnCount) * cardSize.width)
            + (CGFloat(normalizedColumnCount - 1) * metrics.horizontalSpacing)
            + (metrics.horizontalPadding * 2)
        let height = (CGFloat(rowCount) * cardSize.height)
            + (CGFloat(max(0, rowCount - 1)) * metrics.verticalSpacing)
            + (metrics.verticalPadding * 2)
        return CGSize(width: width, height: height)
    }

    nonisolated static func panelFrame(
        visibleFrame: CGRect,
        contentSize: CGSize
    ) -> CGRect {
        let panelWidth = min(max(contentSize.width, 1), visibleFrame.width)
        let panelHeight = min(max(contentSize.height, 1), visibleFrame.height)
        let origin = CGPoint(
            x: visibleFrame.midX - panelWidth / 2,
            y: visibleFrame.midY - panelHeight / 2
        )
        return CGRect(origin: origin, size: CGSize(width: panelWidth, height: panelHeight))
    }

    static func snapshotSignature(for snapshot: SpacesSnapshot) -> DesktopSnapshotSignature {
        DesktopSnapshotSignature(
            currentSpaceIndex: snapshot.currentSpaceIndex,
            fullscreenSpaces: snapshot.fullscreenSpaces.map { space in
                DesktopFullscreenSignature(
                    spaceID: space.spaceId,
                    rawSpaceIndex: space.rawSpaceIndex,
                    title: space.title,
                    subtitle: space.subtitle,
                    bundleIDs: space.bundleIDs,
                    layoutWindows: space.layoutSnapshot?.windows ?? [],
                    isCurrent: space.isCurrent,
                    isVisible: space.isVisible,
                    screenUUID: space.screenUUID
                )
            },
            spaces: snapshot.spaces.map { space in
                DesktopSpaceSignature(
                    spaceIndex: space.spaceIndex,
                    title: space.title,
                    subtitle: space.subtitle,
                    bundleIDs: space.bundleIDs,
                    layoutWindows: space.layoutSnapshot?.windows ?? [],
                    isCurrent: space.isCurrent,
                    isVisible: space.isVisible,
                    screenUUID: space.screenUUID
                )
            }
        )
    }

    static func entryByApplyingOptimisticTitle(
        _ entry: DesktopEntry,
        spaceIndex: Int,
        title: String
    ) -> DesktopEntry {
        guard case .regular(let desktop) = entry,
              desktop.spaceIndex == spaceIndex else {
            return entry
        }

        let renamedDesktop = SpaceSnapshotItem(
            spaceIndex: desktop.spaceIndex,
            spaceId: desktop.spaceId,
            title: title,
            subtitle: desktop.subtitle,
            bundleIDs: desktop.bundleIDs,
            layoutSnapshot: desktop.layoutSnapshot,
            isCurrent: desktop.isCurrent,
            isVisible: desktop.isVisible,
            screenUUID: desktop.screenUUID
        )
        return .regular(renamedDesktop)
    }

}
