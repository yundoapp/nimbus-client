import AppKit
import Foundation

struct IconOutput {
  let path: String
  let size: Int
  let opaque: Bool
}

let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let outputs: [IconOutput] = [
  .init(path: "assets/images/brand/yundo-app-icon-source.png", size: 1024, opaque: false),
  .init(path: "assets/images/app_icon.png", size: 1024, opaque: false),
  .init(path: "assets/images/brand/yundo-app-icon.png", size: 1024, opaque: false),
  .init(path: "assets/images/source/ic_launcher_border.png", size: 1024, opaque: false),
  .init(path: "assets/images/source/ic_launcher_splash.png", size: 512, opaque: false),
  .init(path: "assets/images/source/ic_launcher_foreground.png", size: 512, opaque: false),
  .init(path: "android/app/src/main/ic_launcher-playstore.png", size: 512, opaque: false),
  .init(path: "android/app/src/main/res/drawable-xxxhdpi/splash.png", size: 324, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png", size: 48, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png", size: 72, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png", size: 96, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png", size: 144, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192, opaque: false),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png", size: 192, opaque: false),
  .init(path: "assets/images/tray_icon.png", size: 256, opaque: false),
  .init(path: "assets/images/tray_icon_dark.png", size: 256, opaque: false),
  .init(path: "assets/images/tray_icon_connected.png", size: 256, opaque: false),
  .init(path: "assets/images/tray_icon_disconnected.png", size: 256, opaque: false),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_16x16.png", size: 16, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png", size: 32, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_32x32.png", size: 32, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png", size: 64, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_128x128.png", size: 128, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png", size: 256, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_256x256.png", size: 256, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png", size: 512, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_512x512.png", size: 512, opaque: true),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png", size: 1024, opaque: true),
]

func fail(_ message: String) -> Never {
  fputs("\(message)\n", stderr)
  exit(1)
}

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
  NSColor(
    deviceRed: CGFloat((hex >> 16) & 0xff) / 255,
    green: CGFloat((hex >> 8) & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255,
    alpha: alpha
  )
}

func scaledPoint(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> NSPoint {
  NSPoint(x: rect.minX + rect.width * x / 64, y: rect.minY + rect.height * (1 - y / 64))
}

func cloudTopPath(in rect: NSRect) -> NSBezierPath {
  let path = NSBezierPath()
  path.move(to: scaledPoint(13.5, 38.5, in: rect))
  path.curve(
    to: scaledPoint(25.5, 26.5, in: rect),
    controlPoint1: scaledPoint(13.5, 31.9, in: rect),
    controlPoint2: scaledPoint(18.8, 26.5, in: rect)
  )
  path.curve(
    to: scaledPoint(48.1, 20.6, in: rect),
    controlPoint1: scaledPoint(28.1, 16.6, in: rect),
    controlPoint2: scaledPoint(40.8, 13.3, in: rect)
  )
  path.curve(
    to: scaledPoint(52.3, 30.9, in: rect),
    controlPoint1: scaledPoint(51, 23.5, in: rect),
    controlPoint2: scaledPoint(52.4, 27.2, in: rect)
  )
  path.curve(
    to: scaledPoint(62.5, 42.1, in: rect),
    controlPoint1: scaledPoint(58.5, 31.8, in: rect),
    controlPoint2: scaledPoint(62.5, 36.4, in: rect)
  )
  path.curve(
    to: scaledPoint(50.5, 54, in: rect),
    controlPoint1: scaledPoint(62.5, 48.7, in: rect),
    controlPoint2: scaledPoint(57.2, 54, in: rect)
  )
  path.line(to: scaledPoint(43.1, 54, in: rect))
  return path
}

func cloudBottomPath(in rect: NSRect) -> NSBezierPath {
  let path = NSBezierPath()
  path.move(to: scaledPoint(13.5, 38.5, in: rect))
  path.curve(
    to: scaledPoint(7.5, 45.8, in: rect),
    controlPoint1: scaledPoint(10.1, 39.3, in: rect),
    controlPoint2: scaledPoint(7.5, 42.2, in: rect)
  )
  path.curve(
    to: scaledPoint(15.8, 54, in: rect),
    controlPoint1: scaledPoint(7.5, 50.3, in: rect),
    controlPoint2: scaledPoint(11.2, 54, in: rect)
  )
  path.line(to: scaledPoint(27.2, 54, in: rect))
  path.curve(
    to: scaledPoint(50.5, 45.9, in: rect),
    controlPoint1: scaledPoint(36.8, 54, in: rect),
    controlPoint2: scaledPoint(43.2, 51.3, in: rect)
  )
  return path
}

func drawCloud(in rect: NSRect, lineWidth: CGFloat) {
  let paths = [cloudTopPath(in: rect), cloudBottomPath(in: rect)]
  let shadow = NSShadow()
  shadow.shadowColor = color(0x1f2f63, alpha: 0.28)
  shadow.shadowBlurRadius = rect.width * 0.035
  shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.018)
  shadow.set()

  for path in paths {
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color(0xffffff).setStroke()
    path.stroke()
  }
}

func renderedIcon(size: Int, opaque: Bool) -> NSImage {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    fail("Unable to allocate bitmap for \(size)x\(size)")
  }

  NSGraphicsContext.saveGraphicsState()
  guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fail("Unable to create graphics context")
  }
  NSGraphicsContext.current = context
  context.cgContext.setAllowsAntialiasing(true)
  context.cgContext.setShouldAntialias(true)

  let canvas = NSRect(x: 0, y: 0, width: size, height: size)
  if opaque {
    color(0x293ca0).setFill()
  } else {
    NSColor.clear.setFill()
  }
  canvas.fill()

  let inset = CGFloat(size) * (opaque ? 0 : 0.035)
  let iconRect = canvas.insetBy(dx: inset, dy: inset)
  let cornerRadius = CGFloat(size) * 0.22
  let backgroundPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
  backgroundPath.addClip()

  let gradient = NSGradient(colors: [color(0x6379b8), color(0x4f67aa), color(0x293ca0)])!
  gradient.draw(in: iconRect, angle: 255)

  color(0xffffff, alpha: 0.13).setStroke()
  let highlight = NSBezierPath(roundedRect: iconRect.insetBy(dx: CGFloat(size) * 0.035, dy: CGFloat(size) * 0.035), xRadius: cornerRadius * 0.78, yRadius: cornerRadius * 0.78)
  highlight.lineWidth = max(1, CGFloat(size) * 0.012)
  highlight.stroke()

  NSGraphicsContext.saveGraphicsState()
  let cloudRect = iconRect.insetBy(dx: CGFloat(size) * 0.17, dy: CGFloat(size) * 0.19)
  drawCloud(in: cloudRect, lineWidth: max(2, CGFloat(size) * 0.068))

  NSGraphicsContext.restoreGraphicsState()

  let image = NSImage(size: NSSize(width: size, height: size))
  image.addRepresentation(bitmap)
  return image
}

func writePNG(_ image: NSImage, to url: URL) {
  guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:]) else {
    fail("Unable to encode PNG: \(url.path)")
  }

  do {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url)
  } catch {
    fail("Unable to write PNG \(url.path): \(error)")
  }
}

for output in outputs {
  writePNG(renderedIcon(size: output.size, opaque: output.opaque), to: repoURL.appendingPathComponent(output.path))
}

print("Generated \(outputs.count) Yundo logo assets")
