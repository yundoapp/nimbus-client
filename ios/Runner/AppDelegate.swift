import UIKit
import Flutter
import HiddifyCore
import Security
@main
@objc class AppDelegate: FlutterAppDelegate {
    private var secureSessionBridge: IOSSecureSessionBridge?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupFileManager()
        registerHandlers()
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }
    
    func registerHandlers() {
        MethodHandler.register(with: self.registrar(forPlugin: MethodHandler.name)!)
        PlatformMethodHandler.register(with: self.registrar(forPlugin: PlatformMethodHandler.name)!)
        FileMethodHandler.register(with: self.registrar(forPlugin: FileMethodHandler.name)!)
        StatusEventHandler.register(with: self.registrar(forPlugin: StatusEventHandler.name)!)
        AlertsEventHandler.register(with: self.registrar(forPlugin: AlertsEventHandler.name)!)
        let secureSessionBridge = IOSSecureSessionBridge(
            binaryMessenger: self.registrar(forPlugin: IOSSecureSessionBridge.name)!.messenger()
        )
        secureSessionBridge.register()
        self.secureSessionBridge = secureSessionBridge
//        LogsEventHandler.register(with: self.registrar(forPlugin: LogsEventHandler.name)!)
//        GroupsEventHandler.register(with: self.registrar(forPlugin: GroupsEventHandler.name)!)
//        ActiveGroupsEventHandler.register(with: self.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
//        StatsEventHandler.register(with: self.registrar(forPlugin: StatsEventHandler.name)!)
    }
}

private final class IOSSecureSessionBridge {
    static let name = "yundo_ios_secure_session"

    private let account = "nimbus.auth.session"
    private let channel: FlutterMethodChannel
    private let service: String

    init(binaryMessenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: Self.name, binaryMessenger: binaryMessenger)
        service = "\(Bundle.main.bundleIdentifier ?? "app.yundo.client").secure-session"
    }

    func register() {
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "secure_session_unavailable", message: nil, details: nil))
                return
            }
            switch call.method {
            case "read":
                self.read(result: result)
            case "write":
                guard
                    let arguments = call.arguments as? [String: Any],
                    let value = arguments["value"] as? String,
                    !value.isEmpty
                else {
                    result(FlutterError(code: "secure_session_bad_args", message: nil, details: nil))
                    return
                }
                self.write(value: value, result: result)
            case "delete":
                self.delete(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(result: @escaping FlutterResult) {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound {
            result(nil)
            return
        }
        guard
            status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            result(keychainError(status))
            return
        }
        result(value)
    }

    private func write(value: String, result: @escaping FlutterResult) {
        guard let data = value.data(using: .utf8) else {
            result(FlutterError(code: "secure_session_encoding_failed", message: nil, details: nil))
            return
        }

        let values = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess {
            result(nil)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            result(keychainError(updateStatus))
            return
        }

        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(request as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            result(keychainError(addStatus))
            return
        }
        result(nil)
    }

    private func delete(result: @escaping FlutterResult) {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            result(keychainError(status))
            return
        }
        result(nil)
    }

    private func keychainError(_ status: OSStatus) -> FlutterError {
        FlutterError(
            code: "secure_session_keychain_failed",
            message: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)",
            details: status
        )
    }
}
