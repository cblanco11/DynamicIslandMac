import AppKit

/// Picks a tint from artwork.
///
/// A plain average is muddy -- most covers average to grey-brown. This
/// downsamples hard, discards pixels too dark, too pale or too washed out to
/// read as a colour, then scores what remains by how much of the image it covers
/// *and* how saturated it is, so a small vivid accent can beat a large dull
/// background. Falls back to a neutral when a cover genuinely has no colour.
enum ArtworkColor {

    static let fallback = NSColor(white: 0.72, alpha: 1)

    static func dominant(in data: Data) -> NSColor {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return fallback }
        return dominant(in: cg)
    }

    static func dominant(in cg: CGImage) -> NSColor {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallback }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Bucket by coarse hue so near-identical shades reinforce each other.
        var buckets: [Int: (count: Int, h: Double, s: Double, b: Double)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let bl = Double(pixels[i + 2]) / 255
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.5 else { continue }

            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            NSColor(srgbRed: r, green: g, blue: bl, alpha: 1)
                .getHue(&h, saturation: &s, brightness: &v, alpha: nil)

            // Too dark, blown out, or effectively greyscale: carries no tint.
            guard v > 0.20, v < 0.97, s > 0.18 else { continue }

            let key = Int((h * 24).rounded()) % 24
            var entry = buckets[key] ?? (0, 0, 0, 0)
            entry.count += 1
            entry.h += Double(h); entry.s += Double(s); entry.b += Double(v)
            buckets[key] = entry
        }

        guard let best = buckets.max(by: { a, b in
            let sa = Double(a.value.count) * (a.value.s / Double(a.value.count))
            let sb = Double(b.value.count) * (b.value.s / Double(b.value.count))
            return sa < sb
        })?.value, best.count > 0 else { return fallback }

        let n = Double(best.count)
        // Everything this tints is drawn on black, so brightness has a hard
        // floor: the cover's own brightness is irrelevant to legibility, and a
        // dark album makes an unreadable progress bar. Saturation is lifted a
        // little so the tint still reads as the record's colour.
        return NSColor(
            hue: CGFloat(best.h / n),
            saturation: min(CGFloat(best.s / n) * 1.20, 1.0),
            brightness: max(min(CGFloat(best.b / n) * 1.25, 0.95), 0.70),
            alpha: 1
        )
    }
}
