//
//  SnipManager.swift
//
//  Clipy
//

import AppKit
import Magnet
import UniformTypeIdentifiers

final class SnipManager {
    private let hotKeyService = SnipHotKeyService()
    private var overlayWindows: [SnipCaptureOverlayWindow] = []
    private var annotationWindowControllers: [SnipAnnotationWindowController] = []

    var hotKeyCombo: KeyCombo? { hotKeyService.keyCombo }

    func setup() {
        hotKeyService.onTrigger = { [weak self] in
            self?.beginCapture()
        }
        hotKeyService.setup()
    }

    func changeHotKey(to keyCombo: KeyCombo?) {
        hotKeyService.change(to: keyCombo)
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
        let globalOrigin = NSPoint(
            x: screen.frame.origin.x + selection.origin.x,
            y: screen.frame.origin.y + (screen.frame.height - selection.origin.y - selection.height)
        )
        presentAnnotationEditor(image: image, origin: globalOrigin)
    }

    func closeOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    func presentAnnotationEditor(image: NSImage, origin: NSPoint) {
        let controller = SnipAnnotationWindowController(image: image, screenPoint: origin)
        annotationWindowControllers.append(controller)
        controller.onFinish = { [weak self, weak controller] action, resultImage in
            guard let self else { return }
            if let controller {
                self.annotationWindowControllers.removeAll { $0 === controller }
            }
            switch action {
            case .copy:
                if let resultImage { self.copyToClipboard(resultImage) }
            case .save:
                if let resultImage { self.saveToDisk(resultImage) }
            case .cancel:
                break
            }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func saveToDisk(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snip \(Self.timestampFormatter.string(from: Date()))"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
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

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}
