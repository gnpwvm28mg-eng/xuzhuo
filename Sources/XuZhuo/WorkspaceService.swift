import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit

struct RestoreReport {
    /// Counts resource opens confirmed by NSWorkspace's completion handler.
    var opened = 0
    /// Counts windows whose position and size were both accepted by Accessibility.
    var positioned = 0
    var issues: [String] = []
}

private struct WindowMatchKey: Hashable {
    let bundleID: String
    let title: String
}

@MainActor
final class WorkspaceService: ObservableObject {
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var screenCaptureGranted = CGPreflightScreenCaptureAccess()

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
    }

    /// Permission prompts are confined to these explicit settings actions.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted { openPrivacySettings("Privacy_Accessibility") }
    }

    func requestScreenCapture() {
        screenCaptureGranted = CGRequestScreenCaptureAccess()
        if !screenCaptureGranted { openPrivacySettings("Privacy_ScreenCapture") }
        refreshPermissions()
    }

    func openAutomationSettings() {
        openPrivacySettings("Privacy_Automation")
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Records visible, titled, ordinary windows without requesting Accessibility.
    /// Blank-title, minimized, full-screen, and utility windows are omitted because
    /// there is no reliable, non-destructive way to match and restore them later.
    func captureWindows() -> [SavedWindow] {
        refreshPermissions()
        guard accessibilityGranted else { return [] }
        var saved: [SavedWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isHidden,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundleID = app.bundleIdentifier else { continue }
            for window in accessibilityWindows(for: app) {
                guard isOrdinaryWindow(window), !boolAttribute(window, kAXMinimizedAttribute),
                      !boolAttribute(window, "AXFullScreen"),
                      let title = stringAttribute(window, kAXTitleAttribute),
                      !normalizedTitle(title).isEmpty,
                      let frame = windowFrame(window), frame.width > 80, frame.height > 60 else { continue }
                saved.append(SavedWindow(bundleID: bundleID,
                                         applicationName: app.localizedName ?? bundleID,
                                         title: title, x: frame.minX, y: frame.minY,
                                         width: frame.width, height: frame.height))
            }
        }
        return saved
    }

    /// Called only when the user explicitly selects browser-tab collection.
    /// Reading a browser can trigger macOS's separate Automation consent prompt.
    func captureBrowserTabs() -> (resources: [SceneResource], issues: [String]) {
        var resources: [SceneResource] = []
        var issues: [String] = []
        var seen = Set<String>()
        let browsers = [("com.apple.Safari", "Safari", "name"),
                        ("com.google.Chrome", "Chrome", "title")]
        for (bundleID, name, titleProperty) in browsers {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { continue }
            let source = """
            with timeout of 8 seconds
                tell application id "\(bundleID)"
                    set collectedTabs to {}
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set tabURL to URL of browserTab
                                set tabTitle to \(titleProperty) of browserTab
                                set end of collectedTabs to {tabTitle, tabURL}
                            end try
                        end repeat
                    end repeat
                    return collectedTabs
                end tell
            end timeout
            """
            guard let script = NSAppleScript(source: source) else {
                issues.append(L("\(name)：无法准备标签页读取。", "\(name): Could not prepare tab collection."))
                continue
            }
            var scriptError: NSDictionary?
            let result = script.executeAndReturnError(&scriptError)
            if let scriptError {
                let code = (scriptError[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                if code == -1743 {
                    issues.append(L("\(name)：未获得自动化授权，可在系统设置 → 隐私与安全性 → 自动化中允许续桌读取。", "\(name): Automation access is off. Allow XuZhuo in System Settings → Privacy & Security → Automation."))
                } else if code == -1712 {
                    issues.append(L("\(name)：读取标签页超时，浏览器可能正忙。", "\(name): Tab collection timed out. The browser may be busy."))
                } else {
                    let message = scriptError[NSAppleScript.errorMessage] as? String ?? L("浏览器未返回标签页", "The browser returned no tabs.")
                    issues.append(L("\(name)：\(message)", "\(name): Could not read tabs (AppleScript error \(code.map(String.init) ?? "unknown"))."))
                }
                continue
            }
            var skipped = 0
            guard result.numberOfItems > 0 else { continue }
            for index in 1...result.numberOfItems {
                guard let pair = result.atIndex(index),
                      let location = pair.atIndex(2)?.stringValue,
                      let url = URL(string: location),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                    skipped += 1
                    continue
                }
                guard seen.insert(url.absoluteString).inserted else { continue }
                let title = pair.atIndex(1)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                resources.append(SceneResource(kind: .web,
                                               title: (title?.isEmpty == false ? title : nil) ?? url.host ?? L("网页", "Web page"),
                                               location: url.absoluteString))
            }
            if skipped > 0 { issues.append(L("\(name)：跳过了 \(skipped) 个内部页面或无法读取的标签页，仅保存 HTTP / HTTPS 网页。", "\(name): Skipped \(skipped) internal or unreadable tabs. Only HTTP / HTTPS pages were saved.")) }
        }
        return (resources, issues)
    }

    /// Captures only when permission is already granted; never prompts here.
    func captureDesktop() async -> (data: Data?, message: String?) {
        refreshPermissions()
        guard screenCaptureGranted else {
            return (nil, L("尚未开启屏幕录制权限，已保留布局示意。可在设置中开启真实桌面缩略图。", "Screen Recording access is off. A layout preview was kept. Enable access in Settings for desktop thumbnails."))
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                return (nil, L("没有可截取的显示器，已保留布局示意。", "No display is available to capture. A layout preview was kept."))
            }
            // Keep the save sheet itself out of the remembered desktop.
            let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = SCStreamConfiguration()
            let width = min(display.width, 1600)
            config.width = width
            config.height = max(1, Int(Double(display.height) * Double(width) / Double(max(display.width, 1))))
            config.showsCursor = false
            config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            guard let data else { return (nil, L("桌面截图编码失败，已保留布局示意。", "Could not encode the desktop image. A layout preview was kept.")) }
            return (data, nil)
        } catch {
            return (nil, L("桌面截图未完成：\(error.localizedDescription)。已保留布局示意。", "Desktop capture failed (\(Self.englishErrorCode(error))). A layout preview was kept."))
        }
    }

    /// Reopens resources and restores only matching titled windows. Other work
    /// remains open. A report reflects OS callbacks and accepted AX operations,
    /// not an assumption that an application's own document state was recovered.
    func restore(_ scene: WorkScene) async -> RestoreReport {
        refreshPermissions()
        var report = RestoreReport()
        var unavailableApps = Set<String>()
        let appGroups = Dictionary(grouping: scene.windows, by: \.bundleID)
        for bundleID in appGroups.keys.sorted() {
            guard let window = appGroups[bundleID]?.first else { continue }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.unhide()
                continue
            }
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                unavailableApps.insert(bundleID)
                report.issues.append(L("\(window.applicationName)：应用未安装，无法恢复窗口。", "\(window.applicationName): The app is not installed, so its windows could not be restored."))
                continue
            }
            if let issue = await launchApplication(at: appURL) {
                unavailableApps.insert(bundleID)
                report.issues.append(L("\(window.applicationName)：\(issue)", "\(window.applicationName): \(issue)"))
            }
        }

        for resource in scene.resources {
            guard let url = resource.resolvedURL() else {
                report.issues.append(L("“\(resource.title)”：地址无效，请重新添加资料。", "“\(resource.title)”: The location is invalid. Add this resource again."))
                continue
            }
            let scoped = resource.kind != .web && url.startAccessingSecurityScopedResource()
            if resource.kind != .web && !FileManager.default.fileExists(atPath: url.path) {
                if scoped { url.stopAccessingSecurityScopedResource() }
                report.issues.append(L("“\(resource.title)”：原文件已移动、删除或无法访问。", "“\(resource.title)”: The original file was moved, deleted, or is inaccessible."))
                continue
            }
            let issue = await openResource(url)
            if scoped { url.stopAccessingSecurityScopedResource() }
            if let issue {
                report.issues.append(L("“\(resource.title)”：\(issue)", "“\(resource.title)”: \(issue)"))
            } else {
                report.opened += 1
            }
        }

        guard !scene.windows.isEmpty else { return report }
        guard accessibilityGranted else {
            report.issues.append(L("未开启辅助功能权限，窗口位置与尺寸未恢复。资料打开不受影响。", "Accessibility access is off. Window positions and sizes were not restored; resources can still open."))
            return report
        }
        let restorableWindows = scene.windows.filter { !unavailableApps.contains($0.bundleID) }
        let savedGroups = Dictionary(grouping: restorableWindows) {
            WindowMatchKey(bundleID: $0.bundleID, title: normalizedTitle($0.title))
        }
        var pending: [SavedWindow] = []
        for windows in savedGroups.values {
            guard let saved = windows.first else { continue }
            if windows.count > 1 {
                report.issues.append(L("\(saved.applicationName) · \(saved.title)：存档中有多个同标题窗口，无法区分，未调整。", "\(saved.applicationName) · \(saved.title): The saved session has multiple windows with this title. Their layouts were left unchanged."))
            } else {
                pending.append(saved)
            }
        }
        var usedWindows: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(6)
        repeat {
            var remaining: [SavedWindow] = []
            for saved in pending {
                guard !normalizedTitle(saved.title).isEmpty,
                      let app = NSRunningApplication.runningApplications(withBundleIdentifier: saved.bundleID).first else {
                    remaining.append(saved)
                    continue
                }
                let candidates = accessibilityWindows(for: app).filter { candidate in
                          isOrdinaryWindow(candidate) && !boolAttribute(candidate, kAXMinimizedAttribute)
                          && !boolAttribute(candidate, "AXFullScreen")
                          && normalizedTitle(stringAttribute(candidate, kAXTitleAttribute) ?? "") == normalizedTitle(saved.title)
                          && !usedWindows.contains(where: { CFEqual($0, candidate) })
                }
                if candidates.count > 1 {
                    report.issues.append(L("\(saved.applicationName) · \(saved.title)：有多个同标题窗口，无法区分，未调整。", "\(saved.applicationName) · \(saved.title): Multiple open windows have this title. Their layouts were left unchanged."))
                    continue
                }
                guard let window = candidates.first else {
                    remaining.append(saved)
                    continue
                }
                usedWindows.append(window)
                if let issue = await positionWindow(window, from: saved) {
                    report.issues.append(L("\(saved.applicationName) · \(saved.title)：\(issue)", "\(saved.applicationName) · \(saved.title): \(issue)"))
                } else {
                    report.positioned += 1
                }
            }
            pending = remaining
            if pending.isEmpty || Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: 350_000_000)
        } while !Task.isCancelled
        for saved in pending {
            report.issues.append(L("\(saved.applicationName) · \(saved.title)：未找到同标题的普通窗口，未调整其它窗口。", "\(saved.applicationName) · \(saved.title): No standard window with this title was found. Other windows were left unchanged."))
        }
        return report
    }

    private func openResource(_ url: URL) async -> String? {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        let english = LanguageSettings.shared.language == .english
        let unconfirmed = L("系统未确认资料已打开。", "macOS did not confirm that the resource opened.")
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: config) { app, error in
                if let error {
                    continuation.resume(returning: english
                        ? "Could not open this resource (\(Self.englishErrorCode(error)))."
                        : error.localizedDescription)
                }
                else if app == nil { continuation.resume(returning: unconfirmed) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    private func launchApplication(at url: URL) async -> String? {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let english = LanguageSettings.shared.language == .english
        let unconfirmed = L("系统未确认应用已启动。", "macOS did not confirm that the app launched.")
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error {
                    continuation.resume(returning: english
                        ? "Could not launch this app (\(Self.englishErrorCode(error)))."
                        : error.localizedDescription)
                }
                else if app == nil { continuation.resume(returning: unconfirmed) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    /// Error codes remain useful when the app language differs from macOS.
    nonisolated private static func englishErrorCode(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private func accessibilityWindows(for app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.7)
        return attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ key: String) -> String? {
        attribute(element, key) as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ key: String) -> Bool {
        (attribute(element, key) as? NSNumber)?.boolValue ?? false
    }

    private func isOrdinaryWindow(_ element: AXUIElement) -> Bool {
        stringAttribute(element, kAXRoleAttribute) == kAXWindowRole
        && stringAttribute(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }

    private func normalizedTitle(_ title: String) -> String {
        title.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let positionRef = attribute(window, kAXPositionAttribute),
              let sizeRef = attribute(window, kAXSizeAttribute),
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func positionWindow(_ window: AXUIElement, from saved: SavedWindow) async -> String? {
        guard let frame = safeFrame(for: saved) else { return L("窗口坐标无效或没有可用显示器。", "The window coordinates are invalid or no display is available.") }
        var positionSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable) == .success,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              positionSettable.boolValue, sizeSettable.boolValue else {
            return L("应用不支持通过辅助功能调整该窗口的位置或尺寸。", "This app does not support changing this window’s position or size through Accessibility.")
        }
        var point = frame.origin
        var size = frame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else {
            return L("无法构造窗口布局。", "Could not create the window layout.")
        }
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        guard sizeResult == .success, positionResult == .success else {
            return L("应用没有接受完整布局（位置 \(positionResult.rawValue)，尺寸 \(sizeResult.rawValue)）。", "The app did not accept the complete layout (position \(positionResult.rawValue), size \(sizeResult.rawValue)).")
        }
        // Some apps accept AX writes but impose a minimum size or defer applying
        // them. Read the actual frame before counting a window as restored.
        for attempt in 0..<3 {
            if let actual = windowFrame(window),
               abs(actual.minX - frame.minX) <= 6, abs(actual.minY - frame.minY) <= 6,
               abs(actual.width - frame.width) <= 6, abs(actual.height - frame.height) <= 6 { return nil }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 120_000_000) }
        }
        return L("应用限制了窗口布局，未确认位置与尺寸完整恢复。", "The app restricted the layout. Its full position and size could not be confirmed.")
    }

    /// Accessibility uses a top-left coordinate system; NSScreen uses bottom-left.
    /// Choose the closest available display when a saved monitor is disconnected.
    private func safeFrame(for saved: SavedWindow) -> CGRect? {
        guard [saved.x, saved.y, saved.width, saved.height].allSatisfy(\.isFinite),
              saved.width > 0, saved.height > 0,
              let primary = NSScreen.screens.first else { return nil }
        let screens = NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            return CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY,
                          width: visible.width, height: visible.height)
        }
        let old = CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
        guard let screen = screens.max(by: { lhs, rhs in
            let leftIntersection = old.intersection(lhs)
            let rightIntersection = old.intersection(rhs)
            let leftArea = leftIntersection.isNull ? 0 : leftIntersection.width * leftIntersection.height
            let rightArea = rightIntersection.isNull ? 0 : rightIntersection.width * rightIntersection.height
            if leftArea != rightArea { return leftArea < rightArea }
            let center = CGPoint(x: old.midX, y: old.midY)
            let leftDistance = hypot(center.x - lhs.midX, center.y - lhs.midY)
            let rightDistance = hypot(center.x - rhs.midX, center.y - rhs.midY)
            return leftDistance > rightDistance
        }) else { return nil }
        let width = min(max(saved.width, 120), screen.width)
        let height = min(max(saved.height, 90), screen.height)
        return CGRect(x: min(max(saved.x, screen.minX), screen.maxX - width),
                      y: min(max(saved.y, screen.minY), screen.maxY - height), width: width, height: height)
    }
}
