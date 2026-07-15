//
//  SnipBorderlessWindow.swift
//
//  Clipy
//

import AppKit

class SnipBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
