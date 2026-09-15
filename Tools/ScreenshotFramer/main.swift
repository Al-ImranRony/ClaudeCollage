//
//  ScreenshotFramer/main.swift
//  Caroullage — Step 06 phase 6.7
//
//  Turns a raw simulator screenshot into an App Store screenshot: the same
//  pixel size (App Store Connect wants the device's exact dimensions), an
//  off-white ground, the caption in the app's rounded bold face across the
//  top, and the screenshot inset below it with rounded corners and a soft
//  shadow. One caption per call; Tools/screenshots.sh loops the matrix.
//
//    swift Tools/ScreenshotFramer/main.swift <raw.png> <caption> <out.png>
//
//  macOS-only (AppKit for text); runs on the Mac that runs the simulator.
//

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("usage: main.swift <raw.png> <caption> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let rawURL = URL(fileURLWithPath: args[1])
let caption = args[2]
let outURL = URL(fileURLWithPath: args[3])

guard let raw = NSImage(contentsOf: rawURL),
      let rawRep = raw.representations.first as? NSBitmapImageRep else {
    FileHandle.standardError.write("cannot read \(rawURL.path)\n".data(using: .utf8)!)
    exit(1)
}
let width = rawRep.pixelsWide
let height = rawRep.pixelsHigh

// Geometry as fractions of the height, so a 6.9" iPhone and a 13" iPad compose alike.
let captionBand = Double(height) * 0.17          // the caption's room at the top
let inset = Double(width) * 0.075                 // side margin of the framed shot
let shotWidth = Double(width) - inset * 2
let shotHeight = shotWidth * Double(height) / Double(width)
let shotY = Double(height) - captionBand - shotHeight + Double(height) * 0.02   // bleeds off the bottom a little
let cornerRadius = Double(width) * 0.09

let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
canvas.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
let cg = NSGraphicsContext.current!.cgContext

// Ground: the app's off-white surface.
cg.setFillColor(CGColor(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF8 / 255, alpha: 1))
cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

// The shot, rounded, with a soft shadow.
let shotRect = CGRect(x: inset, y: shotY, width: shotWidth, height: shotHeight)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -Double(height) * 0.01), blur: Double(height) * 0.03,
             color: CGColor(gray: 0, alpha: 0.22))
cg.setFillColor(CGColor(gray: 1, alpha: 1))
cg.addPath(CGPath(roundedRect: shotRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
cg.fillPath()
cg.restoreGState()
cg.saveGState()
cg.addPath(CGPath(roundedRect: shotRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
cg.clip()
cg.draw(rawRep.cgImage!, in: shotRect)
cg.restoreGState()

// The caption: rounded bold, centred, up to two lines.
let fontSize = Double(height) * 0.036
let base = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: fontSize) ?? base
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.lineBreakMode = .byWordWrapping
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255, alpha: 1),
    .paragraphStyle: paragraph,
]
let textRect = CGRect(x: inset, y: Double(height) - captionBand + fontSize * 0.4,
                      width: shotWidth, height: captionBand - fontSize * 0.8)
NSAttributedString(string: caption, attributes: attributes)
    .draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

NSGraphicsContext.restoreGraphicsState()
guard let png = canvas.representation(using: .png, properties: [:]) else { exit(1) }
try! FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try! png.write(to: outURL)
