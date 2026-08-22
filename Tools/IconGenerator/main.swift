//
//  main.swift — ClaudeCollage app-icon generator
//
//  Step 05b Part A. The icon is authored as CoreGraphics drawing code rather
//  than a hand-drawn bitmap so it is genuinely resolution-independent: the same
//  routine emits the PDF vector master and every PNG the asset catalog needs,
//  which means there is exactly one definition of the artwork and no chance of
//  the master and the rendered sizes drifting apart.
//
//  Usage (macOS, run with the Xcode toolchain):
//    swift Tools/IconGenerator/main.swift preview <outDir>
//        renders every candidate at 1024, 180 and 40 pt for legibility checks
//    swift Tools/IconGenerator/main.swift install <candidate> <appiconsetDir>
//        writes the chosen candidate's light/dark/tinted PNGs + Contents.json
//    swift Tools/IconGenerator/main.swift master <candidate> <out.pdf>
//        writes the scalable vector master
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Brand

/// The icon palette is the app's own accent ramp, not a separate set of oranges:
/// `Theme.Color.accentSecondary` (#F29B3C) → `Theme.Color.accentPressed`
/// (#CC5716), which brackets `accent` (#E86A2A). Keeping the icon inside the ramp
/// is what makes the home screen and the app read as one product.
enum Brand {
    static let warm = rgb(0xF2_9B3C)
    static let mid = rgb(0xE8_6A2A)
    static let deep = rgb(0xCC_5716)
    static let white = CGColor(gray: 1, alpha: 1)
    static let paper = rgb(0xFF_FBF7)

    static func rgb(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Which of the three iOS 18 icon appearances is being drawn.
///
/// Apple composites the dark and tinted variants over a system-supplied
/// backdrop, so those two are drawn with a transparent ground; only the default
/// appearance paints its own background.
enum Variant: String, CaseIterable {
    case light, dark, tinted
}

/// The four ink roles every candidate draws with. Swapping the palette — rather
/// than branching inside each candidate — is what keeps the three appearances
/// pixel-identical in geometry and different only in colour.
struct Palette {
    /// Full-bleed background gradient; `nil` means transparent.
    var ground: [CGColor]?
    /// The large card / panel surfaces.
    var card: CGColor
    /// The photo cells inside the cards.
    var cell: [CGColor]
    /// Receding cards and inactive carousel dots.
    var ghostAlpha: CGFloat
    /// True when the artwork sits on its own painted ground and can therefore
    /// carry a shadow. Shadows on a transparent ground print as grey haze.
    var shadows: Bool
}

// MARK: - Geometry helpers

extension CGContext {
    func addRoundedRect(_ rect: CGRect, radius: CGFloat) {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        addPath(path)
    }

    func fill(roundedRect rect: CGRect, radius: CGFloat, color: CGColor) {
        setFillColor(color)
        addRoundedRect(rect, radius: radius)
        fillPath()
    }

    /// Fills a rounded rect with a linear gradient running top-leading →
    /// bottom-trailing, the same direction `Theme.Color.brandGradient` uses.
    func fill(roundedRect rect: CGRect, radius: CGFloat, gradient colors: [CGColor]) {
        guard colors.count > 1 else {
            fill(roundedRect: rect, radius: radius, color: colors[0])
            return
        }
        saveGState()
        addRoundedRect(rect, radius: radius)
        clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let stops: [CGFloat] = colors.enumerated().map { CGFloat($0.offset) / CGFloat(colors.count - 1) }
        if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops) {
            drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        restoreGState()
    }

    func withShadow(_ enabled: Bool, blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ body: () -> Void) {
        saveGState()
        if enabled {
            setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: CGColor(gray: 0, alpha: alpha))
        }
        body()
        restoreGState()
    }

    /// Runs `body` with the origin moved to `center` and the canvas rotated.
    func rotated(around center: CGPoint, degrees: CGFloat, _ body: () -> Void) {
        saveGState()
        translateBy(x: center.x, y: center.y)
        rotate(by: degrees * .pi / 180)
        translateBy(x: -center.x, y: -center.y)
        body()
        restoreGState()
    }
}

// MARK: - The candidates

/// The three motifs put to the owner. All three say "collage + carousel"; they
/// differ in which half of the orange-and-white identity leads.
enum Candidate: Int, CaseIterable {
    /// Orange-led. A fan of photo cards; the front card's face is a collage grid.
    case fan = 1
    /// Orange-led. A white asymmetric collage grid over a carousel dot row.
    case gridDots = 2
    /// White-led. An orange collage grid with the next page peeking in from the edge.
    case paperGrid = 3

    var name: String {
        switch self {
        case .fan: "fan"
        case .gridDots: "grid-dots"
        case .paperGrid: "paper-grid"
        }
    }

