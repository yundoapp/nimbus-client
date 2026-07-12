import FlutterMacOS
import Foundation
import ServiceManagement
import SystemConfiguration

@objc private protocol YundoPrivilegedHelperProtocol {
  func startTunnel(_ config: String, withReply reply: @escaping (String?) -> Void)
  func stopTunnel(withReply reply: @escaping (String?) -> Void)
}

final class PrivilegedHelperBridge {
  private let channel: FlutterMethodChannel
  private var connection: NSXPCConnection?

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "yundo_macos_privileged_helper",
      binaryMessenger: binaryMessenger
    )
  }

  func register() {
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "helper_bridge_unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "startTunnel":
        guard
          let arguments = call.arguments as? [String: Any],
          let config = arguments["config"] as? String,
          !config.isEmpty,
          config.utf8.count <= 65_536
        else {
          result(FlutterError(code: "helper_invalid_config", message: nil, details: nil))
          return
        }
        self.startTunnel(config: config, result: result)
      case "stopTunnel":
        self.stopTunnel(result: result)
      case "status":
        self.readStatus(result: result)
      case "connectionConflict":
        self.inspectConnectionConflict(result: result)
      case "openSystemSettings":
        self.openSystemSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    connection?.invalidate()
  }

  @available(macOS 13.0, *)
  private var service: SMAppService? {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
    return .daemon(plistName: "\(bundleIdentifier).privileged-helper.plist")
  }

  private func startTunnel(config: String, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *), let service else {
      result(FlutterError(code: "helper_unsupported_macos", message: nil, details: nil))
      return
    }

    do {
      if service.status == .notRegistered || service.status == .notFound {
        try service.register()
      }
    } catch {
      let registrationError = error as NSError
      NSLog(
        "Privileged helper registration failed: domain=%@ code=%ld description=%@",
        registrationError.domain,
        registrationError.code,
        registrationError.localizedDescription
      )
      result(
        FlutterError(
          code: "helper_registration_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
      return
    }

    switch service.status {
    case .enabled:
      startThroughXPC(config: config, result: result)
    case .requiresApproval:
      SMAppService.openSystemSettingsLoginItems()
      result(FlutterError(code: "helper_requires_approval", message: nil, details: nil))
    case .notRegistered:
      result(FlutterError(code: "helper_not_registered", message: nil, details: nil))
    case .notFound:
      result(FlutterError(code: "helper_not_found", message: nil, details: nil))
    @unknown default:
      result(FlutterError(code: "helper_unknown_status", message: nil, details: nil))
    }
  }

  private func startThroughXPC(config: String, result: @escaping FlutterResult) {
    let connection = activeConnection()
    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      DispatchQueue.main.async {
        result(FlutterError(code: "helper_xpc_failed", message: error.localizedDescription, details: nil))
      }
    }
    guard let helper = proxy as? YundoPrivilegedHelperProtocol else {
      result(FlutterError(code: "helper_xpc_unavailable", message: nil, details: nil))
      return
    }
    helper.startTunnel(config) { error in
      DispatchQueue.main.async {
        if let error {
          NSLog("Privileged helper start failed: %@", error)
          result(FlutterError(code: "helper_start_failed", message: error, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  private func stopTunnel(result: @escaping FlutterResult) {
    guard let connection else {
      result(nil)
      return
    }
    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      DispatchQueue.main.async {
        result(FlutterError(code: "helper_xpc_failed", message: error.localizedDescription, details: nil))
      }
    }
    guard let helper = proxy as? YundoPrivilegedHelperProtocol else {
      result(FlutterError(code: "helper_xpc_unavailable", message: nil, details: nil))
      return
    }
    helper.stopTunnel { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(code: "helper_stop_failed", message: error, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  private func activeConnection() -> NSXPCConnection {
    if let connection { return connection }
    let serviceName = "\(Bundle.main.bundleIdentifier ?? "app.yundo.client").privileged-helper"
    let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: YundoPrivilegedHelperProtocol.self)
    connection.invalidationHandler = { [weak self] in self?.connection = nil }
    connection.interruptionHandler = { [weak self] in self?.connection = nil }
    connection.resume()
    self.connection = connection
    return connection
  }

  private func readStatus(result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *), let service else {
      result(["status": "unsupported"])
      return
    }
    let status = switch service.status {
    case .notRegistered: "notRegistered"
    case .enabled: "enabled"
    case .requiresApproval: "requiresApproval"
    case .notFound: "notFound"
    @unknown default: "unknown"
    }
    result(["status": status])
  }

  private func inspectConnectionConflict(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let inspection = NetworkConflictInspector.inspect()
      DispatchQueue.main.async {
        result(inspection)
      }
    }
  }

  private func openSystemSettings(result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(FlutterError(code: "helper_unsupported_macos", message: nil, details: nil))
      return
    }
    SMAppService.openSystemSettingsLoginItems()
    result(nil)
  }
}

private enum NetworkConflictInspector {
  private static let publicDestinations = ["1.1.1.1", "8.8.8.8", "9.9.9.9", "223.5.5.5"]
  private static let tunnelInterfacePrefixes = ["utun", "ppp", "ipsec", "tun", "tap"]

  static func inspect() -> [String: Any] {
    let systemProxyEnabled = isSystemProxyEnabled()
    var tunneledRouteCount = 0
    var routeCheckFailures = 0
    for destination in publicDestinations {
      guard let interface = routeInterface(for: destination) else {
        routeCheckFailures += 1
        continue
      }
      if tunnelInterfacePrefixes.contains(where: { interface.hasPrefix($0) }) {
        tunneledRouteCount += 1
      }
    }

    return [
      "hasConflict": systemProxyEnabled || tunneledRouteCount > 0,
      "systemProxyEnabled": systemProxyEnabled,
      "tunneledRouteCount": tunneledRouteCount,
      "routeCheckFailures": routeCheckFailures,
    ]
  }

  private static func isSystemProxyEnabled() -> Bool {
    guard let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return false }
    let enabledKeys = [
      kSCPropNetProxiesHTTPEnable as String,
      kSCPropNetProxiesHTTPSEnable as String,
      kSCPropNetProxiesSOCKSEnable as String,
      kSCPropNetProxiesProxyAutoConfigEnable as String,
      kSCPropNetProxiesProxyAutoDiscoveryEnable as String,
    ]
    return enabledKeys.contains { (proxies[$0] as? NSNumber)?.boolValue == true }
  }

  private static func routeInterface(for destination: String) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["-n", "get", destination]
    process.standardOutput = output
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    guard process.terminationStatus == 0 else { return nil }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    for line in text.split(whereSeparator: \Character.isNewline) {
      let fields = line.split(whereSeparator: \Character.isWhitespace)
      if fields.count == 2, fields[0] == "interface:" {
        return String(fields[1])
      }
    }
    return nil
  }
}
