import Cocoa

class SpacesTab {
    private static var enabledToggle: NSButton?
    private static var desktopSwitcherRecorder: SCShortcutRecorderControl?
    private static var firstEmptySpaceRecorder: SCShortcutRecorderControl?
    private static var columnsTextField: NSTextField?
    private static var columnsStepper: NSStepper?
    private static var previewSizeDropdown: NSPopUpButton?
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
        let desktopSwitcherRec = SCShortcutRecorderControl(keyCombo: SCPreferences.loadDesktopSwitcherShortcut())
        desktopSwitcherRec.onShortcutChanged = { combo in
            SCPreferences.saveDesktopSwitcherShortcut(combo)
            DispatchQueue.main.async {
                SCCoordinator.shared?.hotKeyManager?.unregisterAll()
                SCCoordinator.shared?.hotKeyManager?.registerAll()
            }
        }
        desktopSwitcherRecorder = desktopSwitcherRec
        let desktopSwitcherRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("Desktop switcher", comment: ""),
            rightViews: [desktopSwitcherRec]
        )
        let firstEmptyRec = SCShortcutRecorderControl(keyCombo: SCPreferences.loadFirstEmptySpaceShortcut())
        firstEmptyRec.onShortcutChanged = { combo in
            SCPreferences.saveFirstEmptySpaceShortcut(combo)
            DispatchQueue.main.async {
                SCCoordinator.shared?.hotKeyManager?.unregisterAll()
                SCCoordinator.shared?.hotKeyManager?.registerAll()
            }
        }
        firstEmptySpaceRecorder = firstEmptyRec
        let firstEmptyRow = TableGroupView.Row(
            leftTitle: NSLocalizedString("First empty space", comment: ""),
            rightViews: [firstEmptyRec]
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
        let previewDropdown = NSPopUpButton()
        for size in DesktopPreviewSize.allCases {
            previewDropdown.addItem(withTitle: size.displayName)
        }
        previewDropdown.selectItem(at: SCPreferences.loadDesktopPreviewSize().rawValue)
        previewDropdown.target = self
        previewDropdown.action = #selector(previewSizeChanged(_:))
        previewSizeDropdown = previewDropdown
        let previewSize = TableGroupView.Row(
            leftTitle: NSLocalizedString("Preview size", comment: ""),
            rightViews: [previewDropdown]
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
            DispatchQueue.main.async {
                SCCoordinator.shared?.hotKeyManager?.unregisterAll()
                SCCoordinator.shared?.hotKeyManager?.registerAll()
            }
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
        table.addNewTable()
        table.addRow(desktopsPerRow)
        table.addRow(previewSize)
        table.addNewTable()
        table.addRow(indicatorStyle)
        table.addRow(showCustomTitle)
        table.addNewTable()
        table.addRow(spatialModifiers)
        return TableGroupSetView(originalViews: [table], bottomPadding: 0)
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

    @objc private static func previewSizeChanged(_ sender: NSPopUpButton) {
        guard let size = DesktopPreviewSize(rawValue: sender.indexOfSelectedItem) else { return }
        SCPreferences.saveDesktopPreviewSize(size)
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
