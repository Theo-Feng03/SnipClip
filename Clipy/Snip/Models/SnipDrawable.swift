//
//  SnipDrawable.swift
//
//  Clipy
//

import AppKit

enum SnipTool {
    case none
    case rectangle
    case ellipse
    case arrow
    case line
    case text
    case stepMarker
    case mosaic
}

struct SnipShape {
    enum Kind {
        case rectangle(NSRect)
        case ellipse(NSRect)
        case arrow(from: NSPoint, to: NSPoint)
        case line(from: NSPoint, to: NSPoint)
        case text(String, origin: NSPoint)
        case stepMarker(number: Int, center: NSPoint)
        case mosaic(NSRect)
    }

    let kind: Kind
    let color: NSColor
    let lineWidth: CGFloat
}

extension SnipShape {
    func draw(baseImage: NSImage) {
        switch kind {
        case .rectangle(let rect):
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        case .ellipse(let rect):
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = lineWidth
            color.setStroke()
            path.stroke()
        case .arrow(let from, let to):
            Self.drawArrow(from: from, to: to, color: color, lineWidth: lineWidth)
        case .line(let from, let to):
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
        case .text(let string, let origin):
            (string as NSString).draw(at: origin, withAttributes: [
                .font: NSFont.systemFont(ofSize: max(14, lineWidth * 6)),
                .foregroundColor: color
            ])
        case .stepMarker(let number, let center):
            let radius: CGFloat = max(10, lineWidth * 4)
            let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let text = "\(number)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: radius),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            let textOrigin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            (text as NSString).draw(at: textOrigin, withAttributes: attributes)
        case .mosaic(let rect):
            Self.drawMosaic(rect: rect, baseImage: baseImage, lineWidth: lineWidth)
        }
    }
}

private extension SnipShape {
    static func drawArrow(from: NSPoint, to: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = max(10, lineWidth * 4)
        let headAngle: CGFloat = .pi / 7
        let p1 = NSPoint(x: to.x - headLength * cos(angle - headAngle), y: to.y - headLength * sin(angle - headAngle))
        let p2 = NSPoint(x: to.x - headLength * cos(angle + headAngle), y: to.y - headLength * sin(angle + headAngle))
        let head = NSBezierPath()
        head.move(to: to)
        head.line(to: p1)
        head.line(to: p2)
        head.close()
        color.setFill()
        head.fill()
    }

    static func drawMosaic(rect: NSRect, baseImage: NSImage, lineWidth: CGFloat) {
        guard rect.width > 1, rect.height > 1,
              let cgBase = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scaleX = CGFloat(cgBase.width) / baseImage.size.width
        let scaleY = CGFloat(cgBase.height) / baseImage.size.height
        let pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        guard let cropped = cgBase.cropping(to: pixelRect) else { return }
        let ciImage = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: "CIPixellate") else { return }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(max(8, lineWidth * 3), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return }
        let context = CIContext()
        guard let outputCG = context.createCGImage(output, from: ciImage.extent) else { return }
        NSImage(cgImage: outputCG, size: rect.size).draw(in: rect)
    }
}
