import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("usage: build-app-icon.swift source.png iconset-directory")
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let sizes = [16, 32, 128, 256, 512]

for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("could not create \(pixels)x\(pixels) icon")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                    from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let scaleSuffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(scaleSuffix).png")
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("could not encode \(pixels)x\(pixels) icon")
        }
        try data.write(to: file, options: .atomic)
    }
}
