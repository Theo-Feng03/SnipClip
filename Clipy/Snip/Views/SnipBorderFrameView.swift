//
//  SnipBorderFrameView.swift
//
//  Clipy
//

import AppKit

final class SnipBorderFrameView: NSView {
    var color: NSColor = .black {
        didSet { needsDisplay = true }
    }
    var strokeWidth: CGFloat = 1.5 {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let inset = strokeWidth / 2
        let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = strokeWidth
        color.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}
