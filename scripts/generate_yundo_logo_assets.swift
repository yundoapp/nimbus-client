import AppKit
import Foundation

struct IconOutput {
  let path: String
  let size: Int
  let kind: IconKind
}

enum IconKind {
  case appIcon
  case trayTemplate
}

let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let outputs: [IconOutput] = [
  .init(path: "assets/images/brand/yundo-app-icon-source.png", size: 1024, kind: .appIcon),
  .init(path: "assets/images/app_icon.png", size: 1024, kind: .appIcon),
  .init(path: "assets/images/brand/yundo-app-icon.png", size: 1024, kind: .appIcon),
  .init(path: "assets/images/source/ic_launcher_border.png", size: 1024, kind: .appIcon),
  .init(path: "assets/images/source/ic_launcher_splash.png", size: 512, kind: .appIcon),
  .init(path: "assets/images/source/ic_launcher_foreground.png", size: 512, kind: .appIcon),
  .init(path: "android/app/src/main/ic_launcher-playstore.png", size: 512, kind: .appIcon),
  .init(path: "android/app/src/main/res/drawable-xxxhdpi/splash.png", size: 324, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png", size: 48, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png", size: 72, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png", size: 96, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png", size: 144, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192, kind: .appIcon),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png", size: 192, kind: .appIcon),
  .init(path: "assets/images/source/tray_icon.png", size: 2048, kind: .trayTemplate),
  .init(path: "assets/images/source/tray_icon_connected.png", size: 2048, kind: .trayTemplate),
  .init(path: "assets/images/source/tray_icon_disconnected.png", size: 2048, kind: .trayTemplate),
  .init(path: "assets/images/tray_icon.png", size: 256, kind: .trayTemplate),
  .init(path: "assets/images/tray_icon_dark.png", size: 256, kind: .trayTemplate),
  .init(path: "assets/images/tray_icon_connected.png", size: 256, kind: .trayTemplate),
  .init(path: "assets/images/tray_icon_disconnected.png", size: 256, kind: .trayTemplate),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_16x16.png", size: 16, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png", size: 32, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_32x32.png", size: 32, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png", size: 64, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_128x128.png", size: 128, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png", size: 256, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_256x256.png", size: 256, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png", size: 512, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_512x512.png", size: 512, kind: .appIcon),
  .init(path: "macos/Runner/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png", size: 1024, kind: .appIcon),
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

func scaledTrayPoint(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> NSPoint {
  NSPoint(x: rect.minX + rect.width * x / 24, y: rect.minY + rect.height * (1 - y / 24))
}

func cloudTopPath(in rect: NSRect) -> NSBezierPath {
  let path = NSBezierPath()
  path.move(to: scaledPoint(14.5, 38.1, in: rect))
  path.curve(
    to: scaledPoint(25.2, 27.9, in: rect),
    controlPoint1: scaledPoint(14.6, 32.4, in: rect),
    controlPoint2: scaledPoint(19.2, 27.9, in: rect)
  )
  path.curve(
    to: scaledPoint(47.4, 21.5, in: rect),
    controlPoint1: scaledPoint(28.0, 18.2, in: rect),
    controlPoint2: scaledPoint(40.1, 14.2, in: rect)
  )
  path.curve(
    to: scaledPoint(51.5, 31.5, in: rect),
    controlPoint1: scaledPoint(50.1, 24.2, in: rect),
    controlPoint2: scaledPoint(51.5, 27.6, in: rect)
  )
  path.curve(
    to: scaledPoint(60.5, 42.1, in: rect),
    controlPoint1: scaledPoint(56.2, 32.4, in: rect),
    controlPoint2: scaledPoint(60.5, 36.4, in: rect)
  )
  path.curve(
    to: scaledPoint(49.0, 53.5, in: rect),
    controlPoint1: scaledPoint(60.5, 48.4, in: rect),
    controlPoint2: scaledPoint(55.4, 53.5, in: rect)
  )
  path.line(to: scaledPoint(43.7, 53.5, in: rect))
  return path
}

func cloudBottomPath(in rect: NSRect) -> NSBezierPath {
  let path = NSBezierPath()
  path.move(to: scaledPoint(14.5, 38.1, in: rect))
  path.curve(
    to: scaledPoint(7.9, 45.8, in: rect),
    controlPoint1: scaledPoint(10.6, 38.8, in: rect),
    controlPoint2: scaledPoint(7.9, 42.0, in: rect)
  )
  path.curve(
    to: scaledPoint(16.0, 53.5, in: rect),
    controlPoint1: scaledPoint(7.9, 50.1, in: rect),
    controlPoint2: scaledPoint(11.5, 53.5, in: rect)
  )
  path.line(to: scaledPoint(27.0, 53.5, in: rect))
  path.curve(
    to: scaledPoint(49.5, 45.5, in: rect),
    controlPoint1: scaledPoint(36.2, 53.5, in: rect),
    controlPoint2: scaledPoint(42.6, 50.9, in: rect)
  )
  return path
}

func drawCloud(in rect: NSRect, lineWidth: CGFloat, strokeColor: NSColor = color(0xffffff), shadowEnabled: Bool = true) {
  let paths = [cloudTopPath(in: rect), cloudBottomPath(in: rect)]
  if shadowEnabled {
    let shadow = NSShadow()
    shadow.shadowColor = color(0x1f2f63, alpha: 0.28)
    shadow.shadowBlurRadius = rect.width * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.018)
    shadow.set()
  }

  for path in paths {
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    strokeColor.setStroke()
    path.stroke()
  }
}

func trayCloudPath(in rect: NSRect) -> NSBezierPath {
  let path = NSBezierPath()
  path.move(to: scaledTrayPoint(19.35, 10.04, in: rect))
  path.curve(
    to: scaledTrayPoint(12.0, 4.0, in: rect),
    controlPoint1: scaledTrayPoint(18.67, 6.59, in: rect),
    controlPoint2: scaledTrayPoint(15.64, 4.0, in: rect)
  )
  path.curve(
    to: scaledTrayPoint(5.35, 8.04, in: rect),
    controlPoint1: scaledTrayPoint(9.11, 4.0, in: rect),
    controlPoint2: scaledTrayPoint(6.6, 5.64, in: rect)
  )
  path.curve(
    to: scaledTrayPoint(0.0, 14.0, in: rect),
    controlPoint1: scaledTrayPoint(2.34, 8.36, in: rect),
    controlPoint2: scaledTrayPoint(0.0, 10.91, in: rect)
  )
  path.curve(
    to: scaledTrayPoint(6.0, 20.0, in: rect),
    controlPoint1: scaledTrayPoint(0.0, 17.31, in: rect),
    controlPoint2: scaledTrayPoint(2.69, 20.0, in: rect)
  )
  path.line(to: scaledTrayPoint(19.0, 20.0, in: rect))
  path.curve(
    to: scaledTrayPoint(24.0, 15.0, in: rect),
    controlPoint1: scaledTrayPoint(21.76, 20.0, in: rect),
    controlPoint2: scaledTrayPoint(24.0, 17.76, in: rect)
  )
  path.curve(
    to: scaledTrayPoint(19.35, 10.04, in: rect),
    controlPoint1: scaledTrayPoint(24.0, 12.64, in: rect),
    controlPoint2: scaledTrayPoint(21.95, 10.49, in: rect)
  )
  path.close()
  return path
}

func renderedImage(size: Int, draw: (NSRect) -> Void) -> NSImage {
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
  NSColor.clear.setFill()
  canvas.fill()
  draw(canvas)

  let image = NSImage(size: NSSize(width: size, height: size))
  image.addRepresentation(bitmap)
  return image
}

func renderedAppIcon(size: Int) -> NSImage {
  renderedImage(size: size) { canvas in
  let inset = CGFloat(size) * 0.04
  let iconRect = canvas.insetBy(dx: inset, dy: inset)
  let cornerRadius = CGFloat(size) * 0.19
  let backgroundPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
  backgroundPath.addClip()

  let gradient = NSGradient(colors: [color(0x7184cf), color(0x4f67aa), color(0x2d45a5)])!
  gradient.draw(in: iconRect, angle: 255)

  color(0xffffff, alpha: 0.08).setStroke()
  let highlight = NSBezierPath(
    roundedRect: iconRect.insetBy(dx: CGFloat(size) * 0.03, dy: CGFloat(size) * 0.03),
    xRadius: cornerRadius * 0.78,
    yRadius: cornerRadius * 0.78
  )
  highlight.lineWidth = max(1, CGFloat(size) * 0.008)
  highlight.stroke()

  NSGraphicsContext.saveGraphicsState()
  let cloudRect = iconRect.insetBy(dx: CGFloat(size) * 0.145, dy: CGFloat(size) * 0.17)
  drawCloud(in: cloudRect, lineWidth: max(2, CGFloat(size) * 0.071))

  NSGraphicsContext.restoreGraphicsState()
  }
}

func renderedTrayTemplateIcon(size: Int) -> NSImage {
  renderedImage(size: size) { canvas in
    let iconRect = canvas.insetBy(dx: CGFloat(size) * 0.12, dy: CGFloat(size) * 0.10)
    color(0xffffff).setFill()
    trayCloudPath(in: iconRect).fill()
  }
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
  let image = switch output.kind {
  case .appIcon:
    renderedAppIcon(size: output.size)
  case .trayTemplate:
    renderedTrayTemplateIcon(size: output.size)
  }
  writePNG(image, to: repoURL.appendingPathComponent(output.path))
}

print("Generated \(outputs.count) Yundo logo assets")
