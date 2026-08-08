//
//  FilePath.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation

public enum FilePath {
    public static let packageName = {
        Bundle.main.infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String ?? "unknown"
    }()
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

    static let sharedDirectory: URL = {
        if let sharedDirectory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: FilePath.groupName
        ) {
            return sharedDirectory
        }

        // 本地 Debug profile 尚未拿到 App Group 能力时仍允许 App 启动；
        // Packet Tunnel 构建仍必须使用已签名的 App Group 共享运行数据。
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yundo", isDirectory: true)
        print("[Yundo] App Group unavailable: \(FilePath.groupName); using local fallback")
        return fallback
    }()

    static let cacheDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
