//
//  VPNManager.swift
//  Runner
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import Combine
import NetworkExtension

enum VPNManagerAlertType: String {
    case RequestVPNPermission
    case RequestNotificationPermission
    case EmptyConfiguration
    case StartCommandServer
    case CreateService
    case StartService
}

struct VPNManagerAlert {
    let alert: VPNManagerAlertType?
    let message: String?
}

private enum VPNManagerError: LocalizedError {
    case disconnectTimedOut

    var errorDescription: String? {
        switch self {
        case .disconnectTimedOut:
            return "Timed out while stopping the Yundo connection."
        }
    }
}

class VPNManager: ObservableObject {
    private var observer: NSObjectProtocol?
    private var manager = NEVPNManager.shared()
    private var timer: Timer?
            
    static let shared: VPNManager = VPNManager()
        
    @Published private(set) var state: NEVPNStatus = .invalid
    @Published private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil)
    
    @Published private(set) var upload: Int64 = 0
    @Published private(set) var download: Int64 = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    
    private var _connectTime: Date?
    private var connectTime: Date? {
        set {
            UserDefaults(suiteName: FilePath.groupName)?.set(newValue?.timeIntervalSince1970, forKey: "SingBoxConnectTime")
            _connectTime = newValue
        }
        get {
            if let _connectTime {
                return _connectTime
            }
            guard let interval = UserDefaults(suiteName: FilePath.groupName)?.value(forKey: "SingBoxConnectTime") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }
    private var readingWS: Bool = false
    
    @Published var isConnectedToAnyVPN: Bool = false

    private var providerBundleIdentifier: String {
        Bundle.main.baseBundleIdentifier + ".PacketTunnel"
    }

    private var localizedDescription: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Yundo"
    }
    
    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: nil) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            guard connection === self?.manager.connection else { return }
            self?.state = connection.status
            if connection.status == .disconnected || connection.status == .invalid {
                self?.connectTime = nil
                Task { [weak self] in
                    await self?.set(upload: 0, download: 0)
                }
            }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateStats()
            elapsedTime = -1 * (connectTime?.timeIntervalSinceNow ?? 0)
        }
    }
                
    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
    }
    
    func setup() async throws {
        try await loadVPNPreference()
    }
    
    private func loadVPNPreference() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = managers.first(where: isManagedManager) {
            self.manager = manager
            state = manager.connection.status
            return
        }
        let newManager = NETunnelProviderManager()
        let `protocol` = NETunnelProviderProtocol()
        `protocol`.providerBundleIdentifier = providerBundleIdentifier
        `protocol`.serverAddress = "localhost"
        newManager.protocolConfiguration = `protocol`
        newManager.localizedDescription = localizedDescription
        try await newManager.saveToPreferences()
        try await newManager.loadFromPreferences()
        self.manager = newManager
        state = newManager.connection.status
    }
    
    private func enableVPNManager() async throws {
        manager.isEnabled = true
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        rule.probeURL = URL(string: "http://captive.apple.com")
        manager.onDemandRules = [rule]
        manager.isOnDemandEnabled = true
        
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }
    
    @MainActor private func set(upload: Int64, download: Int64) {
        self.upload = upload
        self.download = download
    }
    
    var isAnyVPNConnected: Bool {
        guard let cfDict = CFNetworkCopySystemProxySettings() else { return false }
        let nsDict = cfDict.takeRetainedValue() as NSDictionary
        guard let keys = nsDict["__SCOPED__"] as? NSDictionary else {
            return false
        }
        for key: String in keys.allKeys as! [String] {
            if key == "tap" || key == "tun" || key == "ppp" || key == "ipsec" || key == "ipsec0" {
                return true
            } else if key.starts(with: "utun") {
                return true
            }
        }
        return false
    }
    
    func reset() async throws {
        if state != .disconnected && state != .invalid {
            try await disconnect()
            try await waitUntilDisconnected()
        }
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        for manager in managers where isManagedManager(manager) {
            try await manager.removeFromPreferences()
        }
        manager = .shared()
        try await loadVPNPreference()
    }
    
    
    private func updateStats() {
        let isAnyVPNConnected = self.isAnyVPNConnected
        if isConnectedToAnyVPN != isAnyVPNConnected {
            isConnectedToAnyVPN = isAnyVPNConnected
        }
        guard state == .connected else {
            Task { [weak self] in
                await self?.set(upload: 0, download: 0)
            }
            return
        }
        guard let connection = manager.connection as? NETunnelProviderSession else { return }
        do {
            try connection.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard
                    let response,
                    let response = String(data: response, encoding: .utf8)
                else { return }
                let responseComponents = response.components(separatedBy: ",")
                guard
                    responseComponents.count == 2,
                    let upload = Int64(responseComponents[0]),
                    let download = Int64(responseComponents[1])
                else { return }
                Task { [upload, download, weak self] () in
                    await self?.set(upload: upload, download: download)
                }
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func connect(with config: String, grpcServiceModePort:Int, disableMemoryLimit: Bool = false) async throws {
        
        await set(upload: 0, download: 0)
//        guard state == .disconnected else { return }
        try await enableVPNManager()
        try manager.connection.startVPNTunnel(options: [
            "Config": config as NSString,
            "GrpcServiceModePort":NSNumber(value: grpcServiceModePort),
            "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
        ])
        connectTime = .now
    }
    
    func disconnect() async throws {
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            try await manager.saveToPreferences()
        }
        manager.connection.stopVPNTunnel()
    }

    private func isManagedManager(_ candidate: NETunnelProviderManager) -> Bool {
        guard let provider = candidate.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return provider.providerBundleIdentifier == providerBundleIdentifier
    }

    private func waitUntilDisconnected() async throws {
        for _ in 0..<50 {
            let currentStatus = manager.connection.status
            if currentStatus == .disconnected || currentStatus == .invalid {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VPNManagerError.disconnectTimedOut
    }
}
