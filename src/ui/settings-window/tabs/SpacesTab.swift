import Cocoa

class SpacesTab {
    private static var enabledToggle: NSButton?
    private static var desktopSwitcherModifierRecorder: ModifierRecorderControl?
    private static var desktopSwitcherKeyRecorder: SCKeyRecorderControl?
    private static var firstEmptySpaceModifierRecorder: ModifierRecorderControl?
    private static var firstEmptySpaceKeyRecorder: SCKeyRecorderControl?
    private static var fullscreenShortcutModifierRecorder: ModifierRecorderControl?
    private static var columnsTextField: NSTextField?
    private static var columnsStepper: NSStepper?
    private static var previewStyleDropdown: NSPopUpButton?
    private static var cardWidthSlider: NSSlider?
    private static var cardWidthLabel: NSTextField?
    private static var fullscreenModeCheckbox: NSButton?
    private static var indicatorStyleDropdown: NSPopUpButton?
    private static var showCustomTitleToggle: NSButton?
    private static var spatialModifierRecorder: ModifierRecorderControl?

    static func initTab() -> NSView {
        let enabledCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(enabledToggleChanged(_:)))
        enabledCheckbox.state = SCPreferences.loadEnabled() ? .on : .off
        enabledToggle = enabledCheckbox
        let enabledRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("Enable Space Commander", comment: ""),
            rightViews: [enabledCheckbox]
        )
        let desktopSwitcherCombo = SCPreferences.loadDesktopSwitcherShortcut()
        let dsMods = ModifierRecorderControl()
        dsMods.modifiers = desktopSwitcherCombo.modifiers
        dsMods.onModifiersChanged = { _ in saveDesktopSwitcherFromControls() }
        desktopSwitcherModifierRecorder = dsMods
        let dsKey = SCKeyRecorderControl()
        dsKey.keyCode = desktopSwitcherCombo.keyCode
        dsKey.onKeyChanged = { _ in saveDesktopSwitcherFromControls() }
        desktopSwitcherKeyRecorder = dsKey
        let dsStack = NSStackView(views: [dsMods, dsKey])
        dsStack.orientation = .horizontal
        dsStack.spacing = 8
        let desktopSwitcherRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("Desktop switcher", comment: ""),
            rightViews: [dsStack]
        )
        let firstEmptyCombo = SCPreferences.loadFirstEmptySpaceShortcut()
        let feMods = ModifierRecorderControl()
        feMods.modifiers = firstEmptyCombo.modifiers
        feMods.onModifiersChanged = { _ in saveFirstEmptySpaceFromControls() }
        firstEmptySpaceModifierRecorder = feMods
        let feKey = SCKeyRecorderControl()
        feKey.keyCode = firstEmptyCombo.keyCode
        feKey.onKeyChanged = { _ in saveFirstEmptySpaceFromControls() }
        firstEmptySpaceKeyRecorder = feKey
        let feStack = NSStackView(views: [feMods, feKey])
        feStack.orientation = .horizontal
        feStack.spacing = 8
        let firstEmptyRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("First empty space", comment: ""),
            rightViews: [feStack]
        )
        let fsModifiers = ModifierRecorderControl()
        fsModifiers.modifiers = SCPreferences.loadFullscreenShortcutModifiers()
        fsModifiers.onModifiersChanged = { _ in saveFullscreenShortcutModifiersFromControls() }
        fullscreenShortcutModifierRecorder = fsModifiers
        let fullscreenShortcutModifiersRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("Fullscreen shortcut modifiers", comment: ""),
            rightViews: [fsModifiers]
        )
        let columnsField = NSTextField()
        columnsField.integerValue = SCPreferences.loadDesktopColumns()
        columnsField.isEditable = true
        columnsField.isBordered = true
        columnsField.isBezeled = true
        columnsField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        columnsField.target = self
        columnsField.action = #selector(columnsFieldChanged(_:))
        columnsTextField = columnsField
        let stepper = NSStepper()
        stepper.minValue = Double(SCPreferences.minimumDesktopColumns)
        stepper.maxValue = Double(SCPreferences.maximumDesktopColumns)
        stepper.integerValue = SCPreferences.loadDesktopColumns()
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepperChanged(_:))
        columnsStepper = stepper
        let columnsStack = NSStackView(views: [columnsField, stepper])
        columnsStack.orientation = .horizontal
        columnsStack.spacing = 4
        let desktopsPerRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("Desktops per row", comment: ""),
            rightViews: [columnsStack]
        )
        let isFullscreen = SCPreferences.loadDesktopFullscreenMode()
        let currentWidth = SCPreferences.loadDesktopCardWidth()
        let slider = NSSlider(value: Double(currentWidth), minValue: Double(SCPreferences.minimumCardWidth), maxValue: Double(SCPreferences.maximumCardWidth), target: self, action: #selector(cardWidthSliderChanged(_:)))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        slider.isEnabled = !isFullscreen
        cardWidthSlider = slider
        let widthLabel = NSTextField(labelWithString: "\(Int(currentWidth))pt")
        widthLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        widthLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        cardWidthLabel = widthLabel
        let sliderStack = NSStackView(views: [slider, widthLabel])
        sliderStack.orientation = .horizontal
        sliderStack.spacing = 6
        let previewSize = TableGroupView.Row(
            leftTitle: NSLocalizedString("Card size", comment: ""),
            rightViews: [sliderStack]
        )
        let fullscreenCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(fullscreenModeChanged(_:)))
        fullscreenCheckbox.state = isFullscreen ? .on : .off
        fullscreenModeCheckbox = fullscreenCheckbox
        let fullscreenRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("Fullscreen mode", comment: ""),
            rightViews: [fullscreenCheckbox]
        )
        let styleDropdown = NSPopUpButton()
        for style in DesktopPreviewStyle.allCases {
            styleDropdown.addItem(withTitle: style.displayName)
        }
        styleDropdown.selectItem(at: SCPreferences.loadDesktopPreviewStyle().rawValue)
        styleDropdown.target = self
        styleDropdown.action = #selector(previewStyleChanged(_:))
        previewStyleDropdown = styleDropdown
        let previewStyle = TableGroupView.Row(
            leftTitle: NSLocalizedString("Preview style", comment: ""),
            rightViews: [styleDropdown]
        )
        let indicatorDropdown = NSPopUpButton()
        for style in MenuBarDesktopIndicatorStyle.allCases {
            indicatorDropdown.addItem(withTitle: style.displayName)
        }
        indicatorDropdown.selectItem(at: SCPreferences.loadMenuBarDesktopIndicatorStyle().rawValue)
        indicatorDropdown.target = self
        indicatorDropdown.action = #selector(indicatorStyleChanged(_:))
        indicatorStyleDropdown = indicatorDropdown
        let indicatorStyle = TableGroupView.Row(
            leftTitle: NSLocalizedString("Menu bar indicator", comment: ""),
            rightViews: [indicatorDropdown]
        )
        let showTitleToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(showCustomTitleChanged(_:)))
        showTitleToggle.state = SCPreferences.loadShowCustomDesktopTitleInMenuBar() ? .on : .off
        showCustomTitleToggle = showTitleToggle
        let showCustomTitle = TableGroupView.Row(
            leftTitle: NSLocalizedString("Show custom name in menu bar", comment: ""),
            rightViews: [showTitleToggle]
        )
        let recorder = ModifierRecorderControl()
        recorder.modifiers = SCPreferences.loadSpatialModifiers()
        recorder.onModifiersChanged = { newModifiers in
            SCPreferences.saveSpatialModifiers(newModifiers)
            reRegisterHotKeys()
        }
        spatialModifierRecorder = recorder
        let spatialModifiers = TableGroupView.Row(
            leftTitle: NSLocalizedString("Spatial navigation modifiers", comment: ""),
            rightViews: [recorder]
        )
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        table.addRow(enabledRow)
        table.addNewTable()
        table.addRow(desktopSwitcherRow)
        table.addRow(firstEmptyRow)
        table.addRow(fullscreenShortcutModifiersRow)
        table.addNewTable()
        table.addRow(desktopsPerRow)
        table.addRow(previewSize)
        table.addRow(fullscreenRow)
        table.addRow(previewStyle)
        table.addNewTable()
        table.addRow(indicatorStyle)
        table.addRow(showCustomTitle)
        table.addNewTable()
        table.addRow(spatialModifiers)
        return TableGroupSetView(originalViews: [table], bottomPadding: 0)
    }

    private static func saveDesktopSwitcherFromControls() {
        guard let modifiers = desktopSwitcherModifierRecorder?.modifiers,
              let keyCode = desktopSwitcherKeyRecorder?.keyCode else { return }
        SCPreferences.saveDesktopSwitcherShortcut(SCKeyCombo(keyCode: keyCode, modifiers: modifiers))
        reRegisterHotKeys()
    }

    private static func saveFirstEmptySpaceFromControls() {
        guard let modifiers = firstEmptySpaceModifierRecorder?.modifiers,
              let keyCode = firstEmptySpaceKeyRecorder?.keyCode else { return }
        SCPreferences.saveFirstEmptySpaceShortcut(SCKeyCombo(keyCode: keyCode, modifiers: modifiers))
        reRegisterHotKeys()
    }

    private static func saveFullscreenShortcutModifiersFromControls() {
        guard let modifiers = fullscreenShortcutModifierRecorder?.modifiers else { return }
        SCPreferences.saveFullscreenShortcutModifiers(modifiers)
        reRegisterHotKeys()
        DispatchQueue.main.async { SCCoordinator.shared?.refreshSpacesSnapshot() }
    }

    private static func reRegisterHotKeys() {
        DispatchQueue.main.async {
            SCCoordinator.shared?.hotKeyManager?.unregisterAll()
            SCCoordinator.shared?.hotKeyManager?.registerAll()
            if let fullscreenCount = SCCoordinator.shared?.latestSpacesSnapshot?.fullscreenSpaces.count {
                SCCoordinator.shared?.hotKeyManager?.updateFullscreenNumberedShortcuts(count: fullscreenCount)
            }
        }
    }

    @objc private static func enabledToggleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SCPreferences.saveEnabled(enabled)
        DispatchQueue.main.async {
            if enabled {
                if SCCoordinator.shared == nil {
                    SCCoordinator.shared = SCCoordinator()
                }
                SCCoordinator.shared?.start()
            } else {
                SCCoordinator.shared?.stop()
                SCCoordinator.shared = nil
            }
        }
    }

    @objc private static func columnsFieldChanged(_ sender: NSTextField) {
        let value = max(SCPreferences.minimumDesktopColumns, min(sender.integerValue, SCPreferences.maximumDesktopColumns))
        sender.integerValue = value
        columnsStepper?.integerValue = value
        SCPreferences.saveDesktopColumns(value)
    }

    @objc private static func stepperChanged(_ sender: NSStepper) {
        columnsTextField?.integerValue = sender.integerValue
        SCPreferences.saveDesktopColumns(sender.integerValue)
    }

    @objc private static func cardWidthSliderChanged(_ sender: NSSlider) {
        let width = CGFloat(sender.integerValue)
        cardWidthLabel?.stringValue = "\(Int(width))pt"
        SCPreferences.saveDesktopCardWidth(width)
    }

    @objc private static func fullscreenModeChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SCPreferences.saveDesktopFullscreenMode(enabled)
        cardWidthSlider?.isEnabled = !enabled
    }

    @objc private static func previewStyleChanged(_ sender: NSPopUpButton) {
        guard let style = DesktopPreviewStyle(rawValue: sender.indexOfSelectedItem) else { return }
        SCPreferences.saveDesktopPreviewStyle(style)
        DispatchQueue.main.async {
            if style == .images {
                SCCoordinator.shared?.imageCaptureManager?.captureVisibleSpaces()
            } else {
                SCCoordinator.shared?.imageCaptureManager?.invalidateAll()
            }
            SCCoordinator.shared?.refreshSpacesSnapshot()
        }
    }

    @objc private static func indicatorStyleChanged(_ sender: NSPopUpButton) {
        guard let style = MenuBarDesktopIndicatorStyle(rawValue: sender.indexOfSelectedItem) else { return }
        SCPreferences.saveMenuBarDesktopIndicatorStyle(style)
        DispatchQueue.main.async { SCCoordinator.shared?.statusBarController?.refreshAppearance() }
    }

    @objc private static func showCustomTitleChanged(_ sender: NSButton) {
        SCPreferences.saveShowCustomDesktopTitleInMenuBar(sender.state == .on)
        DispatchQueue.main.async { SCCoordinator.shared?.statusBarController?.refreshAppearance() }
    }
}
