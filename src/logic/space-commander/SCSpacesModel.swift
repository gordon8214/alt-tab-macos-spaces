import CoreGraphics
import Foundation

struct StageWindowGeometry: Codable, Sendable, Equatable {
    let bundleID: String
    let normalizedX: Double
    let normalizedY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double
}

struct StageLayoutSnapshot: Codable, Sendable, Equatable {
    let windows: [StageWindowGeometry]
    let capturedAt: Date
}

struct SpaceSnapshotItem: Sendable, Equatable {
    let spaceIndex: Int
    let spaceId: UInt64
    let title: String
    let subtitle: String
    let bundleIDs: [String]
    let layoutSnapshot: StageLayoutSnapshot?
    let isCurrent: Bool
    let isVisible: Bool
    let screenUUID: String
}

struct FullscreenSpaceSnapshotItem: Sendable, Equatable {
    let spaceId: UInt64
    let rawSpaceIndex: Int
    let title: String
    let subtitle: String
    let bundleIDs: [String]
    let layoutSnapshot: StageLayoutSnapshot?
    let isCurrent: Bool
    let isVisible: Bool
    let screenUUID: String
}

struct SpacesSnapshot: Sendable, Equatable {
    let currentSpaceIndex: Int
    let spaces: [SpaceSnapshotItem]
    let fullscreenSpaces: [FullscreenSpaceSnapshotItem]
    let hasExpectedConfiguration: Bool
    let missingExpectedIndices: [Int]
    let capturedAt: Date

    var currentSpace: SpaceSnapshotItem? {
        spaces.first(where: { $0.spaceIndex == currentSpaceIndex })
    }

    var currentFullscreenSpace: FullscreenSpaceSnapshotItem? {
        fullscreenSpaces.first(where: \.isCurrent)
    }

    init(
        currentSpaceIndex: Int,
        spaces: [SpaceSnapshotItem],
        fullscreenSpaces: [FullscreenSpaceSnapshotItem] = [],
        hasExpectedConfiguration: Bool,
        missingExpectedIndices: [Int],
        capturedAt: Date
    ) {
        self.currentSpaceIndex = currentSpaceIndex
        self.spaces = spaces
        self.fullscreenSpaces = fullscreenSpaces
        self.hasExpectedConfiguration = hasExpectedConfiguration
        self.missingExpectedIndices = missingExpectedIndices
        self.capturedAt = capturedAt
    }
}

