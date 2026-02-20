//
//  SCSpatialDesktopOverlayController.swift
//  alt-tab-macos
//

import Cocoa

private final class SCSpatialOverlayFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SCSpatialOverlayCellView: NSView {
    enum Role {
        case normal
        case source
        case target
    }

    var role: Role = .normal {
        didSet {
            guard role != oldValue else { return }
            updateAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        guard let layer else { return }
        switch role {
        case .normal:
            layer.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.28).cgColor
            layer.borderColor = NSColor.gridColor.withAlphaComponent(0.45).cgColor
            layer.borderWidth = 1
        case .source:
            layer.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.45).cgColor
            layer.borderColor = NSColor.selectedControlColor.withAlphaComponent(0.85).cgColor
            layer.borderWidth = 1.8
        case .target:
            layer.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.85).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer.borderWidth = 2.2
        }
    }
}

@MainActor
final class SCSpatialDesktopOverlayController {
    private var panel: NSPanel?
    private var contentView: SCSpatialOverlayFlippedView?
    private var dismissWorkItem: DispatchWorkItem?
    private var sourceCell: SCSpatialOverlayCellView?
    private var targetCell: SCSpatialOverlayCellView?
    private var activePresentationToken: UInt64 = 0

    private let panelSize = CGSize(width: 300, height: 225)
    private let horizontalContentInset: CGFloat = 18
    private let verticalContentInset: CGFloat = 10

    nonisolated static func shouldApplyPresentationAction(
        token: UInt64,
        activeToken: UInt64
    ) -> Bool {
        token == activeToken
    }

    func show(
        entries: [SCDesktopSwitcherController.DesktopEntry],
        frames: [CGRect],
        sourceIndex: Int,
        targetIndex: Int?
    ) {
        guard entries.count == frames.count,
              entries.indices.contains(sourceIndex) else {
            return
        }

        let presentationToken = beginPresentation()
        rebuildPanel()
        guard let contentView else { return }

        let framesWithGap = framesByAddingSectionGap(entries: entries, frames: frames)
        let renderedFrames = normalizedFrames(framesWithGap, in: contentView.bounds)
        guard renderedFrames.count == entries.count else {
            return
        }

        sourceCell = nil
        targetCell = nil

        for (index, frame) in renderedFrames.enumerated() {
            let cell = SCSpatialOverlayCellView(frame: frame)
            contentView.addSubview(cell)
            if index == sourceIndex {
                sourceCell = cell
            }
            if index == targetIndex {
                targetCell = cell
            }
        }

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        sourceCell?.role = .source

        if targetIndex != nil, targetCell != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self,
                      Self.shouldApplyPresentationAction(
                        token: presentationToken,
                        activeToken: self.activePresentationToken
                      ) else {
                    return
                }
                self.targetCell?.role = .target
            }
            scheduleDismiss(after: 0.64, token: presentationToken)
        } else {
            pulseSourceCell()
            scheduleDismiss(after: 0.26, token: presentationToken)
        }
    }

    func showUnavailableAttempt() {
        let presentationToken = beginPresentation()
        rebuildPanel()
        guard let contentView else { return }

        sourceCell = nil
        targetCell = nil

        let sourceFrame = centeredAttemptCellFrame(in: contentView.bounds)
        let source = SCSpatialOverlayCellView(frame: sourceFrame)
        source.role = .source
        contentView.addSubview(source)
        sourceCell = source

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        pulseSourceCell()
        scheduleDismiss(after: 0.26, token: presentationToken)
    }

    func dismiss() {
        activePresentationToken &+= 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        clearPanel()
    }

    func cleanup() {
        dismiss()
    }

    private func beginPresentation() -> UInt64 {
        activePresentationToken &+= 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        return activePresentationToken
    }

    private func clearPanel() {
        panel?.orderOut(nil)
        panel = nil
        contentView = nil
        sourceCell = nil
        targetCell = nil
    }

    private func rebuildPanel() {
        clearPanel()

        guard let screen = preferredScreen() else { return }
        let frame = NSRect(
            x: screen.visibleFrame.midX - panelSize.width / 2,
            y: screen.visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.setAccessibilityRole(.popover)
        panel.setAccessibilityLabel(NSLocalizedString("Spatial Desktop Overlay", comment: ""))

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .dark
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]

        let contentFrame = effectView.bounds.insetBy(dx: horizontalContentInset, dy: verticalContentInset)
        let contentView = SCSpatialOverlayFlippedView(frame: contentFrame)
        contentView.autoresizingMask = [.width, .height]
        effectView.addSubview(contentView)

        panel.contentView = effectView

        self.panel = panel
        self.contentView = contentView
    }

    private func pulseSourceCell() {
        guard let sourceLayer = sourceCell?.layer else { return }

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.08
        pulse.duration = 0.08
        pulse.autoreverses = true
        pulse.repeatCount = 1
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sourceLayer.add(pulse, forKey: "spatialPulse")
    }

    private func scheduleDismiss(after delay: TimeInterval, token: UInt64) {
        dismissWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.animateDismiss(token: token)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func animateDismiss(token: UInt64) {
        guard Self.shouldApplyPresentationAction(token: token, activeToken: activePresentationToken),
              let panel else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  Self.shouldApplyPresentationAction(
                    token: token,
                    activeToken: self.activePresentationToken
                  ) else {
                return
            }
            self.dismiss()
        }
    }

    private func centeredAttemptCellFrame(in bounds: CGRect) -> CGRect {
        let width = max(20, bounds.width * 0.42)
        let height = max(16, bounds.height * 0.3)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

private extension SCSpatialDesktopOverlayController {
    func normalizedFrames(_ frames: [CGRect], in bounds: CGRect) -> [CGRect] {
        guard !frames.isEmpty else {
            return []
        }

        let union = frames.reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }

        guard !union.isNull,
              union.width > 0,
              union.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return []
        }

        let scale = min(bounds.width / union.width, bounds.height / union.height)
        let scaledWidth = union.width * scale
        let scaledHeight = union.height * scale
        let offsetX = bounds.minX + (bounds.width - scaledWidth) / 2
        let offsetY = bounds.minY + (bounds.height - scaledHeight) / 2

        return frames.map { frame in
            let normalizedX = offsetX + ((frame.minX - union.minX) * scale)
            let normalizedY = offsetY + ((frame.minY - union.minY) * scale)
            let width = max(14, frame.width * scale)
            let height = max(14, frame.height * scale)
            return CGRect(x: normalizedX, y: normalizedY, width: width, height: height).integral
        }
    }

    func framesByAddingSectionGap(
        entries: [SCDesktopSwitcherController.DesktopEntry],
        frames: [CGRect]
    ) -> [CGRect] {
        guard entries.count == frames.count else {
            return frames
        }

        let fullscreenIndices = entries.indices.filter { entries[$0].kind == .fullscreen }
        let regularIndices = entries.indices.filter { entries[$0].kind == .regular }
        guard !fullscreenIndices.isEmpty, !regularIndices.isEmpty else {
            return frames
        }

        let fullscreenMaxX = fullscreenIndices.map { frames[$0].maxX }.max() ?? 0
        let regularMinX = regularIndices.map { frames[$0].minX }.min() ?? 0
        guard regularMinX > fullscreenMaxX else {
            return frames
        }

        let averageCardWidth = frames.map(\.width).reduce(0, +) / CGFloat(max(1, frames.count))
        let extraGap = max(averageCardWidth * 0.35, 1)

        var adjusted = frames
        for index in regularIndices {
            adjusted[index] = adjusted[index].offsetBy(dx: extraGap, dy: 0)
        }
        return adjusted
    }
}
