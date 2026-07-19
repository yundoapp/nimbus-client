import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconOutput {
  let path: String
  let size: Int
  let kind: IconKind
}

enum IconKind {
  case appIcon
  case iosAppIcon
  case trayTemplate
}

let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconSourceURL = repoURL.appendingPathComponent("assets/images/brand/yundo-app-icon.svg")
let trayIconSourceURL = repoURL.appendingPathComponent("assets/images/brand/yundo-tray-icon.svg")

let outputs: [IconOutput] = [
  .init(path: "assets/images/app_icon.png", size: 1024, kind: .appIcon),
  .init(path: "snap/gui/app_icon.png", size: 256, kind: .appIcon),
  .init(path: "assets/images/source/ic_launcher_splash.png", size: 512, kind: .appIcon),
  .init(path: "assets/images/source/ic_launcher_foreground.png", size: 512, kind: .appIcon),
  .init(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png", size: 256, kind: .appIcon),
  .init(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png", size: 512, kind: .appIcon),
  .init(path: "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png", size: 768, kind: .appIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png", size: 20, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png", size: 40, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png", size: 60, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png", size: 29, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png", size: 58, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png", size: 87, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png", size: 40, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png", size: 80, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png", size: 120, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png", size: 120, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png", size: 180, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png", size: 76, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png", size: 152, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png", size: 167, kind: .iosAppIcon),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", size: 1024, kind: .iosAppIcon),
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
  .init(path: "assets/images/tray_icon.png", size: 256, kind: .trayTemplate),
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

func loadImage(_ url: URL) -> NSImage {
  guard let image = NSImage(contentsOf: url) else {
    fail("Missing image source: \(url.path)")
  }
  return image
}

func resizedImage(_ source: NSImage, size: Int) -> NSImage {
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
  context.cgContext.interpolationQuality = .high

  let canvas = NSRect(x: 0, y: 0, width: size, height: size)
  NSColor.clear.setFill()
  canvas.fill()
  source.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)
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

func writeIOSAppIconPNG(_ source: NSImage, size: Int, to url: URL) {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
  guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
  ) else {
    fail("Unable to create iOS app icon context for \(size)x\(size)")
  }

  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)
  context.interpolationQuality = .high

  let colors = [
    NSColor(red: 0x7D / 255, green: 0x98 / 255, blue: 0xE9 / 255, alpha: 1).cgColor,
    NSColor(red: 0x47 / 255, green: 0x71 / 255, blue: 0xDE / 255, alpha: 1).cgColor,
    NSColor(red: 0x17 / 255, green: 0x4A / 255, blue: 0xCB / 255, alpha: 1).cgColor,
  ] as CFArray
  let locations: [CGFloat] = [0, 0.46, 1]
  guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
    fail("Unable to create iOS app icon background gradient")
  }
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: CGFloat(size) / 2, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size) / 2, y: 0),
    options: []
  )

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  source.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
  )
  NSGraphicsContext.restoreGraphicsState()

  guard let image = context.makeImage() else {
    fail("Unable to render iOS app icon \(size)x\(size)")
  }

  do {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
  } catch {
    fail("Unable to create directory for \(url.path): \(error)")
  }

  guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else {
    fail("Unable to create PNG destination: \(url.path)")
  }

  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    fail("Unable to write PNG \(url.path)")
  }
}

func pngData(_ image: NSImage) -> Data {
  guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:]) else {
    fail("Unable to encode PNG data")
  }
  return data
}

func appendUInt16LE(_ value: UInt16, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
}

func appendUInt32LE(_ value: UInt32, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
  data.append(UInt8((value >> 16) & 0xff))
  data.append(UInt8((value >> 24) & 0xff))
}

func writeICO(from source: NSImage, to url: URL, sizes: [Int]) {
  let pngs = sizes.map { size in
    (size: size, data: pngData(resizedImage(source, size: size)))
  }

  var data = Data()
  appendUInt16LE(0, to: &data)
  appendUInt16LE(1, to: &data)
  appendUInt16LE(UInt16(pngs.count), to: &data)

  var imageOffset = 6 + (16 * pngs.count)
  for png in pngs {
    data.append(UInt8(png.size == 256 ? 0 : png.size))
    data.append(UInt8(png.size == 256 ? 0 : png.size))
    data.append(0)
    data.append(0)
    appendUInt16LE(1, to: &data)
    appendUInt16LE(32, to: &data)
    appendUInt32LE(UInt32(png.data.count), to: &data)
    appendUInt32LE(UInt32(imageOffset), to: &data)
    imageOffset += png.data.count
  }

  for png in pngs {
    data.append(png.data)
  }

  do {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url)
  } catch {
    fail("Unable to write ICO \(url.path): \(error)")
  }
}

let appIconSource = loadImage(appIconSourceURL)
let trayIconSource = loadImage(trayIconSourceURL)

func shouldWriteOutput(_ output: IconOutput) -> Bool {
  guard let topLevel = output.path.split(separator: "/").first else {
    return true
  }
  if topLevel == "android" && !FileManager.default.fileExists(atPath: String(topLevel)) {
    return false
  }
  return true
}

var generatedOutputCount = 0

for output in outputs {
  guard shouldWriteOutput(output) else {
    continue
  }
  let source = switch output.kind {
  case .appIcon:
    appIconSource
  case .iosAppIcon:
    appIconSource
  case .trayTemplate:
    trayIconSource
  }
  if output.kind == .iosAppIcon {
    writeIOSAppIconPNG(source, size: output.size, to: repoURL.appendingPathComponent(output.path))
  } else {
    writePNG(resizedImage(source, size: output.size), to: repoURL.appendingPathComponent(output.path))
  }
  generatedOutputCount += 1
}

writeICO(
  from: trayIconSource,
  to: repoURL.appendingPathComponent("assets/images/tray_icon.ico"),
  sizes: [16, 32, 48, 64, 128]
)

writeICO(
  from: appIconSource,
  to: repoURL.appendingPathComponent("assets/images/yundo_tray_windows.ico"),
  sizes: [16, 20, 24, 32, 40, 48, 64, 128, 256]
)

writeICO(
  from: appIconSource,
  to: repoURL.appendingPathComponent("windows/runner/resources/app_icon.ico"),
  sizes: [16, 24, 32, 48, 64, 128, 256]
)

print("Generated \(generatedOutputCount) Yundo PNG assets and 3 ICO files from SVG sources")
