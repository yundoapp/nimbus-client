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
let appIconSourceURL = repoURL.appendingPathComponent("assets/images/brand/yundo-app-icon.svg")
let trayIconSourceURL = repoURL.appendingPathComponent("assets/images/brand/yundo-tray-icon.svg")

let outputs: [IconOutput] = [
  .init(path: "assets/images/app_icon.png", size: 1024, kind: .appIcon),
  .init(path: "snap/gui/app_icon.png", size: 256, kind: .appIcon),
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

for output in outputs {
  let source = switch output.kind {
  case .appIcon:
    appIconSource
  case .trayTemplate:
    trayIconSource
  }
  writePNG(resizedImage(source, size: output.size), to: repoURL.appendingPathComponent(output.path))
}

writeICO(
  from: trayIconSource,
  to: repoURL.appendingPathComponent("assets/images/tray_icon.ico"),
  sizes: [16, 32, 48, 64, 128]
)

print("Generated \(outputs.count) Yundo PNG assets and 1 tray ICO file from SVG sources")
