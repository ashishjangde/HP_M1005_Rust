import AppKit

final class CropPreviewView: NSView {
    var image: CGImage? {
        didSet {
            selection = .zero
            hint.isHidden = image != nil
            selectionLayer.path = nil
            needsDisplay = true
        }
    }
    private(set) var selection = CGRect.zero { didSet { onSelectionChanged?(selection) } }
    var onSelectionChanged: ((CGRect) -> Void)?
    private var dragOrigin: CGPoint?
    private let hint = NSTextField(labelWithString: "Your scan preview will appear here")
    private let selectionLayer = CAShapeLayer()

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configurePreview()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePreview()
    }

    private func configurePreview() {
        wantsLayer = true
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        selectionLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
        selectionLayer.strokeColor = NSColor.systemBlue.cgColor
        selectionLayer.lineWidth = 2
        layer?.addSublayer(selectionLayer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if selectionLayer.superlayer == nil { layer?.addSublayer(selectionLayer) }
    }

    override func layout() {
        super.layout()
        selectionLayer.frame = bounds
    }

    private var imageRect: CGRect {
        guard let image, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        selectionLayer.frame = bounds
        if let image {
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext.current?.cgContext {
                context.interpolationQuality = .high
                context.draw(image, in: imageRect)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        updateSelectionLayer()
    }

    override func mouseDown(with event: NSEvent) {
        guard image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        dragOrigin = point
        selection = CGRect(origin: point, size: .zero)
        updateSelectionLayer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        selection = CGRect(x: min(dragOrigin.x, point.x), y: min(dragOrigin.y, point.y),
                           width: abs(point.x - dragOrigin.x), height: abs(point.y - dragOrigin.y))
        updateSelectionLayer()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        dragOrigin = nil
    }

    func clearSelection() { selection = .zero; updateSelectionLayer() }

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

    private func updateSelectionLayer() {
        selectionLayer.path = selection.isEmpty ? nil : CGPath(rect: selection, transform: nil)
    }
}
