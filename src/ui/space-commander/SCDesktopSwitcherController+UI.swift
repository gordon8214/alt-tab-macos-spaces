import Cocoa

@MainActor
extension SCDesktopSwitcherController {
    struct PanelLayout {
        let panelFrame: NSRect
        let contentSize: CGSize
        let cardWidth: CGFloat
        let previewStyle: DesktopPreviewStyle
        let cardSize: CGSize
        let previewHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let sectionSpacing: CGFloat
        let dividerWidth: CGFloat
        let gridTopInset: CGFloat
        let regularColumnCount: Int
        let fullscreenSectionHeight: CGFloat
        let regularSectionHeight: CGFloat
        let hasBothSections: Bool
    }

    struct PanelSetup {
        let panel: SCDesktopKeyablePanel
        let scrollView: NSScrollView
        let needsNewPanel: Bool
    }

    struct PanelSectionOrigins {
        let fullscreen: CGFloat
        let regular: CGFloat
    }

    struct PanelSectionSlots {
        var fullscreen = 0
        var regular = 0
    }

    struct PanelSpacing {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let sectionSpacing: CGFloat
        let dividerWidth: CGFloat
        let gridTopInset: CGFloat
    }

    struct PanelSections {
        let regularColumnCount: Int
        let fullscreenSectionWidth: CGFloat
        let regularSectionWidth: CGFloat
        let fullscreenSectionHeight: CGFloat
        let regularSectionHeight: CGFloat
        let hasBothSections: Bool
    }

    struct PanelWidthContext {
        let horizontalPadding: CGFloat
        let fullscreenSectionWidth: CGFloat
        let regularSectionWidth: CGFloat
        let hasBothSections: Bool
        let sectionSpacing: CGFloat
        let dividerWidth: CGFloat
    }

