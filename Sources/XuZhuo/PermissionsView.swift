import SwiftUI
import AppKit

@MainActor
struct PermissionsView: View {
    @ObservedObject var service: WorkspaceService
    @ObservedObject private var languageSettings = LanguageSettings.shared
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("设置", "Settings")).font(.system(size: 25, weight: .semibold))
                        Text(L("让续桌按你的习惯工作。", "Make XuZhuo feel at home.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("完成", "Done")) { if let onClose { onClose() } else { dismiss() } }
                        .keyboardShortcut(.defaultAction)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(L("语言", "Language"))
                    HStack {
                        Label(L("界面语言", "App Language"), systemImage: "globe").font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 20)
                        Picker(L("界面语言", "App Language"), selection: $languageSettings.language) {
                            ForEach(AppLanguage.allCases) { language in Text(language.nativeName).tag(language) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 228)
                    }.padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                    Text(L("切换后立即生效，项目名称和你写的备注保持原样。", "Changes apply immediately. Your project names and notes keep their original text."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(L("桌面恢复权限", "Desktop Permissions"))
                    VStack(spacing: 0) {
                        permissionRow(symbol: "macwindow.on.rectangle", title: L("辅助功能", "Accessibility"),
                                      description: L("保存窗口位置与尺寸；恢复时匹配应用和窗口标题。", "Save window positions and sizes; restore by matching the app and window title."),
                                      granted: service.accessibilityGranted, action: service.requestAccessibility)
                        Divider().padding(.horizontal, 16)
                        permissionRow(symbol: "photo.on.rectangle", title: L("屏幕录制", "Screen Recording"),
                                      description: L("保存主屏幕缩略图。未开启时显示布局示意。", "Save a thumbnail of your primary display. A layout preview is used without access."),
                                      granted: service.screenCaptureGranted, action: service.requestScreenCapture)
                        Divider().padding(.horizontal, 16)
                        HStack(alignment: .top, spacing: 13) {
                            permissionIcon("safari")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L("浏览器自动化", "Browser Automation")).font(.system(size: 13, weight: .semibold))
                                Text(L("保存时勾选 Safari / Chrome 标签后，macOS 会按需询问授权。网页在默认浏览器中重新打开。", "When you select Safari / Chrome tabs while saving, macOS requests access as needed. Links reopen in your default browser."))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Button(L("系统设置", "System Settings"), action: service.openAutomationSettings).controlSize(.small)
                        }.padding(16)
                    }.background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(L("恢复支持", "Restoration Support"))
                    VStack(alignment: .leading, spacing: 11) {
                        supportLine("checkmark.circle", L("文件、文件夹、网页和下一步备注；原资料保留在原处。", "Files, folders, web links, and next steps. Original resources stay in place."))
                        supportLine("macwindow", L("支持辅助功能的普通窗口。显示器变化时，布局会调整到可见屏幕内。", "Standard windows that support Accessibility. Layouts adjust to the visible screen when displays change."))
                        supportLine("info.circle", L("暂不恢复未保存的文档、应用内部状态和标签分组；不收录全屏、最小化和无标题窗口。", "Unsaved documents, in-app state, and tab groups are not restored. Full-screen, minimized, and untitled windows are excluded."))
                    }.padding(16).background(cardBackground, in: RoundedRectangle(cornerRadius: 13))
                }
                HStack(alignment: .top, spacing: 12) {
                    Label(L("本地保存 · 无需账号", "Stored locally · No account"), systemImage: "lock")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("刷新权限", "Refresh Access"), action: service.refreshPermissions).controlSize(.small)
                }
                Text(L("开启权限后若状态未更新，请完全退出并重新打开续桌。", "If access does not update after enabling it, quit and reopen XuZhuo."))
                    .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(28)
        }
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 610, height: 680)
        .environment(\.locale, languageSettings.language.locale)
        .onAppear { service.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in service.refreshPermissions() }
    }
    private var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
    private func permissionRow(symbol: String, title: String, description: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 13) {
            permissionIcon(symbol)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if granted { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green).accessibilityLabel(L("已开启", "Enabled")) }
                }
                Text(description).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(granted ? L("已授权", "Allowed") : L("前往开启", "Enable"), action: action).controlSize(.small).disabled(granted)
        }.padding(16)
    }
    private func permissionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary).frame(width: 32, height: 32)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
    private func supportLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 17).padding(.top, 1)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
