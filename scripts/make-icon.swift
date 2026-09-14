// Renders Resources/AppIcon.png (1024x1024): a dark rounded tile with a notch and three widget dots.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background tile (macOS squircle-ish)
let inset: CGFloat = size * 0.06
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.22, cornerHeight: tile.height * 0.22, transform: nil)
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Screen bezel
let screen = tile.insetBy(dx: tile.width * 0.13, dy: tile.height * 0.17)
ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.17, alpha: 1).cgColor)
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 60, cornerHeight: 60, transform: nil))
ctx.fillPath()

// Notch hanging from the top of the screen
let notchW = screen.width * 0.42
let notchH = screen.height * 0.16
let notch = CGRect(x: screen.midX - notchW / 2, y: screen.maxY - notchH, width: notchW, height: notchH)
let np = CGMutablePath()
let r: CGFloat = 40
np.move(to: CGPoint(x: notch.minX, y: notch.maxY))
np.addLine(to: CGPoint(x: notch.minX, y: notch.minY + r))
np.addQuadCurve(to: CGPoint(x: notch.minX + r, y: notch.minY), control: CGPoint(x: notch.minX, y: notch.minY))
np.addLine(to: CGPoint(x: notch.maxX - r, y: notch.minY))
np.addQuadCurve(to: CGPoint(x: notch.maxX, y: notch.minY + r), control: CGPoint(x: notch.maxX, y: notch.minY))
np.addLine(to: CGPoint(x: notch.maxX, y: notch.maxY))
np.closeSubpath()
ctx.setFillColor(NSColor.black.cgColor)
ctx.addPath(np)
ctx.fillPath()

// Three widget dots: notes (yellow), tasks (green), pomodoro (red)
let dotColors = [
    NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 1),
    NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.5, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.35, alpha: 1),
]
let dotR: CGFloat = 46
let spacing: CGFloat = 150
let cy = screen.midY - 30
for (i, c) in dotColors.enumerated() {
    let cx = screen.midX + CGFloat(i - 1) * spacing
    ctx.setFillColor(c.cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
}
image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
print("wrote Resources/AppIcon.png")