    func buildPanel() {
        resetPanelTransientState()
        guard let screen = preferredScreen() else { return }

        let cardWidth = Self.resolvedCardWidth(
            screenSize: screen.visibleFrame.size,
            screenAspectRatio: screen.ratio(),
            fullscreenCount: fullscreenVisibleCount,
            regularCount: regularVisibleCount,
            configuredColumns: SCPreferences.loadDesktopColumns(),
            isSearchActive: isSearchActive
        )
        let layout = panelLayout(for: screen, cardWidth: cardWidth, screenAspectRatio: screen.ratio())
        guard let panelSetup = preparePanel(layout: layout) else { return }

        let docView = SCDesktopDocumentView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: max(layout.contentSize.width, layout.panelFrame.width),
                height: layout.contentSize.height
            )
        )
        panelSetup.scrollView.documentView = docView

        if isSearchActive {
            addSearchQueryPill(
                in: docView,
                horizontalPadding: layout.horizontalPadding,
                verticalPadding: layout.verticalPadding,
                contentWidth: layout.contentSize.width
            )
        }

        if entries.isEmpty {
            addNoResultsLabel(
                in: docView,
                horizontalPadding: layout.horizontalPadding,
                verticalPadding: layout.verticalPadding,
                contentSize: layout.contentSize,
                gridTopInset: layout.gridTopInset
            )
        } else {
            renderEntries(in: docView, layout: layout)
        }

        applyPreviewLayout(order: displayOrder, animated: false)
        if panelSetup.needsNewPanel {
            NSApp.activate(ignoringOtherApps: true)
            panelSetup.panel.makeKeyAndOrderFront(nil)
            panelSetup.panel.orderFrontRegardless()
        } else {
            panelSetup.panel.orderFrontRegardless()
        }
        documentView = docView
    }

    func resetPanelTransientState() {
        cardViewsByDesktopID = [:]
        titleLabelsByDesktopID = [:]
        searchQueryPillView = nil
        searchQueryLabel = nil
        noResultsLabel = nil
        baseCardFrames = []
        displayOrder = Array(entries.indices)
    }

    func panelLayout(for screen: NSScreen, cardWidth: CGFloat, screenAspectRatio: CGFloat) -> PanelLayout {
        let cardSize = SCPreferences.cardSize(forCardWidth: cardWidth, screenAspectRatio: screenAspectRatio)
        let previewHeight = SCPreferences.previewHeight(forCardWidth: cardWidth, screenAspectRatio: screenAspectRatio)
        let spacing = panelSpacing()
        let regularColumnCount = Self.effectiveColumnCount(
            configuredColumns: SCPreferences.loadDesktopColumns(),
            itemCount: regularVisibleCount
        )
        let sections = panelSections(
            cardSize: cardSize,
            regularColumnCount: regularColumnCount,
            spacing: spacing
        )
        let widthContext = PanelWidthContext(
            horizontalPadding: spacing.horizontalPadding,
            fullscreenSectionWidth: sections.fullscreenSectionWidth,
            regularSectionWidth: sections.regularSectionWidth,
            hasBothSections: sections.hasBothSections,
            sectionSpacing: spacing.sectionSpacing,
            dividerWidth: spacing.dividerWidth
        )
        let rawContentSize = CGSize(
            width: contentWidth(widthContext),
            height: (spacing.verticalPadding * 2) + spacing.gridTopInset
                + max(sections.fullscreenSectionHeight, sections.regularSectionHeight)
        )
        let contentSize = resolvedContentSize(rawContentSize: rawContentSize, gridTopInset: spacing.gridTopInset)
        let panelFrame = Self.panelFrame(visibleFrame: screen.visibleFrame, contentSize: contentSize)

        return PanelLayout(
            panelFrame: panelFrame,
            contentSize: contentSize,
            cardWidth: cardWidth,
            previewStyle: SCPreferences.loadDesktopPreviewStyle(),
            cardSize: cardSize,
            previewHeight: previewHeight,
            horizontalPadding: spacing.horizontalPadding,
            verticalPadding: spacing.verticalPadding,
            horizontalSpacing: spacing.horizontalSpacing,
            verticalSpacing: spacing.verticalSpacing,
            sectionSpacing: spacing.sectionSpacing,
            dividerWidth: spacing.dividerWidth,
            gridTopInset: spacing.gridTopInset,
            regularColumnCount: sections.regularColumnCount,
            fullscreenSectionHeight: sections.fullscreenSectionHeight,
            regularSectionHeight: sections.regularSectionHeight,
            hasBothSections: sections.hasBothSections
        )
    }

    func panelSpacing() -> PanelSpacing {
        let constants = Self.panelSpacingConstants()
        return PanelSpacing(
            horizontalPadding: constants.horizontalPadding,
            verticalPadding: constants.verticalPadding,
            horizontalSpacing: constants.horizontalSpacing,
            verticalSpacing: constants.verticalSpacing,
            sectionSpacing: constants.sectionSpacing,
            dividerWidth: constants.dividerWidth,
            gridTopInset: isSearchActive ? (Self.searchPillHeight + Self.searchToGridSpacing) : 0
        )
    }

    func panelSections(
        cardSize: CGSize,
        regularColumnCount: Int,
        spacing: PanelSpacing
    ) -> PanelSections {
        let regularRowCount = regularRowCount(regularColumnCount: regularColumnCount)
        let fullscreenSectionWidth = fullscreenVisibleCount > 0 ? cardSize.width : 0
        let regularSectionWidth = regularSectionWidth(
            cardSize: cardSize,
            regularColumnCount: regularColumnCount,
            horizontalSpacing: spacing.horizontalSpacing
        )
        let hasBothSections = fullscreenVisibleCount > 0 && regularVisibleCount > 0
        let fullscreenSectionHeight = sectionHeight(
            rowCount: fullscreenVisibleCount,
            cardHeight: cardSize.height,
            verticalSpacing: spacing.verticalSpacing
        )
        let regularSectionHeight = sectionHeight(
            rowCount: regularRowCount,
            cardHeight: cardSize.height,
            verticalSpacing: spacing.verticalSpacing
        )
        return PanelSections(
            regularColumnCount: regularColumnCount,
            fullscreenSectionWidth: fullscreenSectionWidth,
            regularSectionWidth: regularSectionWidth,
            fullscreenSectionHeight: fullscreenSectionHeight,
            regularSectionHeight: regularSectionHeight,
            hasBothSections: hasBothSections
        )
    }

    func regularRowCount(regularColumnCount: Int) -> Int {
        guard regularVisibleCount > 0 else {
            return 0
        }
        return Int(ceil(Double(regularVisibleCount) / Double(max(1, regularColumnCount))))
    }

    func regularSectionWidth(
        cardSize: CGSize,
        regularColumnCount: Int,
        horizontalSpacing: CGFloat
    ) -> CGFloat {
        guard regularVisibleCount > 0 else {
            return 0
        }
        return (CGFloat(regularColumnCount) * cardSize.width)
            + (CGFloat(max(0, regularColumnCount - 1)) * horizontalSpacing)
    }

    func contentWidth(_ context: PanelWidthContext) -> CGFloat {
        var width = (context.horizontalPadding * 2)
            + context.fullscreenSectionWidth
            + context.regularSectionWidth
        if context.hasBothSections {
            width += (context.sectionSpacing * 2) + context.dividerWidth
        }
        return width
    }

    func sectionHeight(rowCount: Int, cardHeight: CGFloat, verticalSpacing: CGFloat) -> CGFloat {
        guard rowCount > 0 else {
            return 0
        }
        return (CGFloat(rowCount) * cardHeight)
            + (CGFloat(max(0, rowCount - 1)) * verticalSpacing)
    }

    func resolvedContentSize(rawContentSize: CGSize, gridTopInset: CGFloat) -> CGSize {
        var contentSize = rawContentSize
        if isSearchActive || entries.isEmpty {
            contentSize.width = max(contentSize.width, minimumEmptyStateWidth)
        }
        if entries.isEmpty {
            contentSize.height = max(contentSize.height, minimumEmptyStateHeight + gridTopInset)
        }
        return contentSize
    }

    func preparePanel(layout: PanelLayout) -> PanelSetup? {
        let needsNewPanel = panel == nil || !(panel?.contentView is NSVisualEffectView)
        if needsNewPanel {
            return createPanel(layout: layout)
        }

        guard let panel,
              let effectView = panel.contentView as? NSVisualEffectView else {
            return nil
        }
        panel.setFrame(layout.panelFrame, display: true, animate: false)
        panel.animationBehavior = .none

        if scrollView == nil {
            let rebuiltScrollView = NSScrollView(frame: effectView.bounds)
            rebuiltScrollView.drawsBackground = false
            rebuiltScrollView.borderType = .noBorder
            rebuiltScrollView.autohidesScrollers = true
            rebuiltScrollView.autoresizingMask = [.width, .height]
            effectView.addSubview(rebuiltScrollView)
            self.scrollView = rebuiltScrollView
        }
        guard let scrollView else { return nil }
        scrollView.frame = effectView.bounds
        scrollView.hasVerticalScroller = layout.contentSize.height > layout.panelFrame.height
        return PanelSetup(panel: panel, scrollView: scrollView, needsNewPanel: false)
    }

    func createPanel(layout: PanelLayout) -> PanelSetup {
        savePanelFrame()
        panel?.orderOut(nil)
        let panel = SCDesktopKeyablePanel(
            contentRect: layout.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.setAccessibilityRole(.popover)
        panel.setAccessibilityLabel(NSLocalizedString("Desktop Switcher", comment: ""))

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: layout.panelFrame.size))
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = panelCornerRadius
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]

        let scrollView = NSScrollView(frame: effectView.bounds)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = layout.contentSize.height > layout.panelFrame.height
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        effectView.addSubview(scrollView)
        panel.contentView = effectView

        self.panel = panel
        self.scrollView = scrollView
        return PanelSetup(panel: panel, scrollView: scrollView, needsNewPanel: true)
    }

    func renderEntries(in docView: SCDesktopDocumentView, layout: PanelLayout) {
        let origins = PanelSectionOrigins(
            fullscreen: layout.horizontalPadding,
            regular: layout.hasBothSections
            ? (layout.horizontalPadding + layout.cardSize.width + layout.sectionSpacing + layout.dividerWidth + layout.sectionSpacing)
            : layout.horizontalPadding
        )

        var slots = PanelSectionSlots()
        for desktop in entries {
            let frame = frameForDesktop(
                desktop,
                layout: layout,
                origins: origins,
                slots: &slots
            )
            let card = makeDesktopCard(for: desktop, frame: frame, previewHeight: layout.previewHeight, cardWidth: layout.cardWidth, previewStyle: layout.previewStyle)
            docView.addSubview(card)
            cardViewsByDesktopID[desktop.stableID] = card
            baseCardFrames.append(frame)
        }

        if layout.hasBothSections {
            let dividerHeight = max(layout.fullscreenSectionHeight, layout.regularSectionHeight)
            let dividerX = layout.horizontalPadding + layout.cardSize.width + layout.sectionSpacing
            let dividerFrame = CGRect(
                x: dividerX,
                y: layout.verticalPadding + layout.gridTopInset,
                width: layout.dividerWidth,
                height: dividerHeight
            )
            let dividerView = NSView(frame: dividerFrame)
            dividerView.wantsLayer = true
            dividerView.layer?.backgroundColor = NSColor.gridColor.withAlphaComponent(0.5).cgColor
            docView.addSubview(dividerView)
        }
    }

    func frameForDesktop(
        _ desktop: DesktopEntry,
        layout: PanelLayout,
        origins: PanelSectionOrigins,
        slots: inout PanelSectionSlots
    ) -> CGRect {
        let originX: CGFloat
        let originY: CGFloat
        switch desktop.kind {
        case .fullscreen:
            originX = origins.fullscreen
            originY = layout.verticalPadding + layout.gridTopInset + CGFloat(slots.fullscreen) * (layout.cardSize.height + layout.verticalSpacing)
            slots.fullscreen += 1

        case .regular:
            let row = slots.regular / max(1, layout.regularColumnCount)
            let column = slots.regular % max(1, layout.regularColumnCount)
            originX = origins.regular + CGFloat(column) * (layout.cardSize.width + layout.horizontalSpacing)
            originY = layout.verticalPadding + layout.gridTopInset + CGFloat(row) * (layout.cardSize.height + layout.verticalSpacing)
            slots.regular += 1
        }

        return CGRect(x: originX, y: originY, width: layout.cardSize.width, height: layout.cardSize.height)
    }
    func addSearchQueryPill(
        in documentView: NSView,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        contentWidth: CGFloat
    ) {
        let label = NSTextField(labelWithString: String(format: NSLocalizedString("Search: %@", comment: ""), searchQuery))
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        let availableWidth = max(80, contentWidth - (horizontalPadding * 2) - 22)
        let measured = label.attributedStringValue.boundingRect(
            with: NSSize(width: availableWidth, height: Self.searchPillHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let pillWidth = min(
            max(90, ceil(measured.width) + 22),
            max(90, contentWidth - (horizontalPadding * 2))
        )

        let pillFrame = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: pillWidth,
            height: Self.searchPillHeight
        )
        let pillView = NSView(frame: pillFrame)
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = Self.searchPillHeight / 2
        pillView.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.2).cgColor

        label.frame = CGRect(
            x: 11,
            y: (Self.searchPillHeight - 16) / 2,
            width: pillFrame.width - 22,
            height: 16
        )
        pillView.addSubview(label)

        documentView.addSubview(pillView)
        searchQueryPillView = pillView
        searchQueryLabel = label
    }

    func addNoResultsLabel(
        in documentView: NSView,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        contentSize: CGSize,
        gridTopInset: CGFloat
    ) {
        let label = NSTextField(labelWithString: NSLocalizedString("No desktops match", comment: ""))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = CGRect(
            x: horizontalPadding,
            y: max(
                verticalPadding + gridTopInset,
                (contentSize.height - 18) / 2
            ),
            width: contentSize.width - (horizontalPadding * 2),
            height: 18
        )
        documentView.addSubview(label)
        noResultsLabel = label
    }

    func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

}
