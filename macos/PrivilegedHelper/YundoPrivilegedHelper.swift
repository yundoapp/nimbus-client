import Darwin
import Foundation
import Security

@objc private protocol YundoPrivilegedHelperProtocol {
  func startTunnel(_ config: String, withReply reply: @escaping (String?) -> Void)
  func stopTunnel(withReply reply: @escaping (String?) -> Void)
}

private enum HelperProcess {
  static let executableURL: URL? = {
    var path = [CChar](repeating: 0, count: 4 * Int(PATH_MAX))
    let length = path.withUnsafeMutableBufferPointer { buffer in
      proc_pidpath(getpid(), buffer.baseAddress, UInt32(buffer.count))
    }
    guard length > 0 else { return nil }
    return path.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else { return nil }
      return URL(
        fileURLWithFileSystemRepresentation: baseAddress,
        isDirectory: false,
        relativeTo: nil
      ).resolvingSymlinksInPath()
    }
  }()
}

private enum HelperFailure: Error, LocalizedError {
  case unauthorizedCaller
  case invalidConfiguration(String)
  case coreLibraryUnavailable
  case coreStartFailed(String)

  var errorDescription: String? {
    switch self {
    case .unauthorizedCaller: "unauthorized caller"
    case .invalidConfiguration(let reason): "invalid tunnel configuration: \(reason)"
    case .coreLibraryUnavailable: "core library is unavailable"
    case .coreStartFailed(let reason): "tunnel start failed: \(reason)"
    }
  }
}

private final class TunnelConfigValidator {
  func validate(_ config: String) throws -> Data {
    guard let data = config.data(using: .utf8), data.count <= 65_536 else {
      throw HelperFailure.invalidConfiguration("payload is too large")
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw HelperFailure.invalidConfiguration("root must be an object")
    }
    guard Set(root.keys).isSubset(of: ["log", "inbounds", "outbounds", "route"]) else {
      throw HelperFailure.invalidConfiguration("unexpected root key")
    }

    guard
      let inbounds = root["inbounds"] as? [[String: Any]],
      inbounds.count == 1,
      let tun = inbounds.first,
      tun["type"] as? String == "tun",
      tun["auto_route"] as? Bool == true,
      tun["stack"] as? String == "system",
      tun["address"] as? [String] == ["172.20.0.1/30", "fdfe:dcba:9876::1/126"],
      tun["interface_name"] == nil
    else {
      throw HelperFailure.invalidConfiguration("exactly one automatic TUN inbound is required")
    }
    let allowedTunKeys: Set<String> = [
      "type", "tag", "address", "mtu", "auto_route", "strict_route", "stack",
      "endpoint_independent_nat", "sniff", "sniff_override_destination",
    ]
    guard Set(tun.keys).isSubset(of: allowedTunKeys) else {
      throw HelperFailure.invalidConfiguration("unexpected TUN option")
    }

    guard let outbounds = root["outbounds"] as? [[String: Any]], outbounds.count == 2 else {
      throw HelperFailure.invalidConfiguration("only local SOCKS and direct outbounds are allowed")
    }
    guard
      let socks = outbounds.first(where: { $0["tag"] as? String == "yundo-socks" }),
      socks["type"] as? String == "socks",
      socks["server"] as? String == "127.0.0.1",
      let port = socks["server_port"] as? Int,
      (1024...65535).contains(port)
    else {
      throw HelperFailure.invalidConfiguration("SOCKS target must be a local unprivileged port")
    }
    let allowedSocksKeys: Set<String> = [
      "type", "tag", "server", "server_port", "version", "username", "password",
    ]
    guard Set(socks.keys).isSubset(of: allowedSocksKeys) else {
      throw HelperFailure.invalidConfiguration("unexpected SOCKS option")
    }
    guard
      let direct = outbounds.first(where: {
        $0["type"] as? String == "direct" && $0["tag"] as? String == "yundo-direct"
      }),
      Set(direct.keys).isSubset(of: ["type", "tag"])
    else {
      throw HelperFailure.invalidConfiguration("direct bypass is required")
    }

    guard
      let route = root["route"] as? [String: Any],
      route["final"] as? String == "yundo-socks",
      route["auto_detect_interface"] as? Bool == true,
      Set(route.keys).isSubset(of: ["rules", "final", "auto_detect_interface"]),
      let rules = route["rules"] as? [[String: Any]],
      rules.count == 1,
      let rule = rules.first,
      Set(rule.keys).isSubset(of: ["process_name", "outbound"]),
      rule["outbound"] as? String == "yundo-direct",
      Set(rule["process_name"] as? [String] ?? []) == Set([BuildIdentity.appExecutableName, "YundoPrivilegedHelper"])
    else {
      throw HelperFailure.invalidConfiguration("route must end at the local SOCKS outbound")
    }
    return data
  }
}

