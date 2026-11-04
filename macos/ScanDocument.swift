import AppKit
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ScanDocument {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScanDocumentError("The scanner returned an image macOS could not open.")
        }
        return image
    }

    static func rotate(_ image: CGImage, degrees: CGFloat) throws -> CGImage {
        let radians = degrees * .pi / 180
        let rotated = CIImage(cgImage: image).transformed(by: CGAffineTransform(rotationAngle: radians))
        let extent = rotated.extent.integral
        let normalized = rotated.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let background = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: extent.size))
        let flattened = normalized.composited(over: background)
        guard let result = ciContext.createCGImage(flattened, from: CGRect(origin: .zero, size: extent.size)) else {
            throw ScanDocumentError("macOS could not rotate this scan.")
        }
        return result
    }

    static func crop(_ image: CGImage, rectInImage: CGRect) throws -> CGImage {
        let rect = rectInImage.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 32, rect.height >= 32, let cropped = image.cropping(to: rect) else {
            throw ScanDocumentError("Select a larger area to crop.")
        }
        return cropped
    }

    static func deskewAngle(_ image: CGImage) throws -> CGFloat? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let points = (request.results ?? []).map {
            CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY)
        }
        guard points.count >= 3 else { return nil }
        let meanX = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let meanY = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let covariance = points.reduce(CGFloat.zero) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let variance = points.reduce(CGFloat.zero) { $0 + pow($1.x - meanX, 2) }
        guard variance > 0 else { return nil }
        let angle = atan(covariance / variance) * 180 / .pi
        guard abs(angle) >= 0.15, abs(angle) <= 7 else { return nil }
        return -angle
    }

    static func writePNG(_ image: CGImage, to url: URL, dpi: Int) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ScanDocumentError("That file already exists. Choose a new filename.")
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ScanDocumentError("macOS could not create the PNG file.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ScanDocumentError("macOS could not finish saving the PNG file.")
        }
    }

    static func writePDF(
        pages: [URL],
        to url: URL,
        dpi: Int,
        searchable: Bool,
        progress: @escaping (Int, String) -> Void
    ) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ScanDocumentError("That file already exists. Choose a new filename.")
        }
        guard !pages.isEmpty else { throw ScanDocumentError("Scan at least one page before saving the PDF.") }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw ScanDocumentError("macOS could not create the PDF file.")
        }
        var completed = false
        defer {
            context.closePDF()
            if !completed { try? FileManager.default.removeItem(at: url) }
        }

        for (index, pageURL) in pages.enumerated() {
            let image = try loadImage(pageURL)
            let pageSize = CGSize(width: CGFloat(image.width) * 72 / CGFloat(dpi),
                                  height: CGFloat(image.height) * 72 / CGFloat(dpi))
            let pageBox = CGRect(origin: .zero, size: pageSize)
            context.beginPDFPage([kCGPDFContextMediaBox as String: pageBox] as CFDictionary)
            context.draw(image, in: pageBox)
            if searchable {
                progress(index, "Reading text on page \(index + 1) of \(pages.count)…")
                try drawSearchableText(from: image, in: context, pageSize: pageSize)
            }
            context.endPDFPage()
            progress(index + 1, searchable ? "Building PDF…" : "Adding page \(index + 1) of \(pages.count)…")
        }
        completed = true
    }

    private static func drawSearchableText(from image: CGImage, in context: CGContext, pageSize: CGSize) throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for observation in request.results ?? [] {
            guard let recognized = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            let fontSize = max(4, box.height * pageSize.height * 0.72)
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: recognized.string, attributes: attributes))
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let targetWidth = max(1, box.width * pageSize.width)
            let horizontalScale = naturalWidth > 0 ? min(3, max(0.5, targetWidth / naturalWidth)) : 1
            context.saveGState()
            context.translateBy(x: box.minX * pageSize.width, y: box.minY * pageSize.height)
            context.scaleBy(x: horizontalScale, y: 1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
        context.restoreGState()
    }
}

struct ScanDocumentError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
