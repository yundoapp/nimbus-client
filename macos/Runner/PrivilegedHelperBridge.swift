import FlutterMacOS
import Foundation
import ServiceManagement
import SystemConfiguration

@objc private protocol YundoPrivilegedHelperProtocol {
  func startTunnel(_ config: String, withReply reply: @escaping (String?) -> Void)
  func stopTunnel(withReply reply: @escaping (String?) -> Void)
}

final class PrivilegedHelperBridge {
  private static let registrationRepairAttempts = 12
  private static let registrationRepairRetryDelay = DispatchTimeInterval.milliseconds(250)

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
          config.utf8.count <= 262_144
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
    guard let serviceName = privilegedHelperServiceName else { return nil }
    return .daemon(plistName: "\(serviceName).plist")
  }

  private var privilegedHelperServiceName: String? {
    if let configured = Bundle.main.object(forInfoDictionaryKey: "YundoPrivilegedHelperService") as? String,
       !configured.isEmpty
    {
      return configured
    }
    return Bundle.main.bundleIdentifier.map { "\($0).privileged-helper" }
  }

  private func startTunnel(config: String, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *), let service else {
      result(FlutterError(code: "helper_unsupported_macos", message: nil, details: nil))
      return
    }

    NSLog("Privileged helper start requested: status=%@", serviceStatusName(service.status))

    do {
      if service.status == .notRegistered || service.status == .notFound {
        try service.register()
        NSLog("Privileged helper registered: status=%@", serviceStatusName(service.status))
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

    continueStart(
      config: config,
      service: service,
      allowRegistrationRepair: true,
      result: result
    )
  }

  @available(macOS 13.0, *)
  private func continueStart(
    config: String,
    service: SMAppService,
    allowRegistrationRepair: Bool,
    result: @escaping FlutterResult
  ) {
    NSLog(
      "Privileged helper continue start: status=%@, repair=%@",
      serviceStatusName(service.status),
      allowRegistrationRepair ? "true" : "false"
    )
    switch service.status {
    case .enabled:
      startThroughXPC(
        config: config,
        allowRegistrationRepair: allowRegistrationRepair,
        result: result
      )
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

  private func startThroughXPC(
    config: String,
    allowRegistrationRepair: Bool,
    result: @escaping FlutterResult
  ) {
    let connection = activeConnection()
    var completed = false
    let finishSuccess: () -> Void = {
      guard !completed else { return }
      completed = true
      result(nil)
    }
    let finishFailure: (FlutterError, Bool) -> Void = { [weak self] error, shouldRepairRegistration in
      guard !completed else { return }
      completed = true
      guard allowRegistrationRepair, shouldRepairRegistration, let self else {
        result(error)
        return
      }
      self.repairRegistrationAndRetry(
        config: config,
        originalError: error,
        result: result
      )
    }
    let timeout = DispatchWorkItem {
      finishFailure(
        FlutterError(code: "helper_xpc_timeout", message: nil, details: nil),
        true
      )
    }
    // Starting sing-box with a system TUN can take several seconds on the first run.
    // Do not unregister a live launch daemon while it is still completing startup.
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      DispatchQueue.main.async {
        timeout.cancel()
        finishFailure(
          FlutterError(
            code: "helper_xpc_failed",
            message: error.localizedDescription,
            details: nil
          ),
          true
        )
      }
    }
    guard let helper = proxy as? YundoPrivilegedHelperProtocol else {
      timeout.cancel()
      finishFailure(
        FlutterError(code: "helper_xpc_unavailable", message: nil, details: nil),
        false
      )
      return
    }
    helper.startTunnel(config) { error in
      DispatchQueue.main.async {
        timeout.cancel()
        if let error {
          NSLog("Privileged helper start failed: %@", error)
          finishFailure(
            FlutterError(code: "helper_start_failed", message: error, details: nil),
            false
          )
        } else {
          finishSuccess()
        }
      }
    }
  }

  private func repairRegistrationAndRetry(
    config: String,
    originalError: FlutterError,
    result: @escaping FlutterResult
  ) {
    guard #available(macOS 13.0, *), let service else {
      result(originalError)
      return
    }

    connection?.invalidate()
    connection = nil

    NSLog("Privileged helper repairing registration: status=%@", serviceStatusName(service.status))

    service.unregister { [weak self] error in
      DispatchQueue.main.async {
        guard let self else {
          result(originalError)
          return
        }
        if let error {
          self.finishRegistrationRepairFailure(
            error: error,
            originalError: originalError,
            result: result
          )
          return
        }

        self.registerAfterUnregister(
          config: config,
          service: service,
          attemptsRemaining: Self.registrationRepairAttempts,
          originalError: originalError,
          result: result
        )
      }
    }
  }

  @available(macOS 13.0, *)
  private func registerAfterUnregister(
    config: String,
    service: SMAppService,
    attemptsRemaining: Int,
    originalError: FlutterError,
    result: @escaping FlutterResult
  ) {
    do {
      try service.register()
    } catch {
      guard attemptsRemaining > 1 else {
        finishRegistrationRepairFailure(
          error: error,
          originalError: originalError,
          result: result
        )
        return
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + Self.registrationRepairRetryDelay) {
        self.registerAfterUnregister(
          config: config,
          service: service,
          attemptsRemaining: attemptsRemaining - 1,
          originalError: originalError,
          result: result
        )
      }
      return
    }

    continueStart(
      config: config,
      service: service,
      allowRegistrationRepair: false,
      result: result
    )
  }

  @available(macOS 13.0, *)
  private func finishRegistrationRepairFailure(
    error: Error,
    originalError: FlutterError,
    result: @escaping FlutterResult
  ) {
    let registrationError = error as NSError
    NSLog(
      "Privileged helper registration repair failed: domain=%@ code=%ld description=%@ status=%@",
      registrationError.domain,
      registrationError.code,
      registrationError.localizedDescription,
      serviceStatusName(service?.status)
    )
    result(
      FlutterError(
        code: "helper_registration_repair_failed",
        message: error.localizedDescription,
        details: ["originalCode": originalError.code]
      )
    )
  }

  private func stopTunnel(result: @escaping FlutterResult) {
    let connection = activeConnection()
    var completed = false
    let finish: (Any?) -> Void = { value in
      guard !completed else { return }
      completed = true
      result(value)
    }
    let timeout = DispatchWorkItem {
      finish(FlutterError(code: "helper_xpc_timeout", message: nil, details: nil))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      DispatchQueue.main.async {
        timeout.cancel()
        finish(FlutterError(code: "helper_xpc_failed", message: error.localizedDescription, details: nil))
      }
    }
    guard let helper = proxy as? YundoPrivilegedHelperProtocol else {
      timeout.cancel()
      finish(FlutterError(code: "helper_xpc_unavailable", message: nil, details: nil))
      return
    }
    helper.stopTunnel { error in
      DispatchQueue.main.async {
        timeout.cancel()
        if let error {
          finish(FlutterError(code: "helper_stop_failed", message: error, details: nil))
        } else {
          finish(nil)
        }
      }
    }
  }

  private func activeConnection() -> NSXPCConnection {
    if let connection { return connection }
    let serviceName = privilegedHelperServiceName ?? "app.yundo.client.privileged-helper"
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
    let status = serviceStatusName(service.status)
    result(["status": status])
  }

  @available(macOS 13.0, *)
  private func serviceStatusName(_ status: SMAppService.Status?) -> String {
    guard let status else { return "unavailable" }
    switch status {
    case .notRegistered: return "notRegistered"
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "unknown"
    }
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
  private struct RouteTarget {
    let destination: String
    let isIPv6: Bool
  }

  private struct RouteDetails {
    let interfaceName: String
    let gateway: String?
  }

  private static let routeTargets = [
    RouteTarget(destination: "1.1.1.1", isIPv6: false),
    RouteTarget(destination: "8.8.8.8", isIPv6: false),
    RouteTarget(destination: "9.9.9.9", isIPv6: false),
    RouteTarget(destination: "223.5.5.5", isIPv6: false),
    RouteTarget(destination: "2606:4700:4700::1111", isIPv6: true),
    RouteTarget(destination: "2001:4860:4860::8888", isIPv6: true),
  ]
  private static let yundoTunnelGateways = ["172.20.0.1", "fdfe:dcba:9876::1"]
  private static let tunnelInterfacePrefixes = ["utun", "ppp", "ipsec", "tun", "tap"]

  static func inspect() -> [String: Any] {
    let systemProxyEnabled = isSystemProxyEnabled()
    var tunneledRouteCount = 0
    var yundoRoutedCount = 0
    var routeCheckFailures = 0
    for target in routeTargets {
      guard let route = routeDetails(for: target) else {
        routeCheckFailures += 1
        continue
      }
      let isTunnelInterface = tunnelInterfacePrefixes.contains(where: { route.interfaceName.hasPrefix($0) })
      if isTunnelInterface {
        tunneledRouteCount += 1
        if isYundoTunnelGateway(route.gateway) {
          yundoRoutedCount += 1
        }
      }
    }

    return [
      "hasConflict": systemProxyEnabled || tunneledRouteCount > 0,
      "systemProxyEnabled": systemProxyEnabled,
      "tunneledRouteCount": tunneledRouteCount,
      "yundoRoutedCount": yundoRoutedCount,
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

  private static func routeDetails(for target: RouteTarget) -> RouteDetails? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["-n", "get"] + (target.isIPv6 ? ["-inet6"] : []) + [target.destination]
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
    var interfaceName: String?
    var gateway: String?
    for line in text.split(whereSeparator: \Character.isNewline) {
      let fields = line.split(whereSeparator: \Character.isWhitespace)
      if fields.count == 2, fields[0] == "interface:" {
        interfaceName = String(fields[1])
      } else if fields.count == 2, fields[0] == "gateway:" {
        gateway = String(fields[1])
      }
    }
    guard let interfaceName else { return nil }
    return RouteDetails(interfaceName: interfaceName, gateway: gateway)
  }

  private static func isYundoTunnelGateway(_ gateway: String?) -> Bool {
    guard let gateway else { return false }
    let normalized = gateway.split(separator: "%", maxSplits: 1).first.map(String.init)?.lowercased() ?? gateway.lowercased()
    return yundoTunnelGateways.contains(normalized)
  }
}
