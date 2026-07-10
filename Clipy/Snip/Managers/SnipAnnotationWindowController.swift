//
//  SnipAnnotationWindowController.swift
//
//  Clipy
//

import AppKit

final class SnipAnnotationWindowController: NSWindowController {
    enum FinishAction {
        case copy
        case save
        case cancel
    }

    var onFinish: ((FinishAction, NSImage?) -> Void)?

    private let canvasView: AnnotationCanvasView
    private let toolbarView = AnnotationToolbarView(frame: .zero)

    private static let toolbarHeight: CGFloat = 44

    init(image: NSImage, screenPoint: NSPoint) {
        let canvas = AnnotationCanvasView(baseImage: image)
        self.canvasView = canvas

        let contentSize = NSSize(width: max(image.size.width, 360), height: image.size.height + Self.toolbarHeight)
        let window = NSWindow(
            contentRect: NSRect(origin: screenPoint, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false

        super.init(window: window)

        canvas.delegate = self
        canvas.currentTool = .rectangle
        canvas.currentColor = .systemRed

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        toolbarView.frame = NSRect(x: 0, y: contentSize.height - Self.toolbarHeight, width: contentSize.width, height: Self.toolbarHeight)
        toolbarView.autoresizingMask = [.width, .minYMargin]
        canvas.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: image.size.height)
        canvas.autoresizingMask = [.width, .height]
        container.addSubview(canvas)
        container.addSubview(toolbarView)
        window.contentView = container

        wireToolbar()
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
        toolbarView.onUndo = { [weak canvasView] in canvasView?.undo() }
        toolbarView.onRedo = { [weak canvasView] in canvasView?.redo() }
        toolbarView.onCancel = { [weak self] in self?.finish(.cancel) }
        toolbarView.onSave = { [weak self] in self?.finish(.save) }
        toolbarView.onCopy = { [weak self] in self?.finish(.copy) }
    }

    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let self, let color else { return }
            self.canvasView.currentColor = color
        }
    }

    func finish(_ action: FinishAction) {
        let image = action == .cancel ? nil : canvasView.flattenedImage()
        window?.close()
        onFinish?(action, image)
    }
}

extension SnipAnnotationWindowController: AnnotationCanvasViewDelegate {
    func annotationCanvasView(_ view: AnnotationCanvasView, didUpdateHistory canUndo: Bool, canRedo: Bool) {
        toolbarView.setUndoRedoEnabled(canUndo: canUndo, canRedo: canRedo)
    }
}
