// Generates the app and document icons.
//
// Run with `make icons`, which writes `Packaging/AppIcon.icns`,
// `Packaging/MarkdownDocument.icns` and the iOS app icon. The results are
// committed, so a normal build does not need to run this.
//
// The app icon is `Packaging/Logo.svg` — the kirupa mark — on white. The
// document icon is drawn with Core Graphics. Nothing here needs an asset
// pipeline or a design tool: AppKit rasterises the SVG and `iconutil` packs
// the result, and both ship with macOS.

import AppKit
import Foundation

let brand = NSColor(srgbRed: 0x07 / 255, green: 0x98 / 255, blue: 0xFF / 255, alpha: 1)

func makeBitmap(size: Int, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    representation.size = NSSize(width: size, height: size)

    let context = NSGraphicsContext(bitmapImageRep: representation)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.interpolationQuality = .high
    draw(context.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()

    return representation
}

/// The kirupa mark, and the round body a reader centres it by.
struct Logo {
    let image: NSImage
    /// The round body's bounds as fractions of the image, y measured from the
    /// bottom. What the icon is sized and centred on.
    let anchor: NSRect

    /// Draws the mark so its **round body** is centred in `rect`, with that
    /// body's diameter `fill` of the rect.
    ///
    /// The body rather than the whole artwork, because the body is the mark.
    /// The leaves are an accent sticking out of it at one corner, and sizing or
    /// centring by them makes the round part — the part the eye settles on —
    /// sit small and off to one side. Place the icon as though the leaves were
    /// not there, and let them overhang.
    ///
    /// `anchor` is found from the dark ring, and that is the whole body rather
    /// than a part of it: measured, the ring and the orange inside it are
    /// concentric and their bounds agree to within the orange's one-pixel
    /// antialiased fringe — 93…459 against 94…458, both centred on (0.540,
    /// 0.520). There is no third thing to reconcile; the ring's bounds *are*
    /// the round area's bounds.
    ///
    /// Two corrections were tried against this and both were wrong, which is
    /// worth knowing before trying them again. The ring is not closed — the
    /// leaves cross it and leave a 40° gap from 9 to 11 o'clock — so its dark
    /// pixels weigh more to the lower right, and centring on that weight drags
    /// the mark up and left until the leaves crowd the plate's corner and an
    /// empty quarter opens opposite. Balancing only the ink the circle encloses
    /// is the gentler version of the same idea and still lifts the mark off
    /// centre. Both start from the premise that the gap is an error to correct
    /// for. It is not: the gap is where the accent sits, and the round area
    /// under it is already where it belongs.
    func draw(in rect: NSRect, fill: CGFloat) {
        let side = rect.width * fill / max(anchor.width, anchor.height)
        let origin = NSPoint(
            x: rect.midX - anchor.midX * side,
            y: rect.midY - anchor.midY * side
        )
        image.draw(
            in: NSRect(origin: origin, size: NSSize(width: side, height: side)),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
    }
}

/// The rounded-rectangle app icon: the kirupa mark on a white plate, inset to
/// match the macOS icon grid.
func drawAppIcon(_ context: CGContext, _ size: CGFloat, logo: Logo) {
    let inset = size * 0.086
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.2237
    let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    context.saveGState()
    path.addClip()
    NSColor.white.setFill()
    plate.fill()
    context.restoreGState()

    logo.draw(in: plate, fill: 0.66)
}

/// The logo, read from the SVG beside the icons it is drawn into.
///
/// AppKit rasterises SVG itself — `NSImage` hands back an `_NSSVGImageRep`,
/// which redraws at whatever size it is asked for — so the 16pt icon and the
/// 512@2x one are both drawn from the vector rather than resampled from one
/// bitmap. That is the whole reason the source art is an SVG here and not a
/// PNG: this script renders ten sizes spanning 16 to 1024 pixels.
func loadLogo(from directory: URL) throws -> Logo {
    let url = directory.appendingPathComponent("Logo.svg")
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(
            domain: "make-icons",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "No logo at \(url.path)"]
        )
    }
    return Logo(image: image, anchor: bodyBounds(of: image))
}

