//
//  SnipAnnotationWindowController.swift
//
//  Clipy
//

import AppKit
import Dependencies

final class SnipAnnotationWindowController: NSWindowController {
    enum FinishAction {
        case copy
        case save
        case cancel
    }

    var onFinish: ((FinishAction, NSImage?) -> Void)?

    private let canvasView: AnnotationCanvasView
    private let toolbarView: AnnotationToolbarView
    private let borderFrameView = SnipBorderFrameView(frame: .zero)
    private let baseImageSize: NSSize
    private var viewingScale: CGFloat = 1
    private var showsBorder = false {
        didSet { borderFrameView.isHidden = !showsBorder }
    }

    private static let toolbarHeight: CGFloat = 30
    private static let reservedDragSpace: CGFloat = 60
    private static let borderWidth: CGFloat = 1.5
    // Space reserved around the canvas purely for the border-preview ring; always laid out
    // (whether or not the border is currently shown) so toggling it never has to resize the
    // window or reposition already-drawn shapes. Matches borderWidth exactly so the preview
    // ring sits flush against the canvas with no visible gap, mirroring how addBorderIfNeeded(to:)
    // pads the real exported image.
    private static let previewMargin: CGFloat = borderWidth
    private static let viewingScaleRange: ClosedRange<CGFloat> = 0.1...8
    private static let viewingScaleFactor: CGFloat = 1.12

    init(image: NSImage, screenPoint: NSPoint) {
        let canvas = AnnotationCanvasView(baseImage: image)
        self.canvasView = canvas
        self.baseImageSize = image.size
        let toolbar = AnnotationToolbarView(frame: .zero)
        self.toolbarView = toolbar

        // The toolbar's own buttons can fill most/all of a narrow window, leaving no empty
        // strip to grab for isMovableByWindowBackground - reserve extra width on top of the
        // toolbar's natural fitting size so there's always a draggable gap.
        let minimumToolbarWidth = toolbar.fittingSize.width + Self.reservedDragSpace
        let contentWidth = max(image.size.width + Self.previewMargin * 2, minimumToolbarWidth)
        let contentSize = NSSize(width: contentWidth, height: image.size.height + Self.previewMargin * 2 + Self.toolbarHeight)
        let window = SnipBorderlessWindow(
            contentRect: NSRect(origin: screenPoint, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        super.init(window: window)

        @Dependency(\.defaultAppStorage) var appStorage
        let defaultTool = SnipTool(rawValue: appStorage.string(forKey: Constants.Snip.defaultTool) ?? "") ?? .rectangle
        let defaultColor = Self.savedColor(from: appStorage) ?? .systemRed
        let defaultLineWidth = appStorage.object(forKey: Constants.Snip.defaultLineWidth) as? Double ?? 4
        let defaultShowsBorder = appStorage.bool(forKey: Constants.Snip.defaultShowsBorder)

        canvas.delegate = self
        canvas.currentTool = defaultTool
        canvas.currentColor = defaultColor
        canvas.currentLineWidth = CGFloat(defaultLineWidth)
        toolbar.configureInitial(color: defaultColor, lineWidth: CGFloat(defaultLineWidth), borderOn: defaultShowsBorder)

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        // Toolbar sits below the image; canvas sits above it, centered, with previewMargin of
        // breathing room reserved on every side for the border-preview ring. Keep the canvas at
        // the image's true size (set by AnnotationCanvasView's own init) so drawn shape
        // coordinates line up 1:1 with flattenedImage().
        toolbarView.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: Self.toolbarHeight)
        toolbarView.autoresizingMask = [.width, .maxYMargin]
        canvas.setFrameOrigin(NSPoint(x: (contentSize.width - image.size.width) / 2, y: Self.toolbarHeight + Self.previewMargin))
        borderFrameView.color = Self.isDark(image) ? .white : .black
        borderFrameView.strokeWidth = Self.borderWidth
        updateBorderFrame()
        container.addSubview(borderFrameView)
        container.addSubview(canvas)
        container.addSubview(toolbarView)
        window.contentView = container

        wireToolbar()
        showsBorder = defaultShowsBorder
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvasView)
    }
}

