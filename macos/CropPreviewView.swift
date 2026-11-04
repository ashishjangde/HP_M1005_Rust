import AppKit

final class CropPreviewView: NSView {
    var image: CGImage? { didSet { selection = .zero; needsDisplay = true } }
    private(set) var selection = CGRect.zero { didSet { onSelectionChanged?(selection) } }
    var onSelectionChanged: ((CGRect) -> Void)?
    private var dragOrigin: CGPoint?

    override var isFlipped: Bool { false }

    private var imageRect: CGRect {
        guard let image, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let image else {
            let hint = NSAttributedString(string: "Your scan preview will appear here", attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor
            ])
            hint.draw(at: CGPoint(x: bounds.midX - hint.size().width / 2, y: bounds.midY - hint.size().height / 2))
            return
        }
        let rect = imageRect
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: rect)
        if !selection.isEmpty {
            NSColor.systemBlue.withAlphaComponent(0.2).setFill()
            selection.fill()
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        dragOrigin = point
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        selection = CGRect(x: min(dragOrigin.x, point.x), y: min(dragOrigin.y, point.y),
                           width: abs(point.x - dragOrigin.x), height: abs(point.y - dragOrigin.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        dragOrigin = nil
    }

    func clearSelection() { selection = .zero; needsDisplay = true }

    func pixelCropRect() -> CGRect? {
        guard let image, selection.width >= 12, selection.height >= 12 else { return nil }
        let rect = imageRect
        let scaleX = CGFloat(image.width) / rect.width
        let scaleY = CGFloat(image.height) / rect.height
        return CGRect(x: (selection.minX - rect.minX) * scaleX,
                      y: (rect.maxY - selection.maxY) * scaleY,
                      width: selection.width * scaleX,
                      height: selection.height * scaleY)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                       y: min(max(point.y, rect.minY), rect.maxY))
    }
}