@MainActor
enum SCSpacesSnapshotBuilder {
    /// Build a SpacesSnapshot directly from AltTab's internal Spaces/Windows data.
    static func build(
        customNames: [Int: String],
        preferredOrder: [Int],
        fullscreenPreferredOrder: [UInt64]
    ) -> SpacesSnapshot {
        let allSpaces = Spaces.idsAndIndexes
        let currentSpaceId = Spaces.currentSpaceId
        let visibleSpaces = Spaces.visibleSpaces
        let fullscreenSpaceIds = Spaces.fullscreenSpaceIds
        let screenSpacesMap = Spaces.screenSpacesMap

        // Separate regular and fullscreen spaces
        let nonFullscreenSpaces = allSpaces.filter { !fullscreenSpaceIds.contains($0.0) }
        let fullscreenSpaces = allSpaces.filter { fullscreenSpaceIds.contains($0.0) }

        // Build normalized index for regular desktops
        var rawToNormalizedIndex: [Int: Int] = [:]
        var normalizedToRawIndex: [Int: Int] = [:]
        var normalizedToSpaceId: [Int: CGSSpaceID] = [:]
        var availableIndexes: [Int] = []

        for (offset, (spaceId, rawSpaceIndex)) in nonFullscreenSpaces.sorted(by: { $0.1 < $1.1 }).enumerated() {
            let normalizedSpaceIndex = offset + 1
            rawToNormalizedIndex[rawSpaceIndex] = normalizedSpaceIndex
            normalizedToRawIndex[normalizedSpaceIndex] = rawSpaceIndex
            normalizedToSpaceId[normalizedSpaceIndex] = spaceId
            availableIndexes.append(normalizedSpaceIndex)
        }

        let currentNormalizedIndex: Int
        if let rawIdx = allSpaces.first(where: { $0.0 == currentSpaceId })?.1,
           let normalized = rawToNormalizedIndex[rawIdx] {
            currentNormalizedIndex = normalized
        } else {
            currentNormalizedIndex = 0
        }

        // Build window-to-space mapping from Windows.list
        let windowsByNormalizedSpace = windowsBySpace(
            rawToNormalizedIndex: rawToNormalizedIndex,
            normalizedCurrentSpaceIndex: currentNormalizedIndex
        )
        let windowsByRawSpace = windowsByRawSpace(
            currentRawSpaceIndex: allSpaces.first(where: { $0.0 == currentSpaceId })?.1 ?? 0
        )

        let availableNormalizedIndexes = Set(availableIndexes)

        // Merge ordering
        let mergedOrder = SpacesSnapshotBuilder.mergedOrder(
            existingOrder: preferredOrder,
            availableIndexes: availableIndexes
        )

        // Build regular space snapshot items
        var regularItems: [SpaceSnapshotItem] = []
        for normalizedSpaceIndex in mergedOrder {
            guard let spaceId = normalizedToSpaceId[normalizedSpaceIndex] else { continue }
            let rawSpaceIndex = normalizedToRawIndex[normalizedSpaceIndex] ?? normalizedSpaceIndex
            let screenUUID = screenSpacesMap.first(where: { $0.value.contains(spaceId) })?.key as String? ?? ""
            let windowsInSpace = windowsByNormalizedSpace[normalizedSpaceIndex] ?? []

            let title = SpacesSnapshotBuilder.resolvedTitle(
                customNames: customNames,
                normalizedSpaceIndex: normalizedSpaceIndex,
                legacyRawSpaceIndex: rawSpaceIndex,
                availableNormalizedIndexes: availableNormalizedIndexes
            )

            let bundleIDs = uniqueBundleIDs(in: windowsInSpace)
            let subtitle = keyboardShortcutSubtitle(normalizedSpaceIndex)
            let layoutSnapshot = buildLayoutSnapshot(from: windowsInSpace)

            regularItems.append(SpaceSnapshotItem(
                spaceIndex: normalizedSpaceIndex,
                spaceId: spaceId,
                title: title,
                subtitle: subtitle,
                bundleIDs: bundleIDs,
                layoutSnapshot: layoutSnapshot,
                isCurrent: spaceId == currentSpaceId,
                isVisible: visibleSpaces.contains(spaceId),
                screenUUID: screenUUID
            ))
        }

        // Build fullscreen space snapshot items
        let mergedFullscreenOrder = SpacesSnapshotBuilder.mergedFullscreenOrder(
            existingOrder: fullscreenPreferredOrder,
            availableSpaceIDs: fullscreenSpaces.map { $0.0 }
        )
        let fullscreenShortcutModifierSymbols = SCPreferences.loadFullscreenShortcutModifiers().symbolString

        var fullscreenItems: [FullscreenSpaceSnapshotItem] = []
        for (offset, spaceId) in mergedFullscreenOrder.enumerated() {
            guard let entry = fullscreenSpaces.first(where: { $0.0 == spaceId }) else { continue }
            let rawSpaceIndex = entry.1
            let screenUUID = screenSpacesMap.first(where: { $0.value.contains(spaceId) })?.key as String? ?? ""
            let windowsInSpace = windowsByRawSpace[rawSpaceIndex] ?? []

            let bundleIDs = uniqueBundleIDs(in: windowsInSpace)
            let title = fullscreenTitle(windows: windowsInSpace, fallbackRawSpaceIndex: rawSpaceIndex)
            let subtitle = fullscreenKeyboardShortcutSubtitle(offset + 1, modifierSymbols: fullscreenShortcutModifierSymbols)
            let layoutSnapshot = buildLayoutSnapshot(from: windowsInSpace)

            fullscreenItems.append(FullscreenSpaceSnapshotItem(
                spaceId: spaceId,
                rawSpaceIndex: rawSpaceIndex,
                title: title,
                subtitle: subtitle,
                bundleIDs: bundleIDs,
                layoutSnapshot: layoutSnapshot,
                isCurrent: spaceId == currentSpaceId,
                isVisible: visibleSpaces.contains(spaceId),
                screenUUID: screenUUID
            ))
        }

        // Configuration validation
        let expectedDesktopCount = nonFullscreenSpaces.count
        let missingIndices = expectedDesktopCount < 9
            ? Array((expectedDesktopCount + 1)...9)
            : []
        let hasExpectedConfig = expectedDesktopCount <= 9

        return SpacesSnapshot(
            currentSpaceIndex: currentNormalizedIndex,
            spaces: regularItems,
            fullscreenSpaces: fullscreenItems,
            hasExpectedConfiguration: hasExpectedConfig,
            missingExpectedIndices: missingIndices,
            capturedAt: Date()
        )
    }

