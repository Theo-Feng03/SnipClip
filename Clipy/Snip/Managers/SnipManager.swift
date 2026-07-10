//
//  SnipManager.swift
//
//  Clipy
//

import AppKit

final class SnipManager {
    private let hotKeyService = SnipHotKeyService()
    private var overlayWindows: [SnipCaptureOverlayWindow] = []

    func setup() {
        hotKeyService.onTrigger = { [weak self] in
            self?.beginCapture()
        }
        hotKeyService.setup()
    }
}

private extension SnipManager {
    func beginCapture() {
        guard overlayWindows.isEmpty else { return }
        guard ScreenCaptureService.requestPermissionIfNeeded() else {
            showPermissionAlert()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var capturedFrames: [CGDirectDisplayID: CGImage] = [:]
            for screen in NSScreen.screens {
                guard let displayID = screen.displayID else { continue }
                if let image = await ScreenCaptureService.captureFrame(for: screen) {
                    capturedFrames[displayID] = image
                }
            }
            self.presentOverlays(capturedFrames: capturedFrames)
        }
    }

    func presentOverlays(capturedFrames: [CGDirectDisplayID: CGImage]) {
        guard !capturedFrames.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID, let frameImage = capturedFrames[displayID] else { continue }
            let window = SnipCaptureOverlayWindow(screen: screen)
            window.selectionView.onFinish = { [weak self] selection in
                self?.finishCapture(selection: selection, screen: screen, frameImage: frameImage)
            }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.selectionView)
            overlayWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishCapture(selection: CGRect?, screen: NSScreen, frameImage: CGImage) {
        closeOverlays()
        guard let selection, selection.width >= 4, selection.height >= 4 else { return }

        let scale = screen.backingScaleFactor
        let pixelRect = CGRect(
            x: selection.origin.x * scale,
            y: selection.origin.y * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
        guard let cropped = frameImage.cropping(to: pixelRect) else { return }

        let image = NSImage(cgImage: cropped, size: NSSize(width: pixelRect.width / scale, height: pixelRect.height / scale))
        copyToClipboard(image)
    }

    func closeOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Please allow Screen Recording")
        alert.informativeText = String(localized: "To capture the screen, allow Screen Recording for Clipy in Privacy & Security settings, then try again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