    func palette(_ variant: Variant) -> Palette {
        switch (self, variant) {
        case (.paperGrid, .light):
            Palette(ground: [Brand.paper, Brand.rgb(0xFF_F0E4)], card: Brand.white,
                    cell: [Brand.warm, Brand.deep], ghostAlpha: 0.42, shadows: true)
        case (_, .light):
            Palette(ground: [Brand.warm, Brand.deep], card: Brand.white,
                    cell: [Brand.warm, Brand.mid], ghostAlpha: 0.45, shadows: true)

        // Dark: no ground of our own. The white cards carry the shape and the
        // orange cells carry the brand, so the mark still reads as itself.
        case (.gridDots, .dark), (.paperGrid, .dark):
            Palette(ground: nil, card: Brand.white,
                    cell: [Brand.warm, Brand.mid], ghostAlpha: 0.40, shadows: false)
        case (.fan, .dark):
            Palette(ground: nil, card: Brand.white,
                    cell: [Brand.warm, Brand.deep], ghostAlpha: 0.35, shadows: false)

        // Tinted: greyscale on transparent; iOS applies the user's hue to the
        // luminance, so the only job here is a clean light/dark separation.
        case (_, .tinted):
            Palette(ground: nil, card: CGColor(gray: 1, alpha: 1),
                    cell: [CGColor(gray: 0.62, alpha: 1), CGColor(gray: 0.62, alpha: 1)],
                    ghostAlpha: 0.40, shadows: false)
        }
    }

    /// Draws the icon into a 1024×1024 CoreGraphics box (y-up).
    func draw(in ctx: CGContext, variant: Variant) {
        let s: CGFloat = 1024
        let bounds = CGRect(x: 0, y: 0, width: s, height: s)
        let p = palette(variant)

        if let ground = p.ground {
            ctx.fill(roundedRect: bounds, radius: 0, gradient: ground)
        }

        switch self {
        case .fan: drawFan(ctx, p)
        case .gridDots: drawGridDots(ctx, p)
        case .paperGrid: drawPaperGrid(ctx, p)
        }
    }

    // MARK: candidate 1 — fan

    private func drawFan(_ ctx: CGContext, _ p: Palette) {
        let card = CGSize(width: 404, height: 516)
        let radius: CGFloat = 58
        let front = CGRect(
            x: 512 - card.width / 2, y: 520 - card.height / 2,
            width: card.width, height: card.height
        )

        // Two siblings fanned out from behind the front card, rotated about a
        // shared pivot just below the stack — the way a hand of cards fans.
        // Pivoting at each card's own centre instead splays the bottom corners
        // outward and the deck reads as a tent.
        let pivot = CGPoint(x: 512, y: front.minY + 18)
        for degrees in [-15.0 as CGFloat, 15] {
            let sibling = front.insetBy(dx: 12, dy: 12)
            ctx.rotated(around: pivot, degrees: degrees) {
                ctx.fill(roundedRect: sibling, radius: radius,
                         color: p.card.copy(alpha: p.ghostAlpha) ?? p.card)
            }
        }

        // The front card, carrying a collage on its face.
        ctx.withShadow(p.shadows, blur: 44, dy: 14, alpha: 0.22) {
            ctx.fill(roundedRect: front, radius: radius, color: p.card)
        }
        drawCollage(ctx, in: front.insetBy(dx: 46, dy: 46), gap: 18, radius: 20, gradient: p.cell)
    }

    // MARK: candidate 2 — grid + dots

    private func drawGridDots(_ ctx: CGContext, _ p: Palette) {
        let block = CGRect(x: 202, y: 300, width: 620, height: 560)
        ctx.withShadow(p.shadows, blur: 36, dy: 12, alpha: 0.18) {
            // On the painted orange ground the grid is white; with no ground of
            // our own (dark/tinted) it takes the cell ink, so the mark never
            // arrives as an all-white silhouette with the brand drained out.
            drawCollage(ctx, in: block, gap: 40, radius: 52,
                        gradient: p.ground == nil ? p.cell : [p.card, p.card])
        }

        // Carousel dots: the middle one elongated, the way a page indicator marks
        // the current page. Three states of the same control, not decoration.
        let y: CGFloat = 190
        let dot: CGFloat = 38
        let ink = p.ground == nil ? p.cell[1] : p.card
        let ghost = ink.copy(alpha: p.ghostAlpha) ?? ink
        ctx.fill(roundedRect: CGRect(x: 512 - 128, y: y - dot / 2, width: dot, height: dot),
                 radius: dot / 2, color: ghost)
        ctx.fill(roundedRect: CGRect(x: 512 - 58, y: y - dot / 2, width: 116, height: dot),
                 radius: dot / 2, color: ink)
        ctx.fill(roundedRect: CGRect(x: 512 + 94, y: y - dot / 2, width: dot, height: dot),
                 radius: dot / 2, color: ghost)
    }

