import Cocoa
import QuartzCore

@MainActor
extension SCDesktopSwitcherController {
    func makeDesktopCard(
        for desktop: DesktopEntry,
        frame: CGRect,
        previewHeight: CGFloat,
        previewSize: DesktopPreviewSize,
        previewStyle: DesktopPreviewStyle
    ) -> SCDesktopCardView {
        let card = SCDesktopCardView(frame: frame)
        card.setAccessibilityRole(.button)
        card.setAccessibilityLabel("\(desktop.title) \(desktop.subtitle)")

        let inset = DesktopPreviewSize.previewInset
        let previewFrame = CGRect(x: inset, y: inset, width: frame.width - inset * 2, height: previewHeight)
        let previewView = SCDesktopLayoutPreviewView(frame: previewFrame)
        previewView.snapshot = desktop.layoutSnapshot
        if previewStyle == .images {
            previewView.desktopImage = imageProvider?(desktop.spaceId)
        }
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 9
        previewView.layer?.masksToBounds = true
        card.addSubview(previewView)

        addPreviewIcons(to: card, desktop: desktop, previewFrame: previewFrame, previewSize: previewSize)
        addDesktopTitleLabels(to: card, desktop: desktop, frame: frame, previewFrame: previewFrame)
        return card
    }

    func addPreviewIcons(
        to card: SCDesktopCardView,
        desktop: DesktopEntry,
        previewFrame: CGRect,
        previewSize: DesktopPreviewSize
    ) {
        let iconSize: CGFloat = previewSize == .small ? 34 : 40
        let iconSpacing: CGFloat = 4
        let iconCornerRadius: CGFloat = previewSize == .small ? 8 : 10

        for (iconIndex, bundleID) in desktop.bundleIDs.prefix(4).enumerated() {
            let iconX = previewFrame.minX + 8 + CGFloat(iconIndex) * (iconSize + iconSpacing)
            let iconY = previewFrame.maxY - iconSize - 6
            let iconView = NSImageView(frame: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
            iconView.image = icon(for: bundleID, size: iconSize)
            iconView.wantsLayer = true
            iconView.layer?.cornerRadius = iconCornerRadius
            iconView.layer?.masksToBounds = true
            card.addSubview(iconView)
        }
    }

    func addDesktopTitleLabels(
        to card: SCDesktopCardView,
        desktop: DesktopEntry,
        frame: CGRect,
        previewFrame: CGRect
    ) {
        let titleY = previewFrame.maxY + 10
        let horizontalPadding: CGFloat = 14
        let gap: CGFloat = 6
        let availableWidth = frame.width - horizontalPadding * 2

        // Create subtitle first to measure its intrinsic width
        let subtitleLabel = NSTextField(labelWithString: desktop.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.sizeToFit()
        let subtitleWidth = subtitleLabel.frame.width
        subtitleLabel.frame = CGRect(
            x: frame.width - horizontalPadding - subtitleWidth,
            y: titleY,
            width: subtitleWidth,
            height: 20
        )
        card.addSubview(subtitleLabel)

        // Title takes remaining space, left-aligned
        let titleWidth = availableWidth - subtitleWidth - gap
        let titleLabel = NSTextField(labelWithString: desktop.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = CGRect(x: horizontalPadding, y: titleY, width: titleWidth, height: 20)
        card.addSubview(titleLabel)
        titleLabelsByDesktopID[desktop.stableID] = titleLabel
    }

    func updateSelection() {
        for (index, desktop) in entries.enumerated() {
            guard let card = cardViewsByDesktopID[desktop.stableID] else {
                continue
            }
            card.isSelected = index == selectedIndex
            card.setAccessibilitySelected(index == selectedIndex)
        }
    }

    func applyPreviewLayout(
        order: [Int],
        animated: Bool,
        preserveDraggedCardPosition: Bool = false
    ) {
        guard order.count == baseCardFrames.count else {
            return
        }

        displayOrder = order
        if animated {
            animatePreviewLayout(order: order, preserveDraggedCardPosition: preserveDraggedCardPosition)
        } else {
            applyPreviewFrames(order: order, preserveDraggedCardPosition: preserveDraggedCardPosition)
        }
    }

    func applyPreviewFrames(order: [Int], preserveDraggedCardPosition: Bool) {
        for (slotIndex, desktopIndex) in order.enumerated() {
            guard let card = cardForPreviewPosition(desktopIndex: desktopIndex, preserveDraggedCardPosition: preserveDraggedCardPosition) else {
                continue
            }
            card.frame = baseCardFrames[slotIndex]
        }
    }

    func animatePreviewLayout(order: [Int], preserveDraggedCardPosition: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = dragReflowAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (slotIndex, desktopIndex) in order.enumerated() {
                guard let card = self.cardForPreviewPosition(
                    desktopIndex: desktopIndex,
                    preserveDraggedCardPosition: preserveDraggedCardPosition
                ) else {
                    continue
                }
                card.animator().frame = self.baseCardFrames[slotIndex]
            }
        }
    }

    func cardForPreviewPosition(desktopIndex: Int, preserveDraggedCardPosition: Bool) -> SCDesktopCardView? {
        guard entries.indices.contains(desktopIndex) else {
            return nil
        }
        let desktop = entries[desktopIndex]
        guard let card = cardViewsByDesktopID[desktop.stableID] else {
            return nil
        }
        if preserveDraggedCardPosition,
           let dragSession,
           dragSession.isActive,
           dragSession.draggedItemID == desktop.stableID {
            return nil
        }
        return card
    }
}