/// Where the mark's round body sits inside its own square, as fractions of
/// that square, y measured from the bottom.
///
/// Found from the dark outline, which bounds the body exactly — see
/// `Logo.draw(in:fill:)`.
///
/// Measured rather than written down. The artwork is neither centred in its
/// viewBox nor filling it, so every number here would otherwise be a constant
/// nobody could check — and the next mark dropped in would need all of them
/// re-derived by hand.
///
/// The outline is found as ink that is dark **and** near-neutral. Dark alone
/// does not do it: the leaves are `#008000`, which is darker than the
/// `#333333` ring, so a brightness test alone drags the box back out to the
/// top-left corner. Saturation is what separates a drawn outline from coloured
/// artwork.
///
/// Measured on this logo the body comes back 0.713 square, centred at (0.540,
/// 0.520) — against (0.489, 0.484) for the bounding box of everything drawn.
/// That gap of about a twentieth of the icon is the visible lean this exists to
/// remove: the leaves are what pull the second number up and left, and they are
/// precisely what should not be counted.
///
/// Falls back to every non-white pixel when a mark has no such outline. White
/// is not ink either way: this logo carries a white halo and a white disc that
/// are invisible on a white plate, and counting them reserves room for
/// something nobody can see.
func bodyBounds(of image: NSImage) -> NSRect {
    let probe = 512
    let rep = makeBitmap(size: probe) { _, size in
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
    }

    var outline = Box(), ink = Box()
    for y in 0..<probe {
        for x in 0..<probe {
            guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.5
            else { continue }
            let highest = max(colour.redComponent, max(colour.greenComponent, colour.blueComponent))
            let lowest = min(colour.redComponent, min(colour.greenComponent, colour.blueComponent))
            guard highest < 0.97 || lowest < 0.97 else { continue }
            ink.add(x: x, y: y)

            let saturation = highest > 0 ? (highest - lowest) / highest : 0
            if saturation < 0.25, highest < 0.45 {
                outline.add(x: x, y: y)
            }
        }
    }

    return (outline.isEmpty ? ink : outline).normalized(in: probe)
}

/// A bounding box accumulated a pixel at a time, in top-down image rows.
struct Box {
    private var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1

    var isEmpty: Bool { maxX < minX }

    mutating func add(x: Int, y: Int) {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }

    /// As fractions of a `side`-pixel square, with y flipped to run from the
    /// bottom — `colorAt` counts rows from the top, and drawing does not.
    func normalized(in side: Int) -> NSRect {
        guard !isEmpty else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
        let side = CGFloat(side)
        return NSRect(
            x: CGFloat(minX) / side,
            y: (side - 1 - CGFloat(maxY)) / side,
            width: CGFloat(maxX - minX + 1) / side,
            height: CGFloat(maxY - minY + 1) / side
        )
    }
}

