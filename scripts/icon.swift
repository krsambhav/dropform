import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.13, green: 0.31, blue: 0.26, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedRed: 0.77, green: 0.89, blue: 0.76, alpha: 1).setStroke()
let tray = NSBezierPath(); tray.lineWidth = 44; tray.lineCapStyle = .round; tray.lineJoinStyle = .round
tray.move(to: NSPoint(x: 260, y: 460)); tray.line(to: NSPoint(x: 292, y: 284)); tray.curve(to: NSPoint(x: 344, y: 244), controlPoint1: NSPoint(x: 300, y: 248), controlPoint2: NSPoint(x: 314, y: 244)); tray.line(to: NSPoint(x: 680, y: 244)); tray.curve(to: NSPoint(x: 732, y: 284), controlPoint1: NSPoint(x: 714, y: 244), controlPoint2: NSPoint(x: 724, y: 248)); tray.line(to: NSPoint(x: 764, y: 460)); tray.stroke()
let arrow = NSBezierPath(); arrow.lineWidth = 46; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 512, y: 774)); arrow.line(to: NSPoint(x: 512, y: 440)); arrow.move(to: NSPoint(x: 390, y: 562)); arrow.line(to: NSPoint(x: 512, y: 440)); arrow.line(to: NSPoint(x: 634, y: 562)); arrow.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
