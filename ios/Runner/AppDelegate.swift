import Flutter
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backupFolder: BackupFolder?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Lets flutter_local_notifications show reminders while the app is open and receive taps.
    UNUserNotificationCenter.current().delegate = self
    if let registrar = registrar(forPlugin: "BackupFolder") {
      backupFolder = BackupFolder(messenger: registrar.messenger(), presenter: { [weak self] in
        self?.window?.rootViewController
      })
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// A folder outside the app sandbox (for example in iCloud Drive) that the user
/// picks once. A security-scoped bookmark keeps write access across launches,
/// so backups there survive deleting the app. Needs no paid iCloud entitlement.
final class BackupFolder: NSObject, UIDocumentPickerDelegate {
  private static let bookmarkKey = "spicci.backupFolderBookmark"
  private let channel: FlutterMethodChannel
  private let presenter: () -> UIViewController?
  private var pending: FlutterResult?

  init(messenger: FlutterBinaryMessenger, presenter: @escaping () -> UIViewController?) {
    channel = FlutterMethodChannel(name: "spicci/backup_folder", binaryMessenger: messenger)
    self.presenter = presenter
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pick":
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      picker.delegate = self
      pending = result
      presenter()?.present(picker, animated: true)
    case "name":
      result(withFolder { $0.lastPathComponent })
    case "clear":
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      result(nil)
    case "write":
      guard let name = args["name"] as? String, let content = args["content"] as? String else {
        return result(FlutterError(code: "args", message: "name and content required", details: nil))
      }
      result(perform { folder in
        let file = folder.appendingPathComponent(name)
        var error: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &error) { url in
          do { try Data(content.utf8).write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let e = error ?? writeError { throw e }
        return nil
      })
    case "list":
      result(perform { folder in
        let urls = try FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return urls.map { $0.lastPathComponent }
      })
    case "read":
      guard let name = args["name"] as? String else {
        return result(FlutterError(code: "args", message: "name required", details: nil))
      }
      result(perform { folder in
        var error: NSError?
        var text: String?
        NSFileCoordinator().coordinate(readingItemAt: folder.appendingPathComponent(name), options: [], error: &error) {
          text = try? String(contentsOf: $0, encoding: .utf8)
        }
        if let e = error { throw e }
        return text
      })
    case "delete":
      guard let name = args["name"] as? String else {
        return result(FlutterError(code: "args", message: "name required", details: nil))
      }
      result(perform { folder in
        try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        return nil
      })
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Resolves the bookmark and runs [body] with access to the folder.
  /// Returns nil when no folder is set.
  private func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
    guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    if stale { save(url) }
    return try body(url)
  }

  private func perform(_ body: (URL) throws -> Any?) -> Any? {
    do {
      guard let value = try withFolder(body) else {
        return FlutterError(code: "no_folder", message: "No backup folder chosen", details: nil)
      }
      return value
    } catch {
      return FlutterError(code: "io", message: error.localizedDescription, details: nil)
    }
  }

  private func save(_ url: URL) {
    if let data = try? url.bookmarkData() {
      UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return documentPickerWasCancelled(controller) }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    save(url)
    pending?(url.lastPathComponent)
    pending = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }
}
