import SwiftUI
import AppKit

@main
enum XuZhuoApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = DesktopAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class DesktopAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DesktopIslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = ProcessInfo.processInfo.environment["XUZHUO_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        controller = DesktopIslandController(store: SceneStore(directory: directory), workspace: WorkspaceService())
        controller?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension Notification.Name {
    static let saveScene = Notification.Name("XuZhuo.saveScene")
}
