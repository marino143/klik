import AppKit
import CoreImage

final class AnnotationCanvasView: NSView {
    let baseImage: NSImage
    private(set) var annotations: [Annotation] = []
    var currentTool: Tool = .select { didSet { updateCursor() } }
    var style = AnnotationStyle()

    private var draftStart: CGPoint?
    private var draftEnd: CGPoint?
    private var activeTextField: NSTextField?
    private let ciContext = CIContext()

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize { baseImage.size }

    private func updateCursor() {
        switch currentTool {
        case .select: NSCursor.arrow.set()
        case .text:   NSCursor.iBeam.set()
        default:      NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor
        switch currentTool {
        case .select: cursor = .arrow
        case .text:   cursor = .iBeam
        default:      cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        commitActiveTextField()
        let p = convert(event.locationInWindow, from: nil)
        draftStart = p
        draftEnd = p

        if currentTool == .text {
            beginTextEdit(at: p)
            return
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard draftStart != nil else { return }
        draftEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            draftStart = nil
            draftEnd = nil
            needsDisplay = true
        }
        guard let start = draftStart, let end = draftEnd else { return }
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch currentTool {
        case .select, .text:
            return
        case .rect:
            guard rect.width > 4, rect.height > 4 else { return }
            annotations.append(.rect(id: UUID(), frame: rect, style: style))
        case .arrow:
            guard hypot(end.x - start.x, end.y - start.y) > 8 else { return }
            annotations.append(.arrow(id: UUID(), from: start, to: end, style: style))
        case .highlight:
            guard rect.width > 4, rect.height > 4 else { return }
            var s = style
            s.color = style.color.withAlphaComponent(0.35)
            annotations.append(.highlight(id: UUID(), frame: rect, style: s))
        case .blur:
            guard rect.width > 4, rect.height > 4 else { return }
            annotations.append(.blur(id: UUID(), frame: rect, radius: 16))
        case .crop:
            guard rect.width > 8, rect.height > 8 else { return }
            performCrop(to: rect)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            undo()
        } else {
            super.keyDown(with: event)
        }
    }

    func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
            needsDisplay = true
        }
    }

