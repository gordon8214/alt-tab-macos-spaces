import Cocoa
import Carbon.HIToolbox
import QuartzCore

final class SCDesktopKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class SCDesktopDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class SCDesktopCardView: NSView {
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
        }
    }

    var isLifted = false {
        didSet {
            guard isLifted != oldValue else { return }
            needsDisplay = true
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 12
        layer?.backgroundColor = isSelected
            ? NSColor.systemAccentColor.withAlphaComponent(0.1).cgColor
            : NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = isSelected ? Appearance.highlightBorderWidth : 1
        layer?.borderColor = isSelected
            ? Appearance.highlightFocusedBorderColor.cgColor
            : NSColor.gridColor.cgColor
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(isLifted ? 0.45 : (isSelected ? 0.35 : 0.25))
        shadow.shadowBlurRadius = isLifted ? 11 : (isSelected ? 7 : 4)
        self.shadow = shadow
        layer?.zPosition = isLifted ? 10 : 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

final class SCDesktopLayoutPreviewView: NSView {
    var snapshot: StageLayoutSnapshot?
    var desktopImage: CGImage?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if let desktopImage {
            drawImagePreview(desktopImage)
            return
        }
        drawShapesPreview()
    }

    private func drawImagePreview(_ image: CGImage) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let cornerRadius: CGFloat = 9
        let clipPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(clipPath)
        context.clip()

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let imageAspect = imageWidth / imageHeight
        let boundsAspect = bounds.width / bounds.height

        let drawRect: CGRect
        if imageAspect > boundsAspect {
            let scaledWidth = bounds.width
            let scaledHeight = scaledWidth / imageAspect
            let yOffset = (bounds.height - scaledHeight) / 2
            drawRect = CGRect(x: 0, y: yOffset, width: scaledWidth, height: scaledHeight)
        } else {
            let scaledHeight = bounds.height
            let scaledWidth = scaledHeight * imageAspect
            let xOffset = (bounds.width - scaledWidth) / 2
            drawRect = CGRect(x: xOffset, y: 0, width: scaledWidth, height: scaledHeight)
        }

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: drawRect)
        context.restoreGState()

        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.gridColor.withAlphaComponent(0.45).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
    }

    private func drawShapesPreview() {
        let gradient = NSGradient(colors: [
            NSColor.windowBackgroundColor.withAlphaComponent(0.95),
            NSColor.controlBackgroundColor.withAlphaComponent(0.85)
        ])
        gradient?.draw(in: bounds, angle: 90)

        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        NSColor.gridColor.withAlphaComponent(0.45).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        guard let snapshot, !snapshot.windows.isEmpty else {
            let text = NSAttributedString(
                string: NSLocalizedString("No Layout", comment: ""),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
            return
        }

        let palette: [NSColor] = [
            NSColor.systemBlue.withAlphaComponent(0.36),
            NSColor.systemGreen.withAlphaComponent(0.34),
            NSColor.systemOrange.withAlphaComponent(0.34),
            NSColor.systemPink.withAlphaComponent(0.34),
            NSColor.systemTeal.withAlphaComponent(0.34)
        ]

        for (index, geometry) in snapshot.windows.prefix(10).enumerated() {
            let originX = CGFloat(geometry.normalizedX) * bounds.width
            let width = max(10, CGFloat(geometry.normalizedWidth) * bounds.width)
            let height = max(10, CGFloat(geometry.normalizedHeight) * bounds.height)
            let yFromBottom = CGFloat(geometry.normalizedY) * bounds.height
            let originY = bounds.height - yFromBottom - height

            let rect = CGRect(x: originX, y: originY, width: width, height: height)
                .intersection(bounds.insetBy(dx: 1, dy: 1))
            guard !rect.isNull, rect.width > 2, rect.height > 2 else {
                continue
            }

            let color = palette[index % palette.count]
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            color.setFill()
            path.fill()
            NSColor.gridColor.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

struct DesktopFullscreenSignature: Equatable {
    let spaceID: UInt64
    let rawSpaceIndex: Int
    let title: String
    let subtitle: String
    let bundleIDs: [String]
    let layoutWindows: [StageWindowGeometry]
    let isCurrent: Bool
    let isVisible: Bool
    let screenUUID: String
}

struct DesktopSpaceSignature: Equatable {
    let spaceIndex: Int
    let title: String
    let subtitle: String
    let bundleIDs: [String]
    let layoutWindows: [StageWindowGeometry]
    let isCurrent: Bool
    let isVisible: Bool
    let screenUUID: String
}

struct DesktopSnapshotSignature: Equatable {
    let currentSpaceIndex: Int
    let fullscreenSpaces: [DesktopFullscreenSignature]
    let spaces: [DesktopSpaceSignature]
}

@MainActor
class SCDesktopSwitcherController: NSObject {
    enum DesktopKind: Equatable {
        case regular
        case fullscreen
    }

    enum DesktopEntry: Equatable {
        case regular(SpaceSnapshotItem)
        case fullscreen(FullscreenSpaceSnapshotItem)

        var kind: DesktopKind {
            switch self {
            case .regular:
                return .regular
            case .fullscreen:
                return .fullscreen
            }
        }

        var spaceId: CGSSpaceID {
            switch self {
            case .regular(let desktop):
                return desktop.spaceId
            case .fullscreen(let desktop):
                return desktop.spaceId
            }
        }

        var stableID: String {
            switch self {
            case .regular(let desktop):
                return "regular:\(desktop.spaceIndex)"
            case .fullscreen(let desktop):
                return "fullscreen:\(desktop.spaceId)"
            }
        }

        var title: String {
            switch self {
            case .regular(let desktop):
                return desktop.title
            case .fullscreen(let desktop):
                return desktop.title
            }
        }

        var subtitle: String {
            switch self {
            case .regular(let desktop):
                return desktop.subtitle
            case .fullscreen(let desktop):
                return desktop.subtitle
            }
        }

        var bundleIDs: [String] {
            switch self {
            case .regular(let desktop):
                return desktop.bundleIDs
            case .fullscreen(let desktop):
                return desktop.bundleIDs
            }
        }

        var layoutSnapshot: StageLayoutSnapshot? {
            switch self {
            case .regular(let desktop):
                return desktop.layoutSnapshot
            case .fullscreen(let desktop):
                return desktop.layoutSnapshot
            }
        }

        var regularSpaceIndex: Int? {
            if case .regular(let desktop) = self {
                return desktop.spaceIndex
            }
            return nil
        }

        var fullscreenSpaceID: UInt64? {
            if case .fullscreen(let desktop) = self {
                return desktop.spaceId
            }
            return nil
        }

        var fullscreenScreenUUID: String? {
            if case .fullscreen(let desktop) = self {
                return desktop.screenUUID
            }
            return nil
        }
    }

    struct DragSession {
        let sourceIndex: Int
        var currentTargetIndex: Int
        let startPoint: CGPoint
        let pointerOffsetInCard: CGPoint
        let draggedItemID: String
        let draggedKind: DesktopKind
        let draggedRegularSpaceIndex: Int?
        let draggedFullscreenSpaceID: UInt64?
        var isActive: Bool
    }

    var snapshotProvider: (() -> SpacesSnapshot?)?
    var imageProvider: ((CGSSpaceID) -> CGImage?)?
    var onActivateDesktop: ((Int) -> Void)?
    var onActivateFullscreenDesktop: ((UInt64, String) -> Void)?
    var onRenameDesktop: ((Int, String?) -> Void)?
    var onReorderDesktops: ((Int, Int) -> Void)?
    var onReorderFullscreenDesktops: ((UInt64, Int) -> Void)?

    var panel: SCDesktopKeyablePanel?
    var scrollView: NSScrollView?
    var documentView: SCDesktopDocumentView?
    var allEntries: [DesktopEntry] = []
    var entries: [DesktopEntry] = []
    var searchQuery = ""
    var selectedIndex = 0
    var fullscreenVisibleCount = 0
    var regularVisibleCount = 0
    var isSearchActive: Bool {
        !searchQuery.isEmpty
    }

    var cardViewsByDesktopID: [String: SCDesktopCardView] = [:]
    var titleLabelsByDesktopID: [String: NSTextField] = [:]
    var searchQueryPillView: NSView?
    var searchQueryLabel: NSTextField?
    var noResultsLabel: NSTextField?
    var baseCardFrames: [CGRect] = []
    var displayOrder: [Int] = []

    var renameField: NSTextField?
    var renamingSpaceIndex: Int?
    weak var renamingTitleLabel: NSTextField?

    var lastShowUptime: TimeInterval = 0
    let duplicateToggleSuppressionInterval: TimeInterval = 0.15

    var localKeyMonitor: Any?
    var localMouseDownMonitor: Any?
    var localMouseDraggedMonitor: Any?
    var localMouseUpMonitor: Any?
    var globalMouseDownMonitor: Any?

    var dragSession: DragSession?

    var iconCache = NSCache<NSString, NSImage>()
    var lastSnapshotSignature: DesktopSnapshotSignature?
    var deferredSnapshotAfterDrag: SpacesSnapshot?
    var deferredSnapshotSignatureAfterDrag: DesktopSnapshotSignature?
    var coalescedRefreshWorkItem: DispatchWorkItem?
    let refreshCoalescingInterval: TimeInterval = 0.12
    let dragActivationDistance: CGFloat = 6
    let dragReflowAnimationDuration: TimeInterval = 0.14
    let dragLiftAnimationDuration: TimeInterval = 0.12
    let panelCornerRadius: CGFloat = 16
    let searchPillHeight: CGFloat = 24
    let searchToGridSpacing: CGFloat = 10
    let minimumEmptyStateWidth: CGFloat = 320
    let minimumEmptyStateHeight: CGFloat = 160

}
