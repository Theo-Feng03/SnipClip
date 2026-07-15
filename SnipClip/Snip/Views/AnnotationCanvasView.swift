//
//  AnnotationCanvasView.swift
//
//  Clipy
//

import AppKit

protocol AnnotationCanvasViewDelegate: AnyObject {
    func annotationCanvasView(_ view: AnnotationCanvasView, didUpdateHistory canUndo: Bool, canRedo: Bool)
}

final class AnnotationCanvasView: NSView {
    weak var delegate: AnnotationCanvasViewDelegate?

    var currentTool: SnipTool = .none
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3

    private let baseImage: NSImage
    private var shapes: [SnipShape] = []
    private var inProgressShape: SnipShape?
    private var dragStart: NSPoint?
    private var activeTextEditor: NSTextField?
    private let history = UndoManager()

    init(baseImage: NSImage) {
        self.baseImage = baseImage
        super.init(frame: NSRect(origin: .zero, size: baseImage.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    var isEditable = true
    var onEscape: (() -> Void)?
    var onToggleToolbar: (() -> Void)?
    var onDoubleClickClose: (() -> Void)?

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() { history.undo() }
    func redo() { history.redo() }

    func flattenedImage() -> NSImage {
        let image = NSImage(size: baseImage.size)
        image.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size))
        shapes.forEach { $0.draw(baseImage: baseImage) }
        image.unlockFocus()
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        baseImage.draw(in: bounds)
        shapes.forEach { $0.draw(baseImage: baseImage) }
        inProgressShape?.draw(baseImage: baseImage)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onDoubleClickClose?()
            return
        }
        guard isEditable, currentTool != .none else {
            // Viewing mode (toolbar hidden): dragging the image moves the window. Done
            // manually via performDrag rather than mouseDownCanMoveWindow so this view
            // still receives clicks for the double-click-to-close gesture above.
            if !isEditable {
                window?.performDrag(with: event)
            }
            return
        }
        let point = clampedPoint(convert(event.locationInWindow, from: nil))

        switch currentTool {
        case .text:
            beginTextEditing(at: point)
        case .stepMarker:
            addShape(SnipShape(kind: .stepMarker(number: nextStepNumber, center: point), color: currentColor, lineWidth: currentLineWidth))
        default:
            dragStart = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        // The view that receives mouseDown keeps receiving mouseDragged/mouseUp for the whole
        // gesture even once the cursor leaves this view's bounds (or the window entirely), so
        // the drag endpoint is otherwise unconstrained - clamp it to the image's true edges.
        let point = clampedPoint(convert(event.locationInWindow, from: nil))
        inProgressShape = shapeForDrag(from: start, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            inProgressShape = nil
            dragStart = nil
            needsDisplay = true
        }
        guard let shape = inProgressShape, isSignificant(shape) else { return }
        addShape(shape)
    }

    override func rightMouseDown(with event: NSEvent) {
        onToggleToolbar?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        guard isEditable, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" else {
            super.keyDown(with: event)
            return
        }
        if event.modifierFlags.contains(.shift) {
            redo()
        } else {
            undo()
        }
    }
}

private extension AnnotationCanvasView {
    var nextStepNumber: Int {
        shapes.reduce(1) { count, shape in
            if case .stepMarker = shape.kind { return count + 1 }
            return count
        }
    }

    func clampedPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    func isSignificant(_ shape: SnipShape) -> Bool {
        switch shape.kind {
        case .rectangle(let rect), .ellipse(let rect), .mosaic(let rect):
            return rect.width >= 2 && rect.height >= 2
        case .arrow(let from, let to), .line(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) >= 2
        case .text, .stepMarker:
            return true
        }
    }

    func shapeForDrag(from start: NSPoint, to end: NSPoint) -> SnipShape {
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let kind: SnipShape.Kind
        switch currentTool {
        case .ellipse:
            kind = .ellipse(rect)
        case .arrow:
            kind = .arrow(from: start, to: end)
        case .line:
            kind = .line(from: start, to: end)
        case .mosaic:
            kind = .mosaic(rect)
        default:
            kind = .rectangle(rect)
        }
        return SnipShape(kind: kind, color: currentColor, lineWidth: currentLineWidth)
    }

    func addShape(_ shape: SnipShape) {
        shapes.append(shape)
        history.registerUndo(withTarget: self) { target in
            target.popShape()
        }
        notifyHistoryChanged()
        needsDisplay = true
    }

    func popShape() {
        guard let removed = shapes.popLast() else { return }
        history.registerUndo(withTarget: self) { target in
            target.addShape(removed)
        }
        notifyHistoryChanged()
        needsDisplay = true
    }

    func notifyHistoryChanged() {
        delegate?.annotationCanvasView(self, didUpdateHistory: canUndo, canRedo: canRedo)
    }

    func beginTextEditing(at point: NSPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 10, width: 220, height: 24))
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: max(14, currentLineWidth * 6))
        field.textColor = currentColor
        field.delegate = self
        field.focusRingType = .none
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextEditor = field
    }
}

extension AnnotationCanvasView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = activeTextEditor else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        activeTextEditor = nil
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        addShape(SnipShape(kind: .text(text, origin: field.frame.origin), color: currentColor, lineWidth: currentLineWidth))
    }
}
