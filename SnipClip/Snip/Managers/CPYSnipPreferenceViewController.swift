//
//  CPYSnipPreferenceViewController.swift
//
//  Clipy
//

import Cocoa
import Dependencies
import KeyHolder
import Magnet

final class CPYSnipPreferenceViewController: NSViewController {
    private let hotKeyRecordView = RecordView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
    private let toolPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorWell = NSColorWell()
    private let widthControl = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne, target: nil, action: nil)
    private let borderCheckbox = NSButton(checkboxWithTitle: String(localized: "Show border by default"), target: nil, action: nil)
    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    // Value stored in Constants.Snip.appLanguage; "system" means no per-app override.
    private static let languageOptions: [(value: String, title: String)] = [
        ("system", String(localized: "System Default")),
        ("en", "English"),
        ("zh-Hans", "简体中文")
    ]

    @Dependency(\.defaultAppStorage) private var appStorage

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        build()
        loadCurrentValues()
    }
}

private extension CPYSnipPreferenceViewController {
    func build() {
        hotKeyRecordView.delegate = self
        hotKeyRecordView.translatesAutoresizingMaskIntoConstraints = false
        hotKeyRecordView.widthAnchor.constraint(equalToConstant: 160).isActive = true
        hotKeyRecordView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        SnipTool.allCases.filter { $0 != .none }.forEach { toolPopUp.addItem(withTitle: $0.displayName) }
        toolPopUp.target = self
        toolPopUp.action = #selector(toolChanged)

        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true

        widthControl.target = self
        widthControl.action = #selector(widthChanged)

        borderCheckbox.target = self
        borderCheckbox.action = #selector(borderChanged)

        Self.languageOptions.forEach { languagePopUp.addItem(withTitle: $0.title) }
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)

        let rows = [
            labeledRow(title: String(localized: "Hotkey:"), control: hotKeyRecordView),
            labeledRow(title: String(localized: "Default Tool:"), control: toolPopUp),
            labeledRow(title: String(localized: "Default Color:"), control: colorWell),
            labeledRow(title: String(localized: "Default Line Width:"), control: widthControl),
            borderCheckbox,
            labeledRow(title: String(localized: "Language:"), control: languagePopUp)
        ]

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)
        ])
    }

    func labeledRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    func loadCurrentValues() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        hotKeyRecordView.keyCombo = appDelegate.snipManager.hotKeyCombo

        let tool = SnipTool(rawValue: appStorage.string(forKey: Constants.Snip.defaultTool) ?? "") ?? .rectangle
        toolPopUp.selectItem(withTitle: tool.displayName)

        if let data = appStorage.object(forKey: Constants.Snip.defaultColor) as? Data,
           let color = NSKeyedUnarchiver.unarchiveObject(with: data) as? NSColor {
            colorWell.color = color
        } else {
            colorWell.color = .systemRed
        }

        let lineWidth = appStorage.object(forKey: Constants.Snip.defaultLineWidth) as? Double ?? 4
        let index = AnnotationToolbarView.lineWidths.enumerated().min {
            abs($0.element - CGFloat(lineWidth)) < abs($1.element - CGFloat(lineWidth))
        }?.offset ?? 1
        widthControl.selectedSegment = index

        borderCheckbox.state = appStorage.bool(forKey: Constants.Snip.defaultShowsBorder) ? .on : .off

        let language = UserDefaults.standard.string(forKey: Constants.Snip.appLanguage) ?? "system"
        let languageIndex = Self.languageOptions.firstIndex { $0.value == language } ?? 0
        languagePopUp.selectItem(at: languageIndex)
    }

    @objc func toolChanged() {
        let tools = SnipTool.allCases.filter { $0 != .none }
        guard tools.indices.contains(toolPopUp.indexOfSelectedItem) else { return }
        appStorage.set(tools[toolPopUp.indexOfSelectedItem].rawValue, forKey: Constants.Snip.defaultTool)
    }

    @objc func colorChanged() {
        appStorage.set(colorWell.color.archive(), forKey: Constants.Snip.defaultColor)
    }

    @objc func widthChanged() {
        let index = min(max(widthControl.selectedSegment, 0), AnnotationToolbarView.lineWidths.count - 1)
        appStorage.set(Double(AnnotationToolbarView.lineWidths[index]), forKey: Constants.Snip.defaultLineWidth)
    }

    @objc func borderChanged() {
        appStorage.set(borderCheckbox.state == .on, forKey: Constants.Snip.defaultShowsBorder)
    }

    @objc func languageChanged() {
        guard Self.languageOptions.indices.contains(languagePopUp.indexOfSelectedItem) else { return }
        let choice = Self.languageOptions[languagePopUp.indexOfSelectedItem].value

        // AppleLanguages is the system-level per-app language override; it must live in
        // UserDefaults.standard and only takes effect on the next launch.
        let defaults = UserDefaults.standard
        defaults.set(choice, forKey: Constants.Snip.appLanguage)
        if choice == "system" {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([choice], forKey: "AppleLanguages")
        }
        defaults.synchronize()
        promptRelaunch()
    }

    func promptRelaunch() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Language changed")
        alert.informativeText = String(localized: "Relaunch SnipClip to apply the new language.")
        alert.addButton(withTitle: String(localized: "Relaunch Now"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

extension CPYSnipPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool { true }
    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool { true }
    func recordViewDidEndRecording(_ recordView: RecordView) {}

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.snipManager.changeHotKey(to: keyCombo)
    }
}
