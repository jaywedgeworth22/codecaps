// Generates the CodeCaps app icon — full-bleed square master, no rounded
// corners baked in.  iOS / App Store Connect applies its own squircle mask at
// display time; macOS before 26 does not, so a square master is shaped into
// the macOS form by `script/make_icon.swift`.
//
// Produces two files:
//   assets/icon-1024.png            — opaque (RGB, no alpha), the iOS source
//   assets/icon-1024-transparent.png — RGBA with transparent background;
//                                      the mark itself stays opaque white
//                                      so it composites cleanly on any
//                                      surface that wants to layer it
//
// usage: swift script/make_codecaps_icon.swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: Int = 1024

// Brand teal — same hex as `Theme.accent` in light mode (QuotaCore Theme.swift).
// 0x087370 = R8 G115 B112.  iOS renders the dark form of the brand colour
// more reliably than the bright form in the App Store grid, so this is the
// master.
let brandTeal = NSColor(srgbRed: 0x08 / 255.0,
                        green: 0x73 / 255.0,
                        blue: 0x70 / 255.0,
                        alpha: 1.0)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make_codecaps_icon: \(message)\n".utf8))
    exit(1)
}

func writePNG(cgImage: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                              UTType.png.identifier as CFString,
                                                              1,
                                                              nil) else {
        fail("could not create PNG destination: \(url.path)")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    if !CGImageDestinationFinalize(destination) {
        fail("could not finalize PNG: \(url.path)")
    }
}

/// Draws the CodeCaps mark into `context` centred on a 1024×1024 canvas.  The
/// mark is a bold "C" whose right-hand opening is closed by a small bracket
/// (the "code" cap).  Drawn entirely with `CGContext` calls — no rounded
/// corners on the background plate or the mark's outer geometry, so the
/// master is a true square; iOS applies the squircle mask itself.
///
/// The mark is built by simple stacking, not by a single even-odd path:
///   1. Background plate (full bleed, only when backgroundAlpha > 0).
///   2. Big white disk centred on the plate — the C body.
///   3. Smaller disk inside it, coloured to match the plate — creates the
///      C ring's inner hole.  When the plate is transparent, the hole is
///      also transparent so the mark composites cleanly on any surface.
///   4. Wedge on the right covering both disks — creates the C opening.
///      Same colour rule as step 3.
///   5. White "cap" square in the right-hand opening — the code-cap accent.
///
/// Stacking reads correctly at every size and avoids the path-winding
/// ambiguity that bites a single even-odd path at small radii.
func drawMark(in context: CGContext, size: Int, backgroundAlpha: CGFloat) {
    let s = CGFloat(size)
    let frame = CGRect(x: 0, y: 0, width: s, height: s)

    // 1. Background plate.  Full bleed.  No corner radius.  For the
    //    transparent variant we explicitly clear the canvas to fully
    //    transparent (alpha 0) because a fill with `setFillColor(...,0)`
    //    on a premultiplied bitmap context does not actually erase — it
    //    paints transparent pixels over the existing pixels, which the
    //    compositing pass then treats as a no-op.
    if backgroundAlpha > 0 {
        context.setFillColor(brandTeal.withAlphaComponent(backgroundAlpha).cgColor)
        context.fill(frame)
    } else {
        context.clear(frame)
    }

    // Geometry constants — measured as fractions of the canvas so a future
    // change to the size keeps the proportions intact.
    let inset: CGFloat = s * 0.16
    let markCentre = CGPoint(x: s * 0.50, y: s * 0.52)
    let outerRadius = (s - inset * 2) * 0.5
    let innerRadius = outerRadius * 0.62

    // 2. Big white disk — the C body.
    context.setFillColor(NSColor.white.cgColor)
    context.fillEllipse(in: CGRect(x: markCentre.x - outerRadius,
                                   y: markCentre.y - outerRadius,
                                   width: outerRadius * 2,
                                   height: outerRadius * 2))

    // 3. Inner "hole" matching the plate's transparency.  For the opaque
    //    variant, draw the brand teal disk; for the transparent variant,
    //    erase with `clear` so the host surface shows through.
    let holeRect = CGRect(x: markCentre.x - innerRadius,
                          y: markCentre.y - innerRadius,
                          width: innerRadius * 2,
                          height: innerRadius * 2)
    if backgroundAlpha > 0 {
        context.setFillColor(brandTeal.cgColor)
        context.fillEllipse(in: holeRect)
    } else {
        context.clear(holeRect)
    }

    // 4. Wedge covering the C opening — a rectangle wide enough to span both
    //    disks plus the cap.  Anchored to the right edge of the plate.
    let wedgeWidth = outerRadius * 0.55
    let wedgeRect = CGRect(x: markCentre.x + outerRadius - wedgeWidth * 0.30,
                           y: markCentre.y - outerRadius,
                           width: wedgeWidth,
                           height: outerRadius * 2)
    if backgroundAlpha > 0 {
        context.setFillColor(brandTeal.cgColor)
        context.fill(wedgeRect)
    } else {
        context.clear(wedgeRect)
    }

    // 5. White "cap" square — sits inside the right-hand opening, sized so it
    //    reads as a terminal caret at small sizes.  Anchored to the right
    //    edge of the outer disk.
    let capSize = outerRadius * 0.42
    let capInset = outerRadius * 0.18
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: markCentre.x + outerRadius - capInset - capSize,
                        y: markCentre.y - capSize / 2,
                        width: capSize,
                        height: capSize))
}

// Build the opaque (RGB) master.
let opaqueSpace = CGColorSpaceCreateDeviceRGB()
guard let opaqueContext = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: opaqueSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fail("could not create opaque context") }
drawMark(in: opaqueContext, size: canvas, backgroundAlpha: 1.0)
guard let opaqueImage = opaqueContext.makeImage() else { fail("opaque makeImage failed") }
let opaqueURL = URL(fileURLWithPath: "assets/icon-1024.png")
writePNG(cgImage: opaqueImage, to: opaqueURL)

// Build the transparent (RGBA) variant.  Same mark, no plate.
let transparentSpace = CGColorSpaceCreateDeviceRGB()
guard let transparentContext = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: transparentSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("could not create transparent context") }
drawMark(in: transparentContext, size: canvas, backgroundAlpha: 0.0)
guard let transparentImage = transparentContext.makeImage() else { fail("transparent makeImage failed") }
let transparentURL = URL(fileURLWithPath: "assets/icon-1024-transparent.png")
writePNG(cgImage: transparentImage, to: transparentURL)

print("wrote \(opaqueURL.path) (\(opaqueImage.width)x\(opaqueImage.height), RGB)")
print("wrote \(transparentURL.path) (\(transparentImage.width)x\(transparentImage.height), RGBA)")