    private static func windowsBySpace(
        rawToNormalizedIndex: [Int: Int],
        normalizedCurrentSpaceIndex: Int
    ) -> [Int: [Window]] {
        var buckets: [Int: [Window]] = [:]
        for window in Windows.list {
            guard !window.isWindowlessApp else { continue }
            let targetSpaces: [Int]
            if window.isOnAllSpaces {
                targetSpaces = normalizedCurrentSpaceIndex > 0
                    ? [normalizedCurrentSpaceIndex]
                    : []
            } else if window.spaceIndexes.isEmpty {
                targetSpaces = []
            } else {
                var seen = Set<Int>()
                targetSpaces = window.spaceIndexes.compactMap { rawSpaceIndex in
                    guard let normalized = rawToNormalizedIndex[rawSpaceIndex],
                          seen.insert(normalized).inserted else {
                        return nil
                    }
                    return normalized
                }
            }
            for spaceIndex in targetSpaces {
                buckets[spaceIndex, default: []].append(window)
            }
        }
        return buckets
    }

    private static func windowsByRawSpace(
        currentRawSpaceIndex: Int
    ) -> [Int: [Window]] {
        var buckets: [Int: [Window]] = [:]
        for window in Windows.list {
            guard !window.isWindowlessApp else { continue }
            let targetSpaces: [Int]
            if window.spaceIndexes.isEmpty {
                targetSpaces = (window.isOnAllSpaces && currentRawSpaceIndex > 0)
                    ? [currentRawSpaceIndex]
                    : []
            } else {
                var seen = Set<Int>()
                targetSpaces = window.spaceIndexes.filter { seen.insert($0).inserted }
            }
            for spaceIndex in targetSpaces {
                buckets[spaceIndex, default: []].append(window)
            }
            if window.isOnAllSpaces,
               currentRawSpaceIndex > 0,
               !targetSpaces.contains(currentRawSpaceIndex) {
                buckets[currentRawSpaceIndex, default: []].append(window)
            }
        }
        return buckets
    }

    private static func uniqueBundleIDs(in windows: [Window]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for window in windows {
            guard let bundleID = window.application.bundleIdentifier,
                  !bundleID.isEmpty,
                  bundleID != App.bundleIdentifier,
                  seen.insert(bundleID).inserted else {
                continue
            }
            result.append(bundleID)
        }
        return result
    }

    private static func fullscreenTitle(
        windows: [Window],
        fallbackRawSpaceIndex: Int
    ) -> String {
        let labels = fullscreenLabels(windows: windows)
        guard let first = labels.first else {
            return String(format: NSLocalizedString("Fullscreen %d", comment: ""), fallbackRawSpaceIndex)
        }
        if labels.count == 1 { return first }
        if labels.count == 2 { return "\(first), \(labels[1])" }
        return "\(first), \(labels[1]) - \(labels.count - 2) others"
    }

    private static func fullscreenLabels(windows: [Window]) -> [String] {
        var titles = [String]()
        var seenTitles = Set<String>()
        var fallbackAppNames = [String]()
        var seenAppNames = Set<String>()
        for window in windows {
            guard let bundleID = window.application.bundleIdentifier,
                  !bundleID.isEmpty,
                  bundleID != App.bundleIdentifier else {
                continue
            }
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty, seenTitles.insert(title).inserted {
                titles.append(title)
            }
            let appName = window.application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !appName.isEmpty, seenAppNames.insert(appName).inserted {
                fallbackAppNames.append(appName)
            }
        }
        return titles.isEmpty ? fallbackAppNames : titles
    }

