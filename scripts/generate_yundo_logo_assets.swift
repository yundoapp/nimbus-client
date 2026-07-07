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

  NSGraphicsContext.restoreGraphicsState()

  let image = NSImage(size: NSSize(width: size, height: size))
  image.addRepresentation(bitmap)
  return image
}

func roundedPill(center: NSPoint, length: CGFloat, thickness: CGFloat, angle: CGFloat) -> NSBezierPath {
  let rect = NSRect(
    x: center.x - length / 2,
    y: center.y - thickness / 2,
    width: length,
    height: thickness
  )
  let path = NSBezierPath(roundedRect: rect, xRadius: thickness / 2, yRadius: thickness / 2)
  var transform = AffineTransform()
  transform.translate(x: center.x, y: center.y)
  transform.rotate(byDegrees: angle)
  transform.translate(x: -center.x, y: -center.y)
  path.transform(using: transform)
  return path
}

func drawYMark(in rect: NSRect, fill: NSColor, shadowEnabled: Bool) {
  if shadowEnabled {
    let shadow = NSShadow()
    shadow.shadowColor = color(0x11245f, alpha: 0.25)
    shadow.shadowBlurRadius = rect.width * 0.036
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.018)
    shadow.set()
  }

  let scale = rect.width / 64
  let thickness = rect.width * 0.098
  let armLength = rect.width * 0.255
  let stemLength = rect.width * 0.245

  fill.setFill()
  roundedPill(
    center: NSPoint(x: rect.minX + 24.0 * scale, y: rect.maxY - 24.0 * scale),
    length: armLength,
    thickness: thickness,
    angle: -45
  ).fill()
  roundedPill(
    center: NSPoint(x: rect.minX + 40.0 * scale, y: rect.maxY - 24.0 * scale),
    length: armLength,
    thickness: thickness,
    angle: 45
  ).fill()
  roundedPill(
    center: NSPoint(x: rect.minX + 32.0 * scale, y: rect.maxY - 40.0 * scale),
    length: stemLength,
    thickness: thickness,
    angle: 90
  ).fill()
}

func renderedAppIcon(size: Int) -> NSImage {
  renderedImage(size: size) { canvas in
    let inset = CGFloat(size) * 0.045
    let iconRect = canvas.insetBy(dx: inset, dy: inset)
    let cornerRadius = CGFloat(size) * 0.18
    let backgroundPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
    backgroundPath.addClip()

    let gradient = NSGradient(colors: [color(0x7689dc), color(0x4f67aa), color(0x244cc4)])!
    gradient.draw(in: iconRect, angle: 250)

    color(0xffffff, alpha: 0.09).setStroke()
    let highlight = NSBezierPath(
      roundedRect: iconRect.insetBy(dx: CGFloat(size) * 0.03, dy: CGFloat(size) * 0.03),
      xRadius: cornerRadius * 0.76,
      yRadius: cornerRadius * 0.76
    )
    highlight.lineWidth = max(1, CGFloat(size) * 0.007)
    highlight.stroke()

    let markRect = iconRect.insetBy(dx: CGFloat(size) * 0.01, dy: CGFloat(size) * 0.065)
    drawYMark(in: markRect, fill: color(0xffffff), shadowEnabled: true)
  }
}

func renderedTrayTemplateIcon(size: Int) -> NSImage {
  renderedImage(size: size) { canvas in
    let markRect = canvas
    drawYMark(in: markRect, fill: color(0xffffff), shadowEnabled: false)
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
