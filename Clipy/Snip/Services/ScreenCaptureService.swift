//
//  ScreenCaptureService.swift
//
//  Clipy
//

import AppKit
import ScreenCaptureKit

enum ScreenCaptureService {
    @discardableResult
    static func requestPermissionIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    static func captureFrame(for screen: NSScreen) async -> CGImage? {
        if #available(macOS 14, *), let image = await captureWithScreenCaptureKit(screen: screen) {
            return image
        }
        return captureWithCoreGraphics(screen: screen)
    }
}

@available(macOS 14, *)
private extension ScreenCaptureService {
    static func captureWithScreenCaptureKit(screen: NSScreen) async -> CGImage? {
        guard let displayID = screen.displayID else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGFloat(scDisplay.width) * screen.backingScaleFactor)
            configuration.height = Int(CGFloat(scDisplay.height) * screen.backingScaleFactor)
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            return nil
        }
    }
}

private extension ScreenCaptureService {
    static func captureWithCoreGraphics(screen: NSScreen) -> CGImage? {
        guard let displayID = screen.displayID else { return nil }
        return CGDisplayCreateImage(displayID)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