private final class CoreRuntime {
  static let shared = CoreRuntime()

  private typealias ParseCliFunction = @convention(c) (
    CInt,
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
  ) -> UnsafeMutablePointer<CChar>?

  private let lock = NSLock()
  private let validator = TunnelConfigValidator()
  private var handle: UnsafeMutableRawPointer?
  private var parseCliFunction: ParseCliFunction?
  private var tunnelProcess: Process?
  private var tunnelLogHandle: FileHandle?

  func selfCheck() throws {
    lock.lock()
    defer { lock.unlock() }
    try loadCoreIfNeeded()
  }

  func start(config: String) throws {
    lock.lock()
    defer { lock.unlock() }
    guard geteuid() == 0 else { throw HelperFailure.unauthorizedCaller }
    let data = try validator.validate(config)
    try loadCoreIfNeeded()
    stopLocked()

    try FileManager.default.createDirectory(
      at: dataDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataDirectory.path)
    let configURL = dataDirectory.appendingPathComponent("active-tunnel.json")
    try data.write(to: configURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

    guard let executableURL = HelperProcess.executableURL else {
      try? FileManager.default.removeItem(at: configURL)
      throw HelperFailure.coreLibraryUnavailable
    }
    let logURL = dataDirectory.appendingPathComponent("tunnel-core.log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
    guard let logHandle = FileHandle(forWritingAtPath: logURL.path) else {
      try? FileManager.default.removeItem(at: configURL)
      throw HelperFailure.coreStartFailed("unable to open core log")
    }
    logHandle.truncateFile(atOffset: 0)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--run-tunnel", configURL.path]
    process.standardOutput = logHandle
    process.standardError = logHandle
    do {
      try process.run()
    } catch {
      logHandle.closeFile()
      try? FileManager.default.removeItem(at: configURL)
      throw HelperFailure.coreStartFailed(error.localizedDescription)
    }

    Thread.sleep(forTimeInterval: 1)
    guard process.isRunning else {
      logHandle.closeFile()
      try? FileManager.default.removeItem(at: configURL)
      let rawLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
      let summary = rawLog.split(separator: "\n").suffix(8).joined(separator: "\n")
      throw HelperFailure.coreStartFailed(summary.isEmpty ? "core process exited during startup" : summary)
    }
    tunnelProcess = process
    tunnelLogHandle = logHandle
  }

  func runTunnelCommand(configPath: String) throws {
    try loadCoreIfNeeded()
    guard let parseCliFunction else { throw HelperFailure.coreLibraryUnavailable }

    let arguments = [BuildIdentity.appExecutableName, "srun", "-c", configPath]
    let allocated = arguments.map { strdup($0) }
    defer { allocated.forEach { free($0) } }
    guard allocated.allSatisfy({ $0 != nil }) else {
      throw HelperFailure.coreStartFailed("unable to allocate core arguments")
    }
    var pointers = allocated
    _ = pointers.withUnsafeMutableBufferPointer { buffer in
      parseCliFunction(CInt(buffer.count), buffer.baseAddress)
    }
  }

  func stop() {
    lock.lock()
    defer { lock.unlock() }
    stopLocked()
  }

  func stopAndExit() {
    stop()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
      exit(EXIT_SUCCESS)
    }
  }

  private var appContentsURL: URL? {
    HelperProcess.executableURL?
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private var dataDirectory: URL {
    URL(fileURLWithPath: "/Library/Application Support/Yundo/PrivilegedHelper", isDirectory: true)
      .appendingPathComponent(BuildIdentity.appBundleIdentifier, isDirectory: true)
  }

  private func loadCoreIfNeeded() throws {
    if handle != nil { return }
    guard let appContentsURL else { throw HelperFailure.coreLibraryUnavailable }
    let libraryURL = appContentsURL.appendingPathComponent("Frameworks/hiddify-core.dylib")
    guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
      throw HelperFailure.coreLibraryUnavailable
    }
    guard
      let parseCliSymbol = dlsym(handle, "parseCli")
    else {
      dlclose(handle)
      throw HelperFailure.coreLibraryUnavailable
    }
    self.handle = handle
    parseCliFunction = unsafeBitCast(parseCliSymbol, to: ParseCliFunction.self)
  }

  private func stopLocked() {
    if let tunnelProcess, tunnelProcess.isRunning {
      tunnelProcess.terminate()
      for _ in 0..<20 where tunnelProcess.isRunning {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if tunnelProcess.isRunning {
        kill(tunnelProcess.processIdentifier, SIGKILL)
      }
    }
    tunnelProcess = nil
    tunnelLogHandle?.closeFile()
    tunnelLogHandle = nil
    try? FileManager.default.removeItem(at: dataDirectory.appendingPathComponent("active-tunnel.json"))
  }
}

private final class HelperEndpoint: NSObject, YundoPrivilegedHelperProtocol {
  func startTunnel(_ config: String, withReply reply: @escaping (String?) -> Void) {
    do {
      try CoreRuntime.shared.start(config: config)
      reply(nil)
    } catch {
      reply(error.localizedDescription)
    }
  }

  func stopTunnel(withReply reply: @escaping (String?) -> Void) {
    CoreRuntime.shared.stop()
    reply(nil)
  }
}

private final class CallerVerifier {
  private static let adHocSignatureFlag: UInt32 = 0x0002

  private struct SigningIdentity {
    let teamIdentifier: String?
    let isAdHoc: Bool
  }

  private lazy var helperSigningIdentity: SigningIdentity? = {
    guard let helperURL = HelperProcess.executableURL else { return nil }
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(helperURL as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
      return nil
    }
    var rawSigningInfo: CFDictionary?
    guard
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &rawSigningInfo)
        == errSecSuccess,
      let signingInfo = rawSigningInfo as? [CFString: Any]
    else {
      return nil
    }
    let signatureFlags = (signingInfo[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
    return SigningIdentity(
      teamIdentifier: signingInfo[kSecCodeInfoTeamIdentifier] as? String,
      isAdHoc: signatureFlags & Self.adHocSignatureFlag != 0
    )
  }()

  func accepts(_ connection: NSXPCConnection) -> Bool {
    guard
      connection.processIdentifier > 0,
      connection.effectiveUserIdentifier != 0,
      let helperSigningIdentity
    else {
      return false
    }
    let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
    var guestCode: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess, let guestCode else {
      return false
    }
    guard SecCodeCheckValidity(guestCode, [], nil) == errSecSuccess else { return false }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(guestCode, [], &staticCode) == errSecSuccess, let staticCode else { return false }
    var rawSigningInfo: CFDictionary?
    guard
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &rawSigningInfo)
        == errSecSuccess,
      let signingInfo = rawSigningInfo as? [CFString: Any],
      signingInfo[kSecCodeInfoIdentifier] as? String == BuildIdentity.appBundleIdentifier,
      let executableURL = signingInfo[kSecCodeInfoMainExecutable] as? URL
    else {
      return false
    }

    let callerTeamIdentifier = signingInfo[kSecCodeInfoTeamIdentifier] as? String
    let callerSignatureFlags = (signingInfo[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
    let callerIsAdHoc = callerSignatureFlags & Self.adHocSignatureFlag != 0
    let teamsMatch = helperSigningIdentity.teamIdentifier.map {
      !$0.isEmpty && $0 == callerTeamIdentifier
    } ?? false
    // Local Debug builds are recursively ad hoc signed. Their exact in-bundle path below
    // remains mandatory; production builds continue to require matching Team IDs.
    let adHocPair = helperSigningIdentity.isAdHoc
      && callerIsAdHoc
      && (helperSigningIdentity.teamIdentifier?.isEmpty ?? true)
      && (callerTeamIdentifier?.isEmpty ?? true)
    guard teamsMatch || adHocPair else { return false }

    guard let helperURL = HelperProcess.executableURL else { return false }
    let contentsURL = helperURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let infoURL = contentsURL.appendingPathComponent("Info.plist")
    guard
      let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
      let executableName = info["CFBundleExecutable"] as? String,
      executableName == BuildIdentity.appExecutableName
    else {
      return false
    }
    let expectedURL = contentsURL.appendingPathComponent("MacOS/\(executableName)")
    return executableURL.resolvingSymlinksInPath().standardizedFileURL
      == expectedURL.resolvingSymlinksInPath().standardizedFileURL
  }
}

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let verifier = CallerVerifier()

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    guard verifier.accepts(connection) else { return false }
    connection.exportedInterface = NSXPCInterface(with: YundoPrivilegedHelperProtocol.self)
    connection.exportedObject = HelperEndpoint()
    connection.invalidationHandler = { CoreRuntime.shared.stopAndExit() }
    connection.resume()
    return true
  }
}

@main
private enum HelperMain {
  static func main() {
    if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-check" {
      do {
        try CoreRuntime.shared.selfCheck()
        print("privileged-helper-self-check-ok")
        return
      } catch {
        fputs("privileged helper self-check failed\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--validate-config" {
      do {
        let config = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        _ = try TunnelConfigValidator().validate(config)
        print("privileged-helper-config-ok")
        return
      } catch {
        fputs("privileged helper config validation failed\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--run-tunnel" {
      do {
        try CoreRuntime.shared.runTunnelCommand(configPath: CommandLine.arguments[2])
        return
      } catch {
        fputs("privileged helper tunnel command failed\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
    let delegate = HelperListenerDelegate()
    let listener = NSXPCListener(machServiceName: BuildIdentity.serviceName)
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime(delegate) {
      RunLoop.current.run()
    }
  }
}