/// The document icon: a white page with a folded corner, a few text rules, and
/// a brand-colored MD badge.
func drawDocumentIcon(_ context: CGContext, _ size: CGFloat) {
    let width = size * 0.68
    let height = size * 0.84
    let page = NSRect(
        x: (size - width) / 2,
        y: (size - height) / 2,
        width: width,
        height: height
    )
    let fold = width * 0.26
    let corner = width * 0.035

    let outline = NSBezierPath()
    outline.move(to: NSPoint(x: page.minX + corner, y: page.minY))
    outline.line(to: NSPoint(x: page.maxX - corner, y: page.minY))
    outline.curve(
        to: NSPoint(x: page.maxX, y: page.minY + corner),
        controlPoint1: NSPoint(x: page.maxX, y: page.minY),
        controlPoint2: NSPoint(x: page.maxX, y: page.minY)
    )
    outline.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    outline.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    outline.line(to: NSPoint(x: page.minX + corner, y: page.maxY))
    outline.curve(
        to: NSPoint(x: page.minX, y: page.maxY - corner),
        controlPoint1: NSPoint(x: page.minX, y: page.maxY),
        controlPoint2: NSPoint(x: page.minX, y: page.maxY)
    )
    outline.line(to: NSPoint(x: page.minX, y: page.minY + corner))
    outline.curve(
        to: NSPoint(x: page.minX + corner, y: page.minY),
        controlPoint1: NSPoint(x: page.minX, y: page.minY),
        controlPoint2: NSPoint(x: page.minX, y: page.minY)
    )
    outline.close()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.008),
        blur: size * 0.02,
        color: NSColor(white: 0, alpha: 0.22).cgColor
    )
    NSColor.white.setFill()
    outline.fill()
    context.restoreGState()

    NSColor(white: 0.80, alpha: 1).setStroke()
    outline.lineWidth = max(1, size * 0.004)
    outline.stroke()

    // The turned-down corner.
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    flap.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
    flap.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    flap.close()
    NSColor(white: 0.90, alpha: 1).setFill()
    flap.fill()
    NSColor(white: 0.80, alpha: 1).setStroke()
    flap.lineWidth = max(1, size * 0.004)
    flap.stroke()

    // Text rules, shortest last so the block reads as a paragraph.
    let ruleHeight = height * 0.030
    let ruleGap = height * 0.062
    let ruleLeft = page.minX + width * 0.14
    let ruleWidths: [CGFloat] = [0.72, 0.60, 0.68, 0.44]
    NSColor(white: 0.82, alpha: 1).setFill()
    for (index, fraction) in ruleWidths.enumerated() {
        let rule = NSRect(
            x: ruleLeft,
            y: page.maxY - fold - height * 0.10 - CGFloat(index) * ruleGap,
            width: width * fraction,
            height: ruleHeight
        )
        NSBezierPath(
            roundedRect: rule,
            xRadius: ruleHeight / 2,
            yRadius: ruleHeight / 2
        ).fill()
    }

    // Brand badge.
    let badgeHeight = height * 0.24
    let badge = NSRect(
        x: page.minX + width * 0.14,
        y: page.minY + height * 0.10,
        width: width * 0.50,
        height: badgeHeight
    )
    brand.setFill()
    NSBezierPath(
        roundedRect: badge,
        xRadius: badgeHeight * 0.24,
        yRadius: badgeHeight * 0.24
    ).fill()

    let label = "MD"
    let font = NSFont.systemFont(ofSize: badgeHeight * 0.60, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let measured = label.size(withAttributes: attributes)
    label.draw(
        at: NSPoint(
            x: badge.midX - measured.width / 2,
            y: badge.midY - measured.height / 2
        ),
        withAttributes: attributes
    )
}

func writeIconSet(
    named name: String,
    into directory: URL,
    draw: @escaping (CGContext, CGFloat) -> Void
) throws {
    let iconset = directory.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    // (point size, scale) pairs required by iconutil.
    let variants: [(Int, Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
        (256, 1), (256, 2), (512, 1), (512, 2),
    ]
    for (points, scale) in variants {
        let pixels = points * scale
        let representation = makeBitmap(size: pixels, draw: draw)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "make-icons", code: 1)
        }
        let suffix = scale == 1 ? "" : "@\(scale)x"
        let file = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try data.write(to: file)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = [
        "--convert", "icns",
        "--output", directory.appendingPathComponent("\(name).icns").path,
        iconset.path,
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "iconutil", code: Int(process.terminationStatus))
    }

    try FileManager.default.removeItem(at: iconset)
    print("Wrote \(directory.appendingPathComponent("\(name).icns").path)")
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let logo = try loadLogo(from: destination)
try writeIconSet(named: "AppIcon", into: destination) { context, size in
    drawAppIcon(context, size, logo: logo)
}
try writeIconSet(named: "MarkdownDocument", into: destination, draw: drawDocumentIcon)

/// The iOS app icon.
///
/// Full-bleed and square: iOS applies its own rounded-rectangle mask and
/// shadow, so an icon that draws its own rounded plate the way the macOS one
/// does ends up with a visible double edge inside the system's corners.
func drawIOSAppIcon(_ context: CGContext, _ size: CGFloat, logo: Logo) {
    let plate = NSRect(x: 0, y: 0, width: size, height: size)

    NSColor.white.setFill()
    plate.fill()

    // Tighter than the Mac's 0.66 because this square has no plate inside
    // it: iOS rounds the corners off the artwork itself, so the same fraction
    // would put the mark hard against the visible edge.
    logo.draw(in: plate, fill: 0.51)
}

