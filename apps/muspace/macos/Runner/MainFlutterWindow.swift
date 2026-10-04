import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let secrets = FlutterMethodChannel(name: "com.mightyoung.muspace/secrets", binaryMessenger: flutterViewController.engine.binaryMessenger)
    secrets.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any], let reference = args["reference"] as? String,
            reference.range(of: "^[A-Za-z0-9_.-]{1,128}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid_reference", message: "Invalid credential reference", details: nil)); return
      }
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mightyoung.muspace.models", kSecAttrAccount as String: reference]
      switch call.method {
      case "read":
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &value)
        if status == errSecItemNotFound { result(nil) }
        else if status == errSecSuccess, let data = value as? Data { result(String(data: data, encoding: .utf8)) }
        else { result(FlutterError(code: "secret_store_failed", message: "System credential store unavailable", details: nil)) }
      case "write":
        guard let value = args["value"] as? String, let data = value.data(using: .utf8) else {
          result(FlutterError(code: "invalid_value", message: "Invalid credential value", details: nil)); return
        }
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var add = query
          add[kSecValueData as String] = data
          add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          status = SecItemAdd(add as CFDictionary, nil)
        }
        result(status == errSecSuccess ? nil : FlutterError(code: "secret_store_failed", message: "System credential store unavailable", details: nil))
      case "remove":
        let status = SecItemDelete(query as CFDictionary)
        result(status == errSecSuccess || status == errSecItemNotFound ? nil : FlutterError(code: "secret_store_failed", message: "System credential store unavailable", details: nil))
      default: result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
