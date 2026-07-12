import FlutterMacOS
import Foundation
import Security

final class SecureSessionBridge {
  private let account = "nimbus.auth.session"
  private let channel: FlutterMethodChannel
  private let service: String

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "yundo_macos_secure_session",
      binaryMessenger: binaryMessenger
    )
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
    guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
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
    SecItemDelete(query as CFDictionary)
    var request = query
    request[kSecValueData as String] = data
    request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(request as CFDictionary, nil)
    guard status == errSecSuccess else {
      result(keychainError(status))
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
