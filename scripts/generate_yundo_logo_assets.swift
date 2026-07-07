import AppKit
import Foundation

struct IconOutput {
  let path: String
  let size: Int
}

let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = repoURL.appendingPathComponent("assets/images/brand/yundo-app-icon-source.png")

let outputs: [IconOutput] = [
  .init(path: "assets/images/app_icon.png", size: 1024),
  .init(path: "assets/images/brand/yundo-app-icon.png", size: 1024),
  .init(path: "assets/images/source/ic_launcher_border.png", size: 1024),
  .init(path: "assets/images/source/ic_launcher_splash.png", size: 512),
  .init(path: "assets/images/source/ic_launcher_foreground.png", size: 512),
  .init(path: "android/app/src/main/ic_launcher-playstore.png", size: 512),
  .init(path: "android/app/src/main/res/drawable-xxxhdpi/splash.png", size: 324),
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48),
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png", size: 48),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png", size: 72),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png", size: 96),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png", size: 144),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png", size: 192),
  .init(path: "assets/images/tray_icon.png", size: 256),
  .init(path: "assets/images/tray_icon_dark.png", size: 256),
  .init(path: "assets/images/tray_icon_connected.png", size: 256),
  .init(path: "assets/images/tray_icon_disconnected.png", size: 256),
]

func fail(_ message: String) -> Never {
  fputs("\(message)\n", stderr)
  exit(1)
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
  fail("Unable to read source image: \(sourceURL.path)")
}

func isEdgeBackground(_ color: NSColor?) -> Bool {
  guard let rgb = color?.usingColorSpace(.deviceRGB) else { return false }
  return rgb.redComponent < 0.08 && rgb.greenComponent < 0.08 && rgb.blueComponent < 0.08
}

func eraseConnectedBackground(in bitmap: NSBitmapImageRep) {
  let width = bitmap.pixelsWide
  let height = bitmap.pixelsHigh
  var visited = Array(repeating: false, count: width * height)
  var queue: [(Int, Int)] = []
  queue.reserveCapacity(width * 2 + height * 2)

  func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * width + x
    guard !visited[index], isEdgeBackground(bitmap.colorAt(x: x, y: y)) else { return }
    visited[index] = true
    queue.append((x, y))
  }

  for x in 0..<width {
    enqueue(x, 0)
    enqueue(x, height - 1)
  }
  for y in 0..<height {
    enqueue(0, y)
    enqueue(width - 1, y)
  }

  let transparent = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
  var cursor = 0
  while cursor < queue.count {
    let (x, y) = queue[cursor]
    cursor += 1
    bitmap.setColor(transparent, atX: x, y: y)
    enqueue(x + 1, y)
    enqueue(x - 1, y)
    enqueue(x, y + 1)
    enqueue(x, y - 1)
  }
}

func renderedIcon(size: Int) -> NSImage {
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
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()
  sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
  )
  NSGraphicsContext.restoreGraphicsState()

  eraseConnectedBackground(in: bitmap)

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
  writePNG(renderedIcon(size: output.size), to: repoURL.appendingPathComponent(output.path))
}

print("Generated \(outputs.count) Yundo logo assets from \(sourceURL.path)")
