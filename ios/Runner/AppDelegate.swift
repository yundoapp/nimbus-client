import UIKit
import Flutter
import HiddifyCore
import Sentry
@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupFileManager()
        let didFinishLaunching = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
        GeneratedPluginRegistrant.register(with: self)
        registerHandlers()
        return didFinishLaunching
    }
    
    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }
    
    func registerHandlers() {
        if let registrar = self.registrar(forPlugin: MethodHandler.name) {
            MethodHandler.register(with: registrar)
        } else {
            print("[Yundo] Flutter registrar unavailable: \(MethodHandler.name)")
        }
        if let registrar = self.registrar(forPlugin: PlatformMethodHandler.name) {
            PlatformMethodHandler.register(with: registrar)
        } else {
            print("[Yundo] Flutter registrar unavailable: \(PlatformMethodHandler.name)")
        }
        if let registrar = self.registrar(forPlugin: FileMethodHandler.name) {
            FileMethodHandler.register(with: registrar)
        } else {
            print("[Yundo] Flutter registrar unavailable: \(FileMethodHandler.name)")
        }
        if let registrar = self.registrar(forPlugin: StatusEventHandler.name) {
            StatusEventHandler.register(with: registrar)
        } else {
            print("[Yundo] Flutter registrar unavailable: \(StatusEventHandler.name)")
        }
        if let registrar = self.registrar(forPlugin: AlertsEventHandler.name) {
            AlertsEventHandler.register(with: registrar)
        } else {
            print("[Yundo] Flutter registrar unavailable: \(AlertsEventHandler.name)")
        }
//        LogsEventHandler.register(with: self.registrar(forPlugin: LogsEventHandler.name)!)
//        GroupsEventHandler.register(with: self.registrar(forPlugin: GroupsEventHandler.name)!)
//        ActiveGroupsEventHandler.register(with: self.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
//        StatsEventHandler.register(with: self.registrar(forPlugin: StatsEventHandler.name)!)
    }
}
