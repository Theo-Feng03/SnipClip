//
//  SnipSelectionView.swift
//
//  Clipy
//

import AppKit

final class SnipSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: NSPoint?
    private var currentSelectionRect: NSRect?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let overlayPath = NSBezierPath(rect: bounds)
        let selection = currentSelectionRect.flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
        if let selection {
            overlayPath.append(NSBezierPath(rect: selection))
            overlayPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.25).setFill()
        overlayPath.fill()

        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        drawDimensionLabel(for: selection)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentSelectionRect = NSRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentSelectionRect = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = currentSelectionRect
        startPoint = nil
        currentSelectionRect = nil
        needsDisplay = true
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        startPoint = nil
        currentSelectionRect = nil
        needsDisplay = true
        onFinish?(nil)
    }
}

private extension SnipSelectionView {
    func drawDimensionLabel(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 4
        var origin = NSPoint(x: rect.minX, y: rect.minY - size.height - padding * 2)
        if origin.y < 0 {
            origin.y = rect.minY + padding
        }
        let backgroundRect = NSRect(x: origin.x, y: origin.y, width: size.width + padding * 2, height: size.height + padding * 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 3, yRadius: 3).fill()
        text.draw(at: NSPoint(x: origin.x + padding, y: origin.y + padding), withAttributes: attributes)
    }
}
