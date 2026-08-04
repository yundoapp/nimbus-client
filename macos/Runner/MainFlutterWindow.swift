import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
  private var statusItemBridge: YundoStatusItemBridge?
  private var privilegedHelperBridge: PrivilegedHelperBridge?
  private var brandingChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let lifecycleChannel = FlutterMethodChannel(
      name: "yundo.application.lifecycle",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    NotificationCenter.default.addObserver(
      forName: Notification.Name("YundoApplicationShouldTerminate"),
      object: nil,
      queue: .main
    ) { _ in
      lifecycleChannel.invokeMethod("applicationShouldTerminate", arguments: nil)
    }
    lifecycleChannel.setMethodCallHandler { call, result in
      if call.method == "allowTerminate" {
        (NSApp.delegate as? AppDelegate)?.allowTermination()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    brandingChannel = FlutterMethodChannel(
      name: "yundo_macos_branding",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    brandingChannel?.setMethodCallHandler { call, result in
      guard
        call.method == "setApplicationBranding",
        let arguments = call.arguments as? [String: Any],
        let displayName = arguments["displayName"] as? String,
        let localeIdentifier = arguments["localeIdentifier"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }

      DispatchQueue.main.async {
        let appleLanguage = localeIdentifier.hasPrefix("zh-TW") ? "zh-Hant" :
          (localeIdentifier.hasPrefix("zh") ? "zh-Hans" : "en")
        UserDefaults.standard.set([appleLanguage], forKey: "AppleLanguages")
        ProcessInfo.processInfo.processName = displayName
        NSApp.mainMenu?.items.first?.title = displayName
        NSApp.mainMenu?.items.first?.submenu?.title = displayName
        result(nil)
      }
    }


 // Add FlutterMethodChannel platform code
    FlutterMethodChannel(
      name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtLogin.isEnabled)
      case "launchAtStartupSetEnabled":
        if let arguments = call.arguments as? [String: Any] {
          LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    statusItemBridge = YundoStatusItemBridge(binaryMessenger: flutterViewController.engine.binaryMessenger)
    statusItemBridge?.register()
    privilegedHelperBridge = PrivilegedHelperBridge(binaryMessenger: flutterViewController.engine.binaryMessenger)
    privilegedHelperBridge?.register()
    //
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // window manager hidden at launch
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

private enum YundoTrayIndicator: String {
  case connected
  case disconnected
  case transitioning

  var color: NSColor {
    switch self {
    case .connected:
      return NSColor(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
    case .disconnected:
      return NSColor(srgbRed: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
    case .transitioning:
      return NSColor(srgbRed: 255 / 255, green: 159 / 255, blue: 10 / 255, alpha: 1)
    }
  }
}

private final class YundoStatusIndicatorView: NSView {
  var indicator = YundoTrayIndicator.disconnected {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let circleRect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(ovalIn: circleRect)
    indicator.color.set()
    if indicator == .disconnected {
      path.lineWidth = 1
      path.stroke()
    } else {
      path.fill()
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class YundoStatusItemBridge: NSObject, NSMenuDelegate {
  private let channel: FlutterMethodChannel
  private var statusItem: NSStatusItem?
  private var trayMenu: NSMenu?
  private let indicatorView = YundoStatusIndicatorView(frame: .zero)

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yundo_macos_status_item", binaryMessenger: binaryMessenger)
    super.init()
  }

  func register() {
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "bridge_unavailable", message: nil, details: nil))
        return
      }

      switch call.method {
      case "update":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Missing status item arguments", details: nil))
          return
        }
        let updateStatusItem = {
          do {
            try self.update(arguments)
            result(nil)
          } catch {
            result(FlutterError(code: "status_item_update_failed", message: error.localizedDescription, details: nil))
          }
        }
        if Thread.isMainThread {
          updateStatusItem()
        } else {
          DispatchQueue.main.async(execute: updateStatusItem)
        }
      case "destroy":
        let destroyStatusItem = {
          self.destroy()
          result(nil)
        }
        if Thread.isMainThread {
          destroyStatusItem()
        } else {
          DispatchQueue.main.async(execute: destroyStatusItem)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func update(_ arguments: [String: Any]) throws {
    guard
      let iconBytes = arguments["iconBytes"] as? FlutterStandardTypedData,
      let image = NSImage(data: iconBytes.data),
      let indicatorName = arguments["indicator"] as? String,
      let indicator = YundoTrayIndicator(rawValue: indicatorName),
      let toolTip = arguments["toolTip"] as? String,
      let openLabel = arguments["openLabel"] as? String,
      let connectionLabel = arguments["connectionLabel"] as? String,
      let connectionEnabled = arguments["connectionEnabled"] as? Bool,
      let modeLabel = arguments["modeLabel"] as? String,
      let modeEnabled = arguments["modeEnabled"] as? Bool,
      let modeItems = arguments["modeItems"] as? [[String: Any]],
      let locationLabel = arguments["locationLabel"] as? String,
      let locationItems = arguments["locationItems"] as? [[String: Any]],
      let locationEnabled = arguments["locationEnabled"] as? Bool,
      let quitLabel = arguments["quitLabel"] as? String
    else {
      throw NSError(
        domain: "YundoStatusItemBridge",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid status item arguments"]
      )
    }

    let button = ensureStatusItem()
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.toolTip = toolTip

    indicatorView.indicator = indicator
    trayMenu = makeMenu(
      openLabel: openLabel,
      connectionLabel: connectionLabel,
      connectionEnabled: connectionEnabled,
      modeLabel: modeLabel,
      modeEnabled: modeEnabled,
      modeItems: modeItems,
      locationLabel: locationLabel,
      locationItems: locationItems,
      locationEnabled: locationEnabled,
      quitLabel: quitLabel
    )
  }

  private func ensureStatusItem() -> NSStatusBarButton {
    if let button = statusItem?.button { return button }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    guard let button = item.button else {
      preconditionFailure("Unable to create macOS status item button")
    }

    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    indicatorView.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(indicatorView, positioned: .above, relativeTo: nil)
    NSLayoutConstraint.activate([
      indicatorView.widthAnchor.constraint(equalToConstant: 5),
      indicatorView.heightAnchor.constraint(equalToConstant: 5),
      indicatorView.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 6),
      indicatorView.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 6),
    ])

    statusItem = item
    return button
  }

  private func makeMenu(
    openLabel: String,
    connectionLabel: String,
    connectionEnabled: Bool,
    modeLabel: String,
    modeEnabled: Bool,
    modeItems: [[String: Any]],
    locationLabel: String,
    locationItems: [[String: Any]],
    locationEnabled: Bool,
    quitLabel: String
  ) -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(makeMenuItem(key: "open", label: openLabel))
    menu.addItem(.separator())

    let connectionItem = makeMenuItem(key: "connection", label: connectionLabel)
    connectionItem.isEnabled = connectionEnabled
    menu.addItem(connectionItem)

    menu.addItem(.separator())
    menu.addItem(makeSubmenuItem(label: modeLabel, items: modeItems, enabled: modeEnabled))
    menu.addItem(makeSubmenuItem(label: locationLabel, items: locationItems, enabled: locationEnabled))

    menu.addItem(.separator())
    menu.addItem(makeMenuItem(key: "quit", label: quitLabel))
    return menu
  }

  private func makeSubmenuItem(label: String, items: [[String: Any]], enabled: Bool = true) -> NSMenuItem {
    let parent = NSMenuItem(title: label, action: nil, keyEquivalent: "")
    parent.isEnabled = enabled

    let submenu = NSMenu(title: label)
    for itemData in items {
      guard
        let key = itemData["key"] as? String,
        let itemLabel = itemData["label"] as? String,
        let checked = itemData["checked"] as? Bool
      else { continue }
      let item = makeMenuItem(key: key, label: itemLabel)
      item.state = checked ? .on : .off
      submenu.addItem(item)
    }
    parent.submenu = submenu
    return parent
  }

  private func makeMenuItem(key: String, label: String) -> NSMenuItem {
    let item = NSMenuItem(title: label, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = key
    return item
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    switch NSApp.currentEvent?.type {
    case .rightMouseDown, .rightMouseUp:
      guard let trayMenu else { return }
      statusItem?.menu = trayMenu
      sender.performClick(nil)
    default:
      channel.invokeMethod("onLeftClick", arguments: nil)
    }
  }

  @objc private func menuItemClicked(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    channel.invokeMethod("onMenuItemClick", arguments: ["key": key])
  }

  func menuDidClose(_ menu: NSMenu) { statusItem?.menu = nil }

  private func destroy() {
    guard let statusItem else { return }
    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
    trayMenu = nil
  }
}
