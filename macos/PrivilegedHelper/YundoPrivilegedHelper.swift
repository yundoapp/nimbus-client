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
  private let allowedMatcherKeys: Set<String> = [
    "domain", "domain_suffix", "domain_keyword", "domain_regex", "ip_cidr",
    "ip_is_private", "source_ip_cidr", "port", "port_range", "source_port",
    "source_port_range", "network", "protocol", "process_name", "process_path",
    "rule_set", "ip_version", "invert",
  ]

  func validate(_ config: String) throws -> Data {
    guard let data = config.data(using: .utf8), data.count <= 262_144 else {
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
      "endpoint_independent_nat",
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
      Set(route.keys).isSubset(of: ["rules", "final", "auto_detect_interface", "rule_set"]),
      let rules = route["rules"] as? [[String: Any]],
      (2...1_024).contains(rules.count),
      let directRule = rules.first,
      Set(directRule.keys) == Set(["process_name", "action", "outbound"]),
      directRule["action"] as? String == "route",
      directRule["outbound"] as? String == "yundo-direct",
      Set(directRule["process_name"] as? [String] ?? [])
        == Set([BuildIdentity.appExecutableName, "YundoPrivilegedHelper"])
    else {
      throw HelperFailure.invalidConfiguration("route must end at the local SOCKS outbound")
    }

    var referencedRuleSets = Set<String>()
    var sniffRuleCount = 0
    for rule in rules.dropFirst() {
      try validateRouteRule(
        rule,
        referencedRuleSets: &referencedRuleSets,
        sniffRuleCount: &sniffRuleCount
      )
    }
    guard sniffRuleCount == 1 else {
      throw HelperFailure.invalidConfiguration("exactly one sniff rule is required")
    }

    let ruleSets = route["rule_set"] as? [[String: Any]] ?? []
    guard ruleSets.count <= 32 else {
      throw HelperFailure.invalidConfiguration("too many route rule sets")
    }
    var definedRuleSets = Set<String>()
    for ruleSet in ruleSets {
      let tag = try validateRuleSet(ruleSet)
      guard definedRuleSets.insert(tag).inserted else {
        throw HelperFailure.invalidConfiguration("duplicate route rule set")
      }
    }
    guard definedRuleSets == referencedRuleSets else {
      throw HelperFailure.invalidConfiguration("route rule set references do not match definitions")
    }
    return data
  }

  private func validateRouteRule(
    _ rule: [String: Any],
    referencedRuleSets: inout Set<String>,
    sniffRuleCount: inout Int
  ) throws {
    let keys = Set(rule.keys)
    guard
      keys.isSubset(of: allowedMatcherKeys.union(["action", "outbound"])),
      let action = rule["action"] as? String
    else {
      throw HelperFailure.invalidConfiguration("unexpected route rule")
    }

    if action == "sniff" {
      guard keys == Set(["action"]) else {
        throw HelperFailure.invalidConfiguration("sniff rule cannot contain matchers")
      }
      sniffRuleCount += 1
      return
    }

    let matcherKeys = keys.intersection(allowedMatcherKeys)
    guard !matcherKeys.subtracting(["invert"]).isEmpty else {
      throw HelperFailure.invalidConfiguration("route rule requires a matcher")
    }
    for key in matcherKeys {
      try validateMatcher(rule[key], key: key)
    }

    switch action {
    case "route":
      guard
        let outbound = rule["outbound"] as? String,
        ["yundo-direct", "yundo-socks"].contains(outbound)
      else {
        throw HelperFailure.invalidConfiguration("route rule has an invalid outbound")
      }
    case "reject":
      guard rule["outbound"] == nil else {
        throw HelperFailure.invalidConfiguration("reject rule cannot contain an outbound")
      }
    default:
      throw HelperFailure.invalidConfiguration("unsupported route action")
    }

    if let tag = rule["rule_set"] as? String {
      guard isSafeTag(tag) else {
        throw HelperFailure.invalidConfiguration("invalid route rule set tag")
      }
      referencedRuleSets.insert(tag)
    } else if let tags = rule["rule_set"] as? [String] {
      guard !tags.isEmpty, tags.count <= 32 else {
        throw HelperFailure.invalidConfiguration("invalid route rule set matcher")
      }
      for tag in tags {
        guard isSafeTag(tag) else {
          throw HelperFailure.invalidConfiguration("invalid route rule set tag")
        }
        referencedRuleSets.insert(tag)
      }
    }
  }

  private func validateMatcher(_ value: Any?, key: String) throws {
    switch key {
    case "ip_is_private", "invert":
      guard value is Bool else {
        throw HelperFailure.invalidConfiguration("invalid boolean route matcher")
      }
    case "ip_version":
      guard let version = value as? Int, [4, 6].contains(version) else {
        throw HelperFailure.invalidConfiguration("invalid IP version matcher")
      }
    case "port", "source_port":
      if let port = value as? Int {
        guard (0...65_535).contains(port) else {
          throw HelperFailure.invalidConfiguration("invalid port matcher")
        }
        return
      }
      guard
        let ports = value as? [Int],
        !ports.isEmpty,
        ports.count <= 256,
        ports.allSatisfy({ (0...65_535).contains($0) })
      else {
        throw HelperFailure.invalidConfiguration("invalid port matcher")
      }
    default:
      if let string = value as? String {
        guard !string.isEmpty, string.utf8.count <= 512 else {
          throw HelperFailure.invalidConfiguration("invalid string route matcher")
        }
        return
      }
      guard
        let strings = value as? [String],
        !strings.isEmpty,
        strings.count <= 256,
        strings.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 })
      else {
        throw HelperFailure.invalidConfiguration("invalid route matcher")
      }
    }
  }

  private func validateRuleSet(_ ruleSet: [String: Any]) throws -> String {
    guard let tag = ruleSet["tag"] as? String, isSafeTag(tag) else {
      throw HelperFailure.invalidConfiguration("invalid route rule set tag")
    }
    switch ruleSet["type"] as? String {
    case "local":
      guard
        Set(ruleSet.keys) == Set(["tag", "type", "format", "path"]),
        tag == "geoip-cn",
        ruleSet["format"] as? String == "binary",
        let path = ruleSet["path"] as? String,
        let appContentsURL = CoreRuntime.shared.appContentsURL,
        URL(fileURLWithPath: path).standardizedFileURL
          == appContentsURL
            .appendingPathComponent(
              "Frameworks/App.framework/Resources/flutter_assets/assets/rules/geoip-cn.srs"
            )
            .standardizedFileURL
      else {
        throw HelperFailure.invalidConfiguration("invalid local route rule set")
      }
    case "remote":
      guard
        Set(ruleSet.keys)
          == Set(["tag", "type", "format", "url", "update_interval", "download_detour"]),
        tag != "geoip-cn",
        ruleSet["format"] as? String == "binary",
        ruleSet["download_detour"] as? String == "yundo-socks",
        let urlString = ruleSet["url"] as? String,
        urlString.utf8.count <= 2_048,
        let components = URLComponents(string: urlString),
        components.scheme == "https",
        components.host?.isEmpty == false,
        components.user == nil,
        components.password == nil,
        let updateInterval = ruleSet["update_interval"] as? String,
        updateInterval.utf8.count <= 64,
        updateInterval.range(
          of: #"^(?:[0-9]+(?:\.[0-9]+)?(?:ns|us|ms|s|m|h|d))+$"#,
          options: .regularExpression
        ) != nil
      else {
        throw HelperFailure.invalidConfiguration("invalid remote route rule set")
      }
    default:
      throw HelperFailure.invalidConfiguration("unsupported route rule set")
    }
    return tag
  }

  private func isSafeTag(_ tag: String) -> Bool {
    tag.range(of: #"^[A-Za-z0-9][A-Za-z0-9._!+-]{0,127}$"#, options: .regularExpression)
      != nil
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
    NSLog("CoreRuntime start: validating configuration")
    let data = try validator.validate(config)
    NSLog("CoreRuntime start: loading core")
    try loadCoreIfNeeded()
    NSLog("CoreRuntime start: stopping existing tunnel")
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

    NSLog("CoreRuntime start: tunnel child launched pid=%d", process.processIdentifier)
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
    NSLog("CoreRuntime start: tunnel child is running")
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

  fileprivate var appContentsURL: URL? {
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
    let libraryURL = appContentsURL.appendingPathComponent("Frameworks/YundoCore.dylib")
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
    stopOrphanedTunnelProcessesLocked()
    tunnelProcess = nil
    tunnelLogHandle?.closeFile()
    tunnelLogHandle = nil
    try? FileManager.default.removeItem(at: dataDirectory.appendingPathComponent("active-tunnel.json"))
  }

  private func stopOrphanedTunnelProcessesLocked() {
    guard
      let helperPath = HelperProcess.executableURL?.path,
      let output = runProcess(executable: "/bin/ps", arguments: ["-axo", "pid=,command="])
    else {
      return
    }

    let configPath = dataDirectory.appendingPathComponent("active-tunnel.json").path
    let expectedCommand = "\(helperPath) --run-tunnel \(configPath)"
    let processIDs = output
      .split(separator: "\n")
      .compactMap { line -> pid_t? in
        let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, let pid = Int32(parts[0]), pid != getpid() else { return nil }
        return parts[1] == expectedCommand ? pid : nil
      }

    if !processIDs.isEmpty {
      NSLog("CoreRuntime stop: terminating orphaned tunnel pids=%@", processIDs.map(String.init).joined(separator: ","))
    }

    for processID in processIDs {
      kill(processID, SIGTERM)
    }
    for processID in processIDs {
      for _ in 0..<20 where kill(processID, 0) == 0 {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if kill(processID, 0) == 0 {
        kill(processID, SIGKILL)
      }
    }
  }

  private func runProcess(executable: String, arguments: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      // Drain stdout while the child is running. Waiting first can deadlock
      // when `ps` output exceeds the pipe buffer.
      let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return String(data: outputData, encoding: .utf8)
    } catch {
      return nil
    }
  }
}

private final class HelperEndpoint: NSObject, YundoPrivilegedHelperProtocol {
  func startTunnel(_ config: String, withReply reply: @escaping (String?) -> Void) {
    NSLog("Helper endpoint: startTunnel received bytes=%d", config.utf8.count)
    do {
      try CoreRuntime.shared.start(config: config)
      NSLog("Helper endpoint: startTunnel completed successfully")
      reply(nil)
    } catch {
      NSLog("Helper endpoint: startTunnel failed: %@", error.localizedDescription)
      reply(error.localizedDescription)
    }
  }

  func stopTunnel(withReply reply: @escaping (String?) -> Void) {
    NSLog("Helper endpoint: stopTunnel received")
    CoreRuntime.shared.stop()
    NSLog("Helper endpoint: stopTunnel completed")
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
    NSLog(
      "CallerVerifier: checking pid=%d euid=%d",
      connection.processIdentifier,
      connection.effectiveUserIdentifier
    )
    guard
      connection.processIdentifier > 0,
      connection.effectiveUserIdentifier != 0,
      let helperSigningIdentity
    else {
      NSLog("CallerVerifier: basic caller or helper identity check failed")
      return false
    }
    NSLog(
      "CallerVerifier: helper team=%@ adhoc=%@",
      helperSigningIdentity.teamIdentifier ?? "<none>",
      helperSigningIdentity.isAdHoc ? "true" : "false"
    )
    let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
    var guestCode: SecCode?
    let guestStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode)
    guard guestStatus == errSecSuccess, let guestCode else {
      NSLog("CallerVerifier: guest code lookup failed status=%d", guestStatus)
      return false
    }
    NSLog("CallerVerifier: guest code lookup succeeded")
    let validityStatus = SecCodeCheckValidity(guestCode, [], nil)
    guard validityStatus == errSecSuccess else {
      NSLog("CallerVerifier: guest code validity failed status=%d", validityStatus)
      return false
    }
    NSLog("CallerVerifier: guest code validity succeeded")
    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(guestCode, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else {
      NSLog("CallerVerifier: static code lookup failed status=%d", staticStatus)
      return false
    }
    NSLog("CallerVerifier: static code lookup succeeded")
    var rawSigningInfo: CFDictionary?
    let signingStatus = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &rawSigningInfo
    )
    guard signingStatus == errSecSuccess, let signingInfo = rawSigningInfo as? [CFString: Any] else {
      NSLog("CallerVerifier: signing information lookup failed status=%d", signingStatus)
      return false
    }
    guard signingInfo[kSecCodeInfoIdentifier] as? String == BuildIdentity.appBundleIdentifier else {
      NSLog("CallerVerifier: caller identifier mismatch")
      return false
    }
    guard let executableURL = signingInfo[kSecCodeInfoMainExecutable] as? URL else {
      NSLog("CallerVerifier: caller executable path unavailable")
      return false
    }
    NSLog("CallerVerifier: caller signing information succeeded executable=%@", executableURL.path)

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
    guard teamsMatch || adHocPair else {
      NSLog(
        "CallerVerifier: team mismatch helper=%@ caller=%@",
        helperSigningIdentity.teamIdentifier ?? "<none>",
        callerTeamIdentifier ?? "<none>"
      )
      return false
    }

    guard let helperURL = HelperProcess.executableURL else {
      NSLog("CallerVerifier: helper executable path unavailable")
      return false
    }
    let contentsURL = helperURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let infoURL = contentsURL.appendingPathComponent("Info.plist")
    guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
      NSLog("CallerVerifier: app Info.plist unavailable")
      return false
    }
    guard let executableName = info["CFBundleExecutable"] as? String,
          executableName == BuildIdentity.appExecutableName else {
      NSLog("CallerVerifier: app executable name mismatch")
      return false
    }
    let expectedURL = contentsURL.appendingPathComponent("MacOS/\(executableName)")
    let accepted = executableURL.resolvingSymlinksInPath().standardizedFileURL
      == expectedURL.resolvingSymlinksInPath().standardizedFileURL
    NSLog(
      "CallerVerifier: executable path check accepted=%@ expected=%@",
      accepted ? "true" : "false",
      expectedURL.path
    )
    return accepted
  }
}

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let verifier = CallerVerifier()

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    NSLog("Helper listener: incoming connection pid=%d", connection.processIdentifier)
    let accepted = verifier.accepts(connection)
    NSLog("Helper listener: connection accepted=%@", accepted ? "true" : "false")
    guard accepted else { return false }
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
        fputs("privileged helper config validation failed: \(error.localizedDescription)\n", stderr)
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