    private func beginTextEdit(at point: CGPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: 200, height: max(28, style.fontSize + 8)))
        field.font = NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
        field.textColor = style.color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.0)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Type…"
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitActiveTextField()
    }

    private func commitActiveTextField() {
        guard let field = activeTextField else { return }
        let text = field.stringValue
        let origin = field.frame.origin
        field.removeFromSuperview()
        activeTextField = nil
        if !text.isEmpty {
            annotations.append(.text(id: UUID(), origin: origin, string: text, style: style))
        }
        needsDisplay = true
    }

    private func performCrop(to rect: CGRect) {
        guard let cg = renderedCGImage() else { return }
        let scale = CGFloat(cg.width) / bounds.width
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = cg.cropping(to: cropRect) else { return }
        let newImage = NSImage(cgImage: cropped, size: rect.size)
        EditorWindowController.show(image: newImage)
        window?.close()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        baseImage.draw(in: bounds)

        for annotation in annotations {
            drawAnnotation(annotation, in: context)
        }

        if let start = draftStart, let end = draftEnd, currentTool != .text {
            drawDraft(from: start, to: end, in: context)
        }
    }

    private func drawAnnotation(_ annotation: Annotation, in context: CGContext) {
        switch annotation {
        case .rect(_, let frame, let style):
            context.setStrokeColor(style.color.cgColor)
            context.setLineWidth(style.strokeWidth)
            context.stroke(frame)
        case .arrow(_, let from, let to, let style):
            drawArrow(from: from, to: to, style: style, in: context)
        case .highlight(_, let frame, let style):
            context.setFillColor(style.color.cgColor)
            context.fill(frame)
        case .text(_, let origin, let text, let style):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
                .foregroundColor: style.color
            ]
            (text as NSString).draw(at: origin, withAttributes: attrs)
        case .blur(_, let frame, let radius):
            drawBlur(in: frame, radius: radius, context: context)
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, style: AnnotationStyle, in context: CGContext) {
        context.setStrokeColor(style.color.cgColor)
        context.setFillColor(style.color.cgColor)
        context.setLineWidth(style.strokeWidth)
        context.setLineCap(.round)

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = max(12, style.strokeWidth * 4)
        let headAngle: CGFloat = .pi / 6

        let shaftEnd = CGPoint(
            x: to.x - cos(angle) * headLength * 0.6,
            y: to.y - sin(angle) * headLength * 0.6
        )

        context.move(to: from)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let p1 = CGPoint(x: to.x - cos(angle - headAngle) * headLength,
                         y: to.y - sin(angle - headAngle) * headLength)
        let p2 = CGPoint(x: to.x - cos(angle + headAngle) * headLength,
                         y: to.y - sin(angle + headAngle) * headLength)
        context.move(to: to)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    private func drawBlur(in frame: CGRect, radius: CGFloat, context: CGContext) {
        guard let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scaleX = CGFloat(cg.width) / bounds.width
        let scaleY = CGFloat(cg.height) / bounds.height

        let imageRect = CGRect(
            x: frame.origin.x * scaleX,
            y: (bounds.height - frame.origin.y - frame.height) * scaleY,
            width: frame.width * scaleX,
            height: frame.height * scaleY
        )

        guard let cropped = cg.cropping(to: imageRect) else { return }
        let ciImage = CIImage(cgImage: cropped)
        let blurred = ciImage
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: ciImage.extent)
        guard let outputCG = ciContext.createCGImage(blurred, from: blurred.extent) else { return }
        context.saveGState()
        context.draw(outputCG, in: frame)
        context.restoreGState()
    }

    private func drawDraft(from: CGPoint, to: CGPoint, in context: CGContext) {
        let rect = CGRect(
            x: min(from.x, to.x),
            y: min(from.y, to.y),
            width: abs(to.x - from.x),
            height: abs(to.y - from.y)
        )
        switch currentTool {
        case .rect:
            context.setStrokeColor(style.color.cgColor)
            context.setLineWidth(style.strokeWidth)
            context.stroke(rect)
        case .arrow:
            drawArrow(from: from, to: to, style: style, in: context)
        case .highlight:
            context.setFillColor(style.color.withAlphaComponent(0.35).cgColor)
            context.fill(rect)
        case .blur:
            drawBlur(in: rect, radius: 16, context: context)
        case .crop:
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(rect)
            context.setLineDash(phase: 0, lengths: [])
        case .select, .text:
            break
        }
    }

    func renderedImage() -> NSImage? {
        guard let cg = renderedCGImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func renderedCGImage() -> CGImage? {
        guard let cgBase = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cgBase.width
        let height = cgBase.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        let scaleX = CGFloat(width) / bounds.width
        let scaleY = CGFloat(height) / bounds.height

        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgBase, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()

        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        for annotation in annotations {
            drawAnnotationFlipped(annotation, in: context)
        }

        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()

        return context.makeImage()
    }

    private func drawAnnotationFlipped(_ annotation: Annotation, in context: CGContext) {
        let h = bounds.height
        switch annotation {
        case .rect(_, let frame, let style):
            let f = CGRect(x: frame.origin.x, y: h - frame.origin.y - frame.height,
                          width: frame.width, height: frame.height)
            context.setStrokeColor(style.color.cgColor)
            context.setLineWidth(style.strokeWidth)
            context.stroke(f)
        case .arrow(_, let from, let to, let style):
            let f = CGPoint(x: from.x, y: h - from.y)
            let t = CGPoint(x: to.x, y: h - to.y)
            drawArrowAbsolute(from: f, to: t, style: style, in: context)
        case .highlight(_, let frame, let style):
            let f = CGRect(x: frame.origin.x, y: h - frame.origin.y - frame.height,
                          width: frame.width, height: frame.height)
            context.setFillColor(style.color.cgColor)
            context.fill(f)
        case .text(_, let origin, let text, let style):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
                .foregroundColor: style.color
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let drawPoint = NSPoint(x: origin.x, y: h - origin.y - size.height)
            (text as NSString).draw(at: drawPoint, withAttributes: attrs)
        case .blur(_, let frame, let radius):
            let f = CGRect(x: frame.origin.x, y: h - frame.origin.y - frame.height,
                          width: frame.width, height: frame.height)
            drawBlurFlipped(in: f, radius: radius, context: context)
        }
    }

    private func drawArrowAbsolute(from: CGPoint, to: CGPoint, style: AnnotationStyle, in context: CGContext) {
        context.setStrokeColor(style.color.cgColor)
        context.setFillColor(style.color.cgColor)
        context.setLineWidth(style.strokeWidth)
        context.setLineCap(.round)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = max(12, style.strokeWidth * 4)
        let headAngle: CGFloat = .pi / 6
        let shaftEnd = CGPoint(
            x: to.x - cos(angle) * headLength * 0.6,
            y: to.y - sin(angle) * headLength * 0.6
        )
        context.move(to: from)
        context.addLine(to: shaftEnd)
        context.strokePath()
        let p1 = CGPoint(x: to.x - cos(angle - headAngle) * headLength,
                         y: to.y - sin(angle - headAngle) * headLength)
        let p2 = CGPoint(x: to.x - cos(angle + headAngle) * headLength,
                         y: to.y - sin(angle + headAngle) * headLength)
        context.move(to: to)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    private func drawBlurFlipped(in frame: CGRect, radius: CGFloat, context: CGContext) {
        guard let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scaleX = CGFloat(cg.width) / bounds.width
        let scaleY = CGFloat(cg.height) / bounds.height
        let imageRect = CGRect(
            x: frame.origin.x * scaleX,
            y: frame.origin.y * scaleY,
            width: frame.width * scaleX,
            height: frame.height * scaleY
        )
        guard let cropped = cg.cropping(to: imageRect) else { return }
        let ciImage = CIImage(cgImage: cropped)
        let blurred = ciImage
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: ciImage.extent)
        guard let outputCG = ciContext.createCGImage(blurred, from: blurred.extent) else { return }
        context.draw(outputCG, in: frame)
    }
}
