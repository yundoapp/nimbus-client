import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
  private var privilegedHelperBridge: PrivilegedHelperBridge?
  private var secureSessionBridge: SecureSessionBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)


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
    FlutterMethodChannel(
      name: "yundo_macos_app_menu", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { [weak self] (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "setApplicationName":
        guard
          let arguments = call.arguments as? [String: Any],
          let title = arguments["title"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "Missing application title", details: nil))
          return
        }
        DispatchQueue.main.async {
          self?.updateApplicationMenuTitle(title)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    privilegedHelperBridge = PrivilegedHelperBridge(binaryMessenger: flutterViewController.engine.binaryMessenger)
    privilegedHelperBridge?.register()
    secureSessionBridge = SecureSessionBridge(binaryMessenger: flutterViewController.engine.binaryMessenger)
    secureSessionBridge?.register()
    //
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // window manager hidden at launch
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }

  private func updateApplicationMenuTitle(_ title: String) {
    let appTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !appTitle.isEmpty else { return }

    guard let appMenuItem = NSApp.mainMenu?.item(at: 0) else { return }
    appMenuItem.title = appTitle

    guard let appMenu = appMenuItem.submenu else { return }
    appMenu.title = appTitle

    let isChineseTitle = appTitle.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    if appMenu.items.indices.contains(0) {
      appMenu.items[0].title = isChineseTitle ? "关于\(appTitle)" : "About \(appTitle)"
    }
    if appMenu.items.indices.contains(6) {
      appMenu.items[6].title = isChineseTitle ? "隐藏\(appTitle)" : "Hide \(appTitle)"
    }
    if appMenu.items.indices.contains(10) {
      appMenu.items[10].title = isChineseTitle ? "退出\(appTitle)" : "Quit \(appTitle)"
    }
  }
}