    private static func keyboardShortcutSubtitle(_ spaceIndex: Int) -> String {
        guard spaceIndex >= 1, spaceIndex <= 9 else { return "" }
        return "⌃\(spaceIndex)"
    }

    private static func fullscreenKeyboardShortcutSubtitle(_ spaceIndex: Int, modifierSymbols: String) -> String {
        guard spaceIndex >= 1, spaceIndex <= 9, !modifierSymbols.isEmpty else { return "" }
        return "\(modifierSymbols)\(spaceIndex)"
    }

    private static func buildLayoutSnapshot(from windows: [Window]) -> StageLayoutSnapshot? {
        let drawableWindows: [(String, CGRect)] = windows.compactMap { window in
            guard !window.isMinimized,
                  !window.isHidden,
                  let bundleID = window.application.bundleIdentifier,
                  !bundleID.isEmpty,
                  let position = window.position,
                  let size = window.size else {
                return nil
            }
            let rect = CGRect(origin: position, size: size)
            guard rect.width > 2, rect.height > 2 else { return nil }
            return (bundleID, rect)
        }
        guard !drawableWindows.isEmpty else { return nil }

        let bounds = drawableWindows.map(\.1).reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let normalizedWindows = drawableWindows.map { bundleID, frame in
            let normalizedX = clamp((frame.minX - bounds.minX) / bounds.width)
            let normalizedWidth = clamp(frame.width / bounds.width)
            let normalizedHeight = clamp(frame.height / bounds.height)
            let topNormalized = clamp((frame.minY - bounds.minY) / bounds.height)
            let normalizedY = clamp(1 - topNormalized - normalizedHeight)
            return StageWindowGeometry(
                bundleID: bundleID,
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                normalizedWidth: normalizedWidth,
                normalizedHeight: normalizedHeight
            )
        }

        return StageLayoutSnapshot(windows: normalizedWindows, capturedAt: Date())
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// Ordering helpers from SpacesModel+Ordering.swift
extension SpacesSnapshotBuilder {
    static func mergedOrder(existingOrder: [Int], availableIndexes: [Int]) -> [Int] {
        let availableSet = Set(availableIndexes)
        var seen = Set<Int>()
        var merged: [Int] = []
        for spaceIndex in existingOrder {
            guard availableSet.contains(spaceIndex), seen.insert(spaceIndex).inserted else { continue }
            merged.append(spaceIndex)
        }
        for spaceIndex in availableIndexes.sorted() {
            guard seen.insert(spaceIndex).inserted else { continue }
            merged.append(spaceIndex)
        }
        return merged
    }

    static func mergedFullscreenOrder(existingOrder: [UInt64], availableSpaceIDs: [UInt64]) -> [UInt64] {
        let availableSet = Set(availableSpaceIDs)
        var seen = Set<UInt64>()
        var merged: [UInt64] = []
        for spaceID in existingOrder {
            guard availableSet.contains(spaceID), seen.insert(spaceID).inserted else { continue }
            merged.append(spaceID)
        }
        for spaceID in availableSpaceIDs {
            guard seen.insert(spaceID).inserted else { continue }
            merged.append(spaceID)
        }
        return merged
    }

    static func resolvedTitle(
        customNames: [Int: String],
        normalizedSpaceIndex: Int,
        legacyRawSpaceIndex: Int,
        availableNormalizedIndexes: Set<Int>
    ) -> String {
        if let name = customNames[normalizedSpaceIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if legacyRawSpaceIndex != normalizedSpaceIndex,
           !availableNormalizedIndexes.contains(legacyRawSpaceIndex),
           let legacyName = customNames[legacyRawSpaceIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyName.isEmpty {
            return legacyName
        }
        return String(format: NSLocalizedString("Desktop %d", comment: ""), normalizedSpaceIndex)
    }
}

// Namespace for the ordering-only builder used by the model
private enum SpacesSnapshotBuilder {}