private extension SnipAnnotationWindowController {
    func wireToolbar() {
        toolbarView.onSelectTool = { [weak canvasView] tool in
            canvasView?.currentTool = tool
        }
        toolbarView.onColorChange = { [weak canvasView] color in
            canvasView?.currentColor = color
        }
        toolbarView.onLineWidthChange = { [weak canvasView] width in
            canvasView?.currentLineWidth = width
        }
        toolbarView.onEyedropper = { [weak self] in
            self?.pickColor()
        }
        toolbarView.onBorderToggle = { [weak self] isOn in
            self?.showsBorder = isOn
        }
        toolbarView.onUndo = { [weak canvasView] in canvasView?.undo() }
        toolbarView.onRedo = { [weak canvasView] in canvasView?.redo() }
        toolbarView.onCancel = { [weak self] in self?.finish(.cancel) }
        toolbarView.onSave = { [weak self] in self?.finish(.save) }
        toolbarView.onCopy = { [weak self] in self?.finish(.copy) }
        canvasView.onEscape = { [weak self] in self?.finish(.cancel) }
        canvasView.onToggleToolbar = { [weak self] in self?.toggleToolbar() }
        canvasView.onDoubleClickClose = { [weak self] in self?.finish(.cancel) }
        canvasView.onZoomStep = { [weak self] direction, anchor, screenPoint in
            self?.zoomViewingMode(direction: direction, anchor: anchor, screenPoint: screenPoint)
        }
    }

    func toggleToolbar() {
        let isHidden = !toolbarView.isHidden
        toolbarView.isHidden = isHidden
        // With the toolbar hidden the window is in "viewing" mode: drawing is disabled and
        // dragging the image moves the window instead (see AnnotationCanvasView.isEditable).
        canvasView.isEditable = !isHidden
        if isHidden {
            viewingScale = 1
            resizeViewingWindow(to: viewingScale)
        } else {
            restoreEditingWindow()
        }
    }

    func updateBorderFrame() {
        borderFrameView.frame = canvasView.frame.insetBy(dx: -Self.previewMargin, dy: -Self.previewMargin)
    }

    func zoomViewingMode(direction: Int, anchor: NSPoint, screenPoint: NSPoint) {
        guard toolbarView.isHidden, direction != 0 else { return }
        let proposed = direction > 0
            ? viewingScale * Self.viewingScaleFactor
            : viewingScale / Self.viewingScaleFactor
        let clamped = min(max(proposed, Self.viewingScaleRange.lowerBound), Self.viewingScaleRange.upperBound)
        guard clamped != viewingScale else { return }
        viewingScale = clamped
        resizeViewingWindow(to: viewingScale, anchor: anchor, screenPoint: screenPoint)
    }

    func resizeViewingWindow(
        to scale: CGFloat,
        anchor: NSPoint = NSPoint(x: 0.5, y: 0.5),
        screenPoint: NSPoint? = nil
    ) {
        guard let window else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        canvasView.setDisplayScale(scale)
        let contentSize = NSSize(
            width: canvasView.frame.width + Self.previewMargin * 2,
            height: canvasView.frame.height + Self.previewMargin * 2
        )
        window.setContentSize(contentSize)
        canvasView.setFrameOrigin(NSPoint(x: Self.previewMargin, y: Self.previewMargin))
        if let screenPoint {
            let anchorInWindow = NSPoint(
                x: Self.previewMargin + canvasView.frame.width * anchor.x,
                y: Self.previewMargin + canvasView.frame.height * anchor.y
            )
            window.setFrameOrigin(NSPoint(
                x: screenPoint.x - anchorInWindow.x,
                y: screenPoint.y - anchorInWindow.y
            ))
        } else {
            window.setFrameOrigin(NSPoint(x: center.x - window.frame.width / 2, y: center.y - window.frame.height / 2))
        }
        updateBorderFrame()
    }