    // MARK: candidate 3 — paper grid

    private func drawPaperGrid(_ ctx: CGContext, _ p: Palette) {
        // The next page, running off the trailing edge — the cheapest possible
        // way to say "there is more, swipe" without drawing an arrow.
        let peek = CGRect(x: 772, y: 300, width: 352, height: 424)
        ctx.fill(roundedRect: peek, radius: 60,
                 color: p.cell[0].copy(alpha: p.ghostAlpha) ?? p.cell[0])

        let block = CGRect(x: 122, y: 252, width: 568, height: 520)
        ctx.withShadow(p.shadows, blur: 40, dy: 14, alpha: 0.14) {
            drawCollage(ctx, in: block, gap: 32, radius: 50, gradient: p.cell)
        }
    }

    // MARK: shared motif

    /// The app's signature asymmetric three-cell collage: one tall cell leading,
    /// two stacked trailing. Used at two scales — as the whole mark and as the
    /// face of a card — so the icon repeats one idea instead of inventing two.
    private func drawCollage(
        _ ctx: CGContext, in rect: CGRect, gap: CGFloat, radius: CGFloat, gradient: [CGColor]
    ) {
        let leftWidth = (rect.width - gap) * 0.46
        let rightWidth = rect.width - gap - leftWidth
        let rightHeight = (rect.height - gap) / 2

        let left = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
        let topRight = CGRect(x: rect.minX + leftWidth + gap, y: rect.minY + rightHeight + gap,
                              width: rightWidth, height: rightHeight)
        let bottomRight = CGRect(x: rect.minX + leftWidth + gap, y: rect.minY,
                                 width: rightWidth, height: rightHeight)

        for cell in [left, topRight, bottomRight] {
            ctx.fill(roundedRect: cell, radius: radius, gradient: gradient)
        }
    }
}

// MARK: - Rendering

func makeBitmap(_ size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw Err("cannot create \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw Err("cannot write \(url.path)") }
}

func render(_ candidate: Candidate, _ variant: Variant, size: Int) -> CGImage {
    let ctx = makeBitmap(size)
    candidate.draw(in: ctx, variant: variant)
    return ctx.makeImage()!
}

struct Err: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: - Asset catalog

/// The iOS 17+ single-size layout: one 1024 image per appearance. Xcode expands
/// it to every device size at build time, so there is nothing else to keep in sync.
func contentsJSON(prefix: String) -> String {
    """
    {
      "images" : [
        {
          "filename" : "\(prefix)-light-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "dark"
            }
          ],
          "filename" : "\(prefix)-dark-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "tinted"
            }
          ],
          "filename" : "\(prefix)-tinted-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
}

// MARK: - Entry point

let args = CommandLine.arguments
func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard args.count >= 3 else {
    die("usage: main.swift preview <outDir> | install <candidate> <appiconsetDir> | master <candidate> <out.pdf>")
}

let fm = FileManager.default

switch args[1] {
case "preview":
    let out = URL(fileURLWithPath: args[2])
    try fm.createDirectory(at: out, withIntermediateDirectories: true)
    for candidate in Candidate.allCases {
        for size in [1024, 180, 40] {
            let image = render(candidate, .light, size: size)
            try writePNG(image, to: out.appendingPathComponent("\(candidate.rawValue)-\(candidate.name)-\(size).png"))
        }
        for variant in [Variant.dark, .tinted] {
            let image = render(candidate, variant, size: 512)
            try writePNG(image, to: out.appendingPathComponent("\(candidate.rawValue)-\(candidate.name)-\(variant.rawValue)-512.png"))
        }
    }
    print("wrote previews to \(out.path)")

case "install":
    guard let raw = Int(args[2]), let candidate = Candidate(rawValue: raw) else {
        die("unknown candidate \(args[2])")
    }
    let dir = URL(fileURLWithPath: args[3])
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for variant in Variant.allCases {
        let image = render(candidate, variant, size: 1024)
        try writePNG(image, to: dir.appendingPathComponent("icon-\(variant.rawValue)-1024.png"))
    }
    try contentsJSON(prefix: "icon").write(
        to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
    )
    print("installed candidate \(candidate.name) into \(dir.path)")

case "master":
    guard let raw = Int(args[2]), let candidate = Candidate(rawValue: raw) else {
        die("unknown candidate \(args[2])")
    }
    let url = URL(fileURLWithPath: args[3])
    var box = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { die("cannot open \(url.path)") }
    ctx.beginPDFPage(nil)
    candidate.draw(in: ctx, variant: .light)
    ctx.endPDFPage()
    ctx.closePDF()
    print("wrote vector master to \(url.path)")

default:
    die("unknown command \(args[1])")
}
