//
//  AnnotationToolbarView.swift
//
//  Clipy
//

import AppKit

final class AnnotationToolbarView: NSView {
    var onSelectTool: ((SnipTool) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    var onLineWidthChange: ((CGFloat) -> Void)?
    var onEyedropper: (() -> Void)?
    var onBorderToggle: ((Bool) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let borderButton = NSButton()
    private let colorWell = NSColorWell()
    private let widthControl = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne, target: nil, action: nil)
    static let lineWidths: [CGFloat] = [2, 4, 8]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUndoRedoEnabled(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    func configureInitial(color: NSColor, lineWidth: CGFloat, borderOn: Bool) {
        colorWell.color = color
        let index = Self.lineWidths.enumerated().min { abs($0.element - lineWidth) < abs($1.element - lineWidth) }?.offset ?? 1
        widthControl.selectedSegment = index
        borderButton.state = borderOn ? .on : .off
    }

    // Keeps the S/M/L control in sync with scroll-wheel width changes: highlights the
    // matching preset, or clears the selection for an in-between width.
    func reflectLineWidth(_ lineWidth: CGFloat) {
        if let index = Self.lineWidths.firstIndex(of: lineWidth) {
            widthControl.selectedSegment = index
        } else {
            for segment in 0..<widthControl.segmentCount {
                widthControl.setSelected(false, forSegment: segment)
            }
        }
    }
}

private extension AnnotationToolbarView {
    struct ToolItem {
        let tool: SnipTool
        let symbol: String
        let accessibilityDescription: String
    }

    static let toolItems: [ToolItem] = [
        ToolItem(tool: .rectangle, symbol: "rectangle", accessibilityDescription: "Rectangle"),
        ToolItem(tool: .ellipse, symbol: "circle", accessibilityDescription: "Ellipse"),
        ToolItem(tool: .arrow, symbol: "arrow.up.right", accessibilityDescription: "Arrow"),
        ToolItem(tool: .line, symbol: "line.diagonal", accessibilityDescription: "Line"),
        ToolItem(tool: .text, symbol: "textformat", accessibilityDescription: "Text"),
        ToolItem(tool: .stepMarker, symbol: "1.circle", accessibilityDescription: "Step Marker"),
        ToolItem(tool: .mosaic, symbol: "square.grid.3x3.fill", accessibilityDescription: "Mosaic")
    ]

    func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let toolStack = NSStackView(views: Self.toolItems.enumerated().map { makeToolButton(index: $0.offset, item: $0.element) })
        toolStack.orientation = .horizontal
        toolStack.spacing = 2

        let eyedropperButton = makeIconButton(symbol: "eyedropper", accessibilityDescription: "Eyedropper", action: #selector(eyedropperTapped))

        borderButton.image = NSImage(systemSymbolName: "square.dashed", accessibilityDescription: "Border")
        borderButton.bezelStyle = .texturedRounded
        borderButton.setButtonType(.pushOnPushOff)
        borderButton.controlSize = .small
        borderButton.target = self
        borderButton.action = #selector(borderToggled)

        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 24).isActive = true

        widthControl.selectedSegment = 1
        widthControl.controlSize = .small
        widthControl.target = self
        widthControl.action = #selector(widthChanged)

        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoButton.bezelStyle = .texturedRounded
        undoButton.controlSize = .small
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.isEnabled = false

        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        redoButton.bezelStyle = .texturedRounded
        redoButton.controlSize = .small
        redoButton.target = self
        redoButton.action = #selector(redoTapped)
        redoButton.isEnabled = false

        let cancelButton = makeIconButton(symbol: "xmark", accessibilityDescription: "Cancel", action: #selector(cancelTapped))
        let saveButton = makeIconButton(symbol: "square.and.arrow.down", accessibilityDescription: "Save", action: #selector(saveTapped))
        let copyButton = makeIconButton(symbol: "doc.on.doc", accessibilityDescription: "Copy", action: #selector(copyTapped))

        let leftStack = NSStackView(views: [toolStack, eyedropperButton, borderButton, colorWell, widthControl, undoButton, redoButton])
        leftStack.orientation = .horizontal
        leftStack.spacing = 6

        let rightStack = NSStackView(views: [cancelButton, saveButton, copyButton])
        rightStack.orientation = .horizontal
        rightStack.spacing = 4

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let mainStack = NSStackView(views: [leftStack, spacer, rightStack])
        mainStack.orientation = .horizontal
        mainStack.spacing = 8
        mainStack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func makeToolButton(index: Int, item: ToolItem) -> NSButton {
        let button = makeIconButton(symbol: item.symbol, accessibilityDescription: item.accessibilityDescription, action: #selector(toolTapped(_:)))
        button.tag = index
        return button
    }

    func makeIconButton(symbol: String, accessibilityDescription: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.imagePosition = .imageOnly
        return button
    }
}

private extension AnnotationToolbarView {
    @objc func toolTapped(_ sender: NSButton) {
        guard Self.toolItems.indices.contains(sender.tag) else { return }
        onSelectTool?(Self.toolItems[sender.tag].tool)
    }

    @objc func colorChanged() {
        onColorChange?(colorWell.color)
    }

    @objc func widthChanged() {
        let index = min(max(widthControl.selectedSegment, 0), Self.lineWidths.count - 1)
        onLineWidthChange?(Self.lineWidths[index])
    }

    @objc func eyedropperTapped() {
        onEyedropper?()
    }

    @objc func borderToggled() {
        onBorderToggle?(borderButton.state == .on)
    }

    @objc func undoTapped() {
        onUndo?()
    }

    @objc func redoTapped() {
        onRedo?()
    }

    @objc func cancelTapped() {
        onCancel?()
    }

    @objc func saveTapped() {
        onSave?()
    }

    @objc func copyTapped() {
        onCopy?()
    }
}
