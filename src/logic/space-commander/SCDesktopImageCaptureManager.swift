import Cocoa

@MainActor
class SCDesktopImageCaptureManager {
    private var cache = [CGSSpaceID: CGImage]()
    private let maxWidth: CGFloat = 1360
    private var lastCaptureTime: TimeInterval = 0
    private let captureMinInterval: TimeInterval = 1.0
    private var captureInFlight = false

    func captureVisibleSpaces(excludingWindowNumbers: [Int] = []) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= captureMinInterval else { return }
        guard !captureInFlight else { return }
        if #available(macOS 10.15, *) {
            guard CGPreflightScreenCaptureAccess() else {
                Logger.debug { "Screen capture permission not granted, skipping desktop image capture" }
                return
            }
        }
        lastCaptureTime = now
        captureInFlight = true

        var captureTargets = [(spaceID: CGSSpaceID, displayID: CGDirectDisplayID, bounds: CGRect)]()
        for (screenUUID, spaceIDs) in Spaces.screenSpacesMap {
            guard let screen = Screens.all[screenUUID],
                  let displayID = screen.number() else {
                continue
            }
            guard let visibleSpaceID = spaceIDs.first(where: { Spaces.visibleSpaces.contains($0) }) else {
                continue
            }
            captureTargets.append((visibleSpaceID, displayID, CGDisplayBounds(displayID)))
        }

        guard !captureTargets.isEmpty else {
            captureInFlight = false
            return
        }

        let excludedIDs = Set(excludingWindowNumbers.map { CGWindowID($0) })
        let maxW = maxWidth
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results = [(CGSSpaceID, CGImage)]()
            for target in captureTargets {
                let cgImage: CGImage?
                if excludedIDs.isEmpty {
                    cgImage = CGWindowListCreateImage(
                        target.bounds,
                        .optionOnScreenOnly,
                        kCGNullWindowID,
                        [.bestResolution]
                    )
                } else {
                    // Build a window list that excludes our panels
                    let allWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
                    let filteredIDs = allWindows.compactMap { info -> CGWindowID? in
                        guard let windowID = info[kCGWindowNumber] as? CGWindowID else { return nil }
                        return excludedIDs.contains(windowID) ? nil : windowID
                    }
                    cgImage = CGImage.windowListScreenshot(target.bounds, filteredIDs)
                }
                guard let cgImage else {
                    Logger.debug { "CGWindowListCreateImage returned nil for displayID=\(target.displayID)" }
                    continue
                }
                let scaled = Self.downscale(cgImage, maxWidth: maxW)
                results.append((target.spaceID, scaled))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (spaceID, image) in results {
                    self.cache[spaceID] = image
                }
                self.captureInFlight = false
            }
        }
    }

    func cachedImage(for spaceID: CGSSpaceID) -> CGImage? {
        cache[spaceID]
    }

    func pruneStaleEntries(currentSpaceIDs: Set<CGSSpaceID>) {
        for key in cache.keys where !currentSpaceIDs.contains(key) {
            cache.removeValue(forKey: key)
        }
    }

    func invalidateAll() {
        cache.removeAll()
    }

    private nonisolated static func downscale(_ image: CGImage, maxWidth: CGFloat) -> CGImage {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)
        guard originalWidth > maxWidth else { return image }
        let scale = maxWidth / originalWidth
        let newWidth = Int(originalWidth * scale)
        let newHeight = Int(originalHeight * scale)
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}

extension CGImage {
    static func windowListScreenshot(_ bounds: CGRect, _ windowIDs: [CGWindowID]) -> CGImage? {
        guard !windowIDs.isEmpty else { return nil }
        return CGImage(
            windowListFromArrayScreenBounds: bounds,
            windowArray: windowIDs as CFArray,
            imageOption: [.bestResolution]
        )
    }
}
