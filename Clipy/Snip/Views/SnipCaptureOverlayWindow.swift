//
//  SnipCaptureOverlayWindow.swift
//
//  Clipy
//

import AppKit

final class SnipCaptureOverlayWindow: NSWindow {
    let selectionView = SnipSelectionView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        selectionView.frame = NSRect(origin: .zero, size: screen.frame.size)
        selectionView.autoresizingMask = [.width, .height]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
}