    func restoreEditingWindow() {
        guard let window else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        viewingScale = 1
        canvasView.setDisplayScale(1)
        let minimumToolbarWidth = toolbarView.fittingSize.width + Self.reservedDragSpace
        let contentSize = NSSize(
            width: max(baseImageSize.width + Self.previewMargin * 2, minimumToolbarWidth),
            height: baseImageSize.height + Self.previewMargin * 2 + Self.toolbarHeight
        )
        window.setContentSize(contentSize)
        window.setFrameOrigin(NSPoint(x: center.x - window.frame.width / 2, y: center.y - window.frame.height / 2))
        toolbarView.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: Self.toolbarHeight)
        canvasView.setFrameOrigin(NSPoint(
            x: (contentSize.width - baseImageSize.width) / 2,
            y: Self.toolbarHeight + Self.previewMargin
        ))
        updateBorderFrame()
    }

    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let self, let color else { return }
            self.canvasView.currentColor = color
        }
    }

    func finish(_ action: FinishAction) {
        let image = action == .cancel ? nil : addBorderIfNeeded(to: canvasView.flattenedImage())
        window?.close()
        onFinish?(action, image)
    }

    // The border is composited only into the exported (copy/save) image, added entirely
    // *outside* the original pixels - the live edit canvas never previews it - so it can
    // never cover any of the actual screenshot content, and toggling it can't desync
    // already-drawn shape coordinates from the image.
    func addBorderIfNeeded(to image: NSImage) -> NSImage {
        guard showsBorder else { return image }
        let margin = Self.borderWidth
        let newSize = NSSize(width: image.size.width + margin * 2, height: image.size.height + margin * 2)
        let color: NSColor = Self.isDark(image) ? .white : .black

        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: NSRect(x: margin, y: margin, width: image.size.width, height: image.size.height))
        let path = NSBezierPath(rect: NSRect(origin: .zero, size: newSize).insetBy(dx: margin / 2, dy: margin / 2))
        path.lineWidth = Self.borderWidth
        color.withAlphaComponent(0.85).setStroke()
        path.stroke()
        result.unlockFocus()
        return result
    }

    static func savedColor(from appStorage: UserDefaults) -> NSColor? {
        guard let data = appStorage.object(forKey: Constants.Snip.defaultColor) as? Data else { return nil }
        return NSKeyedUnarchiver.unarchiveObject(with: data) as? NSColor
    }

    static func isDark(_ image: NSImage) -> Bool {
        let sampleSize = 16
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: sampleSize * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let data = context.data else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        let buffer = data.bindMemory(to: UInt8.self, capacity: sampleSize * sampleSize * 4)
        var totalLuminance: CGFloat = 0
        for pixel in 0..<(sampleSize * sampleSize) {
            let red = CGFloat(buffer[pixel * 4]) / 255
            let green = CGFloat(buffer[pixel * 4 + 1]) / 255
            let blue = CGFloat(buffer[pixel * 4 + 2]) / 255
            totalLuminance += 0.299 * red + 0.587 * green + 0.114 * blue
        }
        return (totalLuminance / CGFloat(sampleSize * sampleSize)) < 0.5
    }
}

extension SnipAnnotationWindowController: AnnotationCanvasViewDelegate {
    func annotationCanvasView(_ view: AnnotationCanvasView, didUpdateHistory canUndo: Bool, canRedo: Bool) {
        toolbarView.setUndoRedoEnabled(canUndo: canUndo, canRedo: canRedo)
    }

    func annotationCanvasView(_ view: AnnotationCanvasView, didChangeLineWidthTo lineWidth: CGFloat) {
        toolbarView.reflectLineWidth(lineWidth)
    }
}
