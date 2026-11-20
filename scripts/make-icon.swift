import AppKit
import Foundation

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.925, green: 0.925, blue: 0.918, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 200, yRadius: 200).fill()
NSColor(calibratedRed: 1, green: 0.51, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 325, y: 180, width: 374, height: 664), xRadius: 84, yRadius: 84).fill()
NSColor.white.withAlphaComponent(0.96).setStroke()
let outline = NSBezierPath(roundedRect: NSRect(x: 367, y: 228, width: 290, height: 568), xRadius: 46, yRadius: 46)
outline.lineWidth = 17
outline.stroke()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 459, y: 745, width: 106, height: 15), xRadius: 8, yRadius: 8).fill()
NSBezierPath(roundedRect: NSRect(x: 462, y: 253, width: 100, height: 12), xRadius: 6, yRadius: 6).fill()
NSColor(calibratedRed: 0.3, green: 0.57, blue: 0.4, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 594, y: 136, width: 230, height: 230)).fill()
let check = NSBezierPath()
check.move(to: NSPoint(x: 655, y: 253)); check.line(to: NSPoint(x: 694, y: 213)); check.line(to: NSPoint(x: 765, y: 290))
check.lineWidth = 22; check.lineCapStyle = .round; check.lineJoinStyle = .round
NSColor.white.setStroke(); check.stroke()
image.unlockFocus()
guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: destination))
