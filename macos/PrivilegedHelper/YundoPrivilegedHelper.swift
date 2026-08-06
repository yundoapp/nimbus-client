import Darwin
import Foundation
import Security

@objc private protocol YundoPrivilegedHelperProtocol {
  func helperInfo(withReply reply: @escaping (String, String) -> Void)
  func startTunnel(_ config: String, withReply reply: @escaping (String?) -> Void)
  func stopTunnel(withReply reply: @escaping (String?) -> Void)
  func ruleSetDiagnostics(withReply reply: @escaping ([String]) -> Void)
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
  case coreStopFailed(String)

  var errorDescription: String? {
    switch self {
    case .unauthorizedCaller: "unauthorized caller"
    case .invalidConfiguration(let reason): "invalid tunnel configuration: \(reason)"
    case .coreLibraryUnavailable: "core library is unavailable"
    case .coreStartFailed(let reason): "tunnel start failed: \(reason)"
    case .coreStopFailed(let reason): "tunnel stop failed: \(reason)"
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
    guard Set(root.keys).isSubset(of: ["log", "experimental", "dns", "inbounds", "outbounds", "route"]) else {
      throw HelperFailure.invalidConfiguration("unexpected root key")
    }
    if let experimental = root["experimental"] {
      try validateExperimental(experimental)
    }
    if let dns = root["dns"] {
      try validateDNS(dns)
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
    guard
      Set(tun.keys).isSubset(of: allowedTunKeys),
      tun["sniff"] as? Bool == true,
      tun["sniff_override_destination"] as? Bool == true
    else {
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

  private func validateExperimental(_ value: Any) throws {
    guard
      let experimental = value as? NSDictionary,
      Set(experimental.allKeys.compactMap { $0 as? String }) == Set(["clash_api"]),
      let clashAPI = experimental["clash_api"] as? NSDictionary,
      Set(clashAPI.allKeys.compactMap { $0 as? String }).isSubset(of: ["external_controller", "secret"]),
      clashAPI["external_controller"] as? String == routeHistoryControllerAddress
    else {
      throw HelperFailure.invalidConfiguration("invalid route history controller")
    }
    if let secret = clashAPI["secret"] {
      guard let secret = secret as? String, !secret.isEmpty, secret.utf8.count <= 256 else {
        throw HelperFailure.invalidConfiguration("invalid route history controller secret")
      }
    }
  }

  private func validateDNS(_ value: Any) throws {
    guard
      let dns = value as? NSDictionary,
      Set(dns.allKeys.compactMap { $0 as? String }).isSubset(of: ["servers", "final", "strategy"]),
      let servers = dns["servers"] as? NSArray,
      servers.count > 0,
      let final = dns["final"] as? String,
      !final.isEmpty
    else {
      throw HelperFailure.invalidConfiguration("invalid DNS configuration")
    }

    if let strategy = dns["strategy"] as? String {
      guard ["prefer_ipv4", "prefer_ipv6", "ipv4_only", "ipv6_only"].contains(strategy) else {
        throw HelperFailure.invalidConfiguration("invalid DNS strategy")
      }
    } else if dns["strategy"] != nil {
      throw HelperFailure.invalidConfiguration("invalid DNS strategy")
    }

    var tags = Set<String>()
    for item in servers {
      guard let server = item as? NSDictionary else {
        throw HelperFailure.invalidConfiguration("invalid DNS server")
      }
      guard
        Set(server.allKeys.compactMap { $0 as? String }).isSubset(of: ["type", "tag", "server", "server_port", "tls", "detour"]),
        let type = server["type"] as? String,
        ["https", "tls", "tcp", "udp", "quic"].contains(type),
        let tag = server["tag"] as? String,
        !tag.isEmpty,
        tags.insert(tag).inserted,
        let address = server["server"] as? String,
        !address.isEmpty,
        !address.hasPrefix("/"),
        server["detour"] as? String == "yundo-socks"
      else {
        throw HelperFailure.invalidConfiguration("invalid DNS server")
      }

      if let port = server["server_port"] {
        guard let port = (port as? NSNumber)?.intValue, (1...65_535).contains(port) else {
          throw HelperFailure.invalidConfiguration("invalid DNS server port")
        }
      }
      if let tls = server["tls"] {
        guard
          let tls = tls as? NSDictionary,
          Set(tls.allKeys.compactMap { $0 as? String }).isSubset(of: ["enabled", "server_name"]),
          ((tls["enabled"] as? Bool) == true || (tls["enabled"] as? NSNumber)?.boolValue == true),
          (tls["server_name"] == nil
            || ((tls["server_name"] as? String)?.isEmpty == false))
        else {
          throw HelperFailure.invalidConfiguration("invalid DNS TLS configuration")
        }
      }
    }
    guard tags.contains(final) else {
      throw HelperFailure.invalidConfiguration("DNS final server is not defined")
    }
  }

  private var routeHistoryControllerAddress: String {
    let port = BuildIdentity.appBundleIdentifier == "app.yundo.client.rebuild.dev" ? 16757 : 16758
    return "127.0.0.1:\(port)"
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
    case "hijack-dns":
      guard rule["outbound"] == nil else {
        throw HelperFailure.invalidConfiguration("DNS hijack rule cannot contain an outbound")
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
      let allowedKeys = Set(["tag", "type", "format", "url", "update_interval", "download_detour", "fallback_path"])
      guard
        Set(ruleSet.keys).isSubset(of: allowedKeys),
        Set(ruleSet.keys).contains("tag"),
        Set(ruleSet.keys).contains("type"),
        Set(ruleSet.keys).contains("format"),
        Set(ruleSet.keys).contains("url"),
        Set(ruleSet.keys).contains("update_interval"),
        Set(ruleSet.keys).contains("download_detour"),
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
        && validateBundledFallbackPath(ruleSet["fallback_path"] as? String, tag: tag)
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

  private func validateBundledFallbackPath(_ path: String?, tag: String) -> Bool {
    guard let path, let appContentsURL = CoreRuntime.shared.appContentsURL else {
      return path == nil
    }
    return URL(fileURLWithPath: path).standardizedFileURL
      == appContentsURL
        .appendingPathComponent(
          "Frameworks/App.framework/Resources/flutter_assets/assets/rules/\(tag).srs"
        )
        .standardizedFileURL
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
    try stopLocked()

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

  func stop() throws {
    lock.lock()
    defer { lock.unlock() }
    try stopLocked()
  }

  func stopAndExit() {
    try? stop()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
      exit(EXIT_SUCCESS)
    }
  }

  func ruleSetDiagnostics() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    let logURL = dataDirectory.appendingPathComponent("tunnel-core.log")
    guard let rawLog = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
    return rawLog
      .split(separator: "\n")
      .filter { $0.contains("rule-set ") }
      .suffix(512)
      .map { String($0.prefix(2_048)) }
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

  private func stopLocked() throws {
    if let tunnelProcess, tunnelProcess.isRunning {
      tunnelProcess.terminate()
      for _ in 0..<20 where tunnelProcess.isRunning {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if tunnelProcess.isRunning {
        kill(tunnelProcess.processIdentifier, SIGKILL)
        for _ in 0..<20 where tunnelProcess.isRunning {
          Thread.sleep(forTimeInterval: 0.05)
        }
      }
    }
    try stopOrphanedTunnelProcessesLocked()
    tunnelProcess = nil
    tunnelLogHandle?.closeFile()
    tunnelLogHandle = nil
    try? FileManager.default.removeItem(at: dataDirectory.appendingPathComponent("active-tunnel.json"))

    var residuals: [String] = []
    for _ in 0..<30 {
      residuals = cleanupResidualsLocked()
      if residuals.isEmpty { return }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw HelperFailure.coreStopFailed(residuals.joined(separator: "; "))
  }

  private func stopOrphanedTunnelProcessesLocked() throws {
    let processIDs = try ownedTunnelProcessIDsLocked()
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
        for _ in 0..<20 where kill(processID, 0) == 0 {
          Thread.sleep(forTimeInterval: 0.05)
        }
      }
    }
  }

  private func ownedTunnelProcessIDsLocked() throws -> [pid_t] {
    guard
      let helperPath = HelperProcess.executableURL?.path,
      let output = runProcess(executable: "/bin/ps", arguments: ["-axo", "pid=,command="])
    else {
      throw HelperFailure.coreStopFailed("unable to inspect tunnel worker processes")
    }

    let configPath = dataDirectory.appendingPathComponent("active-tunnel.json").path
    let expectedCommand = "\(helperPath) --run-tunnel \(configPath)"
    return output
      .split(separator: "\n")
      .compactMap { line -> pid_t? in
        let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, let pid = Int32(parts[0]), pid != getpid() else { return nil }
        return parts[1] == expectedCommand ? pid : nil
      }
  }

  private func cleanupResidualsLocked() -> [String] {
    var residuals: [String] = []
    do {
      let processIDs = try ownedTunnelProcessIDsLocked()
      if !processIDs.isEmpty {
        residuals.append("tunnel worker processes remain: \(processIDs.map(String.init).joined(separator: ","))")
      }
    } catch {
      residuals.append(error.localizedDescription)
    }

    let activeConfigURL = dataDirectory.appendingPathComponent("active-tunnel.json")
    if FileManager.default.fileExists(atPath: activeConfigURL.path) {
      residuals.append("active tunnel configuration remains")
    }

    let addressTokens = ["172.20.0.1", "fdfe:dcba:9876::1"]
    if let interfaces = runProcess(executable: "/sbin/ifconfig", arguments: []) {
      if addressTokens.contains(where: interfaces.contains) {
        residuals.append("Yundo tunnel interface address remains")
      }
    } else {
      residuals.append("unable to inspect network interfaces")
    }

    let routeOutputs = [
      runProcess(executable: "/usr/sbin/netstat", arguments: ["-rn", "-f", "inet"]),
      runProcess(executable: "/usr/sbin/netstat", arguments: ["-rn", "-f", "inet6"]),
    ]
    if routeOutputs.contains(where: { $0 == nil }) {
      residuals.append("unable to inspect system routes")
    } else if routeOutputs.compactMap({ $0 }).contains(where: { output in
      addressTokens.contains(where: output.contains)
    }) {
      residuals.append("Yundo system routes remain")
    }

    if let dns = runProcess(executable: "/usr/sbin/scutil", arguments: ["--dns"]) {
      if addressTokens.contains(where: dns.contains) {
        residuals.append("Yundo DNS state remains")
      }
    } else {
      residuals.append("unable to inspect DNS state")
    }
    return residuals
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
  func helperInfo(withReply reply: @escaping (String, String) -> Void) {
    reply(BuildIdentity.appBundleIdentifier, BuildIdentity.appBuildNumber)
  }

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
    do {
      try CoreRuntime.shared.stop()
      NSLog("Helper endpoint: stopTunnel completed")
      reply(nil)
    } catch {
      NSLog("Helper endpoint: stopTunnel failed: %@", error.localizedDescription)
      reply(error.localizedDescription)
    }
  }

  func ruleSetDiagnostics(withReply reply: @escaping ([String]) -> Void) {
    reply(CoreRuntime.shared.ruleSetDiagnostics())
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
