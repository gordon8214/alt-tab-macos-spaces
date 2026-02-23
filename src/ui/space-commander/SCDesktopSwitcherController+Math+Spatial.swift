import Cocoa

extension SCDesktopSwitcherController {
    nonisolated static func spatialMoveResolution(
        snapshot: SpacesSnapshot,
        direction: SpatialDirection,
        configuredRegularColumns: Int,
        cardWidth: CGFloat,
        screenAspectRatio: CGFloat
    ) -> SpatialMoveResolution? {
        let entries = spatialEntries(from: snapshot)
        guard !entries.isEmpty else {
            return nil
        }

        let cardSize = SCPreferences.cardSize(forCardWidth: cardWidth, screenAspectRatio: screenAspectRatio)
        let frames = spatialFrames(
            entries: entries,
            configuredRegularColumns: configuredRegularColumns,
            cardSize: cardSize
        )
        guard frames.count == entries.count else {
            return nil
        }

        let sourceIndex = spatialSourceIndex(entries: entries, snapshot: snapshot)
        let targetIndex = directionalMoveTargetIndex(
            currentIndex: sourceIndex,
            itemFrames: frames,
            direction: direction
        )
        return SpatialMoveResolution(
            entries: entries,
            frames: frames,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex
        )
    }

    private nonisolated static func spatialEntries(from snapshot: SpacesSnapshot) -> [DesktopEntry] {
        snapshot.fullscreenSpaces.map(DesktopEntry.fullscreen) + snapshot.spaces.map(DesktopEntry.regular)
    }

    private nonisolated static func spatialSourceIndex(entries: [DesktopEntry], snapshot: SpacesSnapshot) -> Int {
        guard !entries.isEmpty else {
            return 0
        }

        if let preferredStableID = preferredInitialDesktopStableID(snapshot: snapshot),
           let preferredIndex = entries.firstIndex(where: { $0.stableID == preferredStableID }) {
            return preferredIndex
        }

        return 0
    }

    private nonisolated static func spatialFrames(
        entries: [DesktopEntry],
        configuredRegularColumns: Int,
        cardSize: CGSize
    ) -> [CGRect] {
        let spacing = panelSpacingConstants()

        let fullscreenCount = entries.filter { $0.kind == .fullscreen }.count
        let regularCount = entries.count - fullscreenCount
        let regularColumnCount = effectiveColumnCount(
            configuredColumns: configuredRegularColumns,
            itemCount: regularCount
        )
        let hasBothSections = fullscreenCount > 0 && regularCount > 0
        let fullscreenOriginX = spacing.horizontalPadding
        let regularOriginX = hasBothSections
            ? (spacing.horizontalPadding + cardSize.width + spacing.sectionSpacing + spacing.dividerWidth + spacing.sectionSpacing)
            : spacing.horizontalPadding

        var fullscreenSlot = 0
        var regularSlot = 0
        var frames: [CGRect] = []
        frames.reserveCapacity(entries.count)

        for entry in entries {
            let originX: CGFloat
            let originY: CGFloat
            switch entry.kind {
            case .fullscreen:
                originX = fullscreenOriginX
                originY = spacing.verticalPadding + CGFloat(fullscreenSlot) * (cardSize.height + spacing.verticalSpacing)
                fullscreenSlot += 1

            case .regular:
                let row = regularSlot / max(1, regularColumnCount)
                let column = regularSlot % max(1, regularColumnCount)
                originX = regularOriginX + CGFloat(column) * (cardSize.width + spacing.horizontalSpacing)
                originY = spacing.verticalPadding + CGFloat(row) * (cardSize.height + spacing.verticalSpacing)
                regularSlot += 1
            }

            frames.append(CGRect(x: originX, y: originY, width: cardSize.width, height: cardSize.height))
        }

        return frames
    }

}
