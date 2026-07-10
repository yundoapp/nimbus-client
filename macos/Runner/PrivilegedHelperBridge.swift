import FlutterMacOS
import Foundation
import ServiceManagement

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
      if service.status == .notRegistered {
        try service.register()
      }
    } catch {
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

  private func openSystemSettings(result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(FlutterError(code: "helper_unsupported_macos", message: nil, details: nil))
      return
    }
    SMAppService.openSystemSettingsLoginItems()
    result(nil)
  }
}