/// Writes the single 1024×1024 PNG an iOS asset catalog expects.
func writeIOSAppIcon(into appIconSet: URL, logo: Logo) throws {
    let representation = makeBitmap(size: 1024) { context, size in
        drawIOSAppIcon(context, size, logo: logo)
    }
    guard let data = representation.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "png", code: 1)
    }
    try FileManager.default.createDirectory(
        at: appIconSet, withIntermediateDirectories: true
    )
    let file = appIconSet.appendingPathComponent("AppIcon.png")
    try data.write(to: file)
    print("Wrote \(file.path)")
}

if CommandLine.arguments.count > 2 {
    try writeIOSAppIcon(
        into: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
        logo: logo
    )
}

/// The web icon: the same mark on the same white plate, written as an SVG.
///
/// Generated rather than hand-drawn, for the reason the bitmaps are. The plate
/// geometry and where the mark sits on it are one decision, and a second copy
/// of that decision in a hand-written file is a copy that will disagree — the
/// file this replaces still carried the old blue plate months after the Mac
/// icon had one drawn from constants.
///
/// Self-contained on purpose: a browser renders an SVG favicon in a restricted
/// mode that fetches no external resources, so the mark is inlined rather than
/// referenced. That also makes it usable as an `<img>` on the welcome screen,
/// which is how the web build reaches what macOS gets from
/// `NSImage.applicationIconName` — one icon in the tab, on the landing screen,
/// and on a home screen.
func writeWebIcon(into directory: URL, logo: Logo, source: URL) throws {
    let canvas: CGFloat = 64
    let inset = canvas * 0.086
    let plate = NSRect(
        x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2
    )

    // The arithmetic `Logo.draw` does, in SVG user units. `anchor` measures y
    // from the bottom and SVG measures it from the top, which is the one place
    // the two coordinate systems have to be reconciled by hand.
    let side = plate.width * 0.66 / max(logo.anchor.width, logo.anchor.height)
    let scale = side / logo.image.size.width
    let anchorX = logo.anchor.midX * logo.image.size.width
    let anchorY = (1 - logo.anchor.midY) * logo.image.size.height
    let x = canvas / 2 - anchorX * scale
    let y = canvas / 2 - anchorY * scale

    let markup = try String(contentsOf: source, encoding: .utf8)
    guard let openEnd = markup.range(of: ">"),
        let closeStart = markup.range(of: "</svg>", options: .backwards)
    else {
        throw NSError(
            domain: "make-icons",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "\(source.path) is not an SVG"]
        )
    }
    let inner = markup[openEnd.upperBound..<closeStart.lowerBound]
        .trimmingCharacters(in: .whitespacesAndNewlines)

    func round(_ value: CGFloat) -> String {
        String(format: "%.4g", value)
    }

    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" \
        xmlns:xlink="http://www.w3.org/1999/xlink" \
        viewBox="0 0 \(Int(canvas)) \(Int(canvas))" role="img" aria-label="Humanish">
        <!-- Generated by macOS/Scripts/make-icons.swift. Do not edit. -->
        <rect x="\(round(plate.minX))" y="\(round(plate.minY))" \
        width="\(round(plate.width))" height="\(round(plate.height))" \
        rx="\(round(plate.width * 0.2237))" fill="#FFFFFF"/>
        <g transform="translate(\(round(x)) \(round(y))) scale(\(round(scale)))">
        \(inner)
        </g>
        </svg>

        """

    let file = directory.appendingPathComponent("icon.svg")
    try svg.write(to: file, atomically: true, encoding: .utf8)
    print("Wrote \(file.path)")
}

if CommandLine.arguments.count > 3 {
    try writeWebIcon(
        into: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true),
        logo: logo,
        source: destination.appendingPathComponent("Logo.svg")
    )
}
