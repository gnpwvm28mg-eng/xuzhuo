import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct SaveSceneView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var store: SceneStore
    @ObservedObject var workspace: WorkspaceService
    let completion: (WorkScene, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var nextStep = ""
    @State private var tint = "sage"
    @State private var resources: [SceneResource] = []
    @State private var windows = false
    @State private var browserTabs = false
    @State private var screenshot = false
    @State private var showLink = false
    @State private var saving = false
    @State private var dropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("给此刻，留个存档。", "Save your place.")).font(.system(size: 23, weight: .semibold))
                    Text(L("资料、窗口、下一步。下次，一起接上。", "Files, windows, and your next step. Ready for your return."))
                        .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                }
                Spacer()
            }.padding(28)
            Divider().overlay(DeskStyle.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        formLabel(L("现场名称", "Scene Name"), hint: L("一个项目，一个存档点", "One project, one place to return to"))
                        TextField(L("比如：新产品方案", "For example: Product proposal"), text: $title).textFieldStyle(.plain)
                            .font(.system(size: 15)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 9))
                        HStack(spacing: 10) {
                            Text(L("封面颜色", "Cover Color")).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
                            ForEach(["sage", "clay", "blue", "lavender"], id: \.self) { color in
                                Button { tint = color } label: {
                                    Circle().fill(DeskStyle.tint(color)).frame(width: 19, height: 19)
                                        .padding(3).overlay(Circle().stroke(tint == color ? DeskStyle.ink : .clear, lineWidth: 1.3))
                                }.buttonStyle(.plain).accessibilityLabel(L("封面颜色 ", "Cover color ") + color)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        formLabel(L("下一步", "Next Step"), hint: L("留一句，回来就知道做什么", "A quick note for your return"))
                        TextEditor(text: $nextStep).accessibilityLabel(L("下一步", "Next Step")).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 66)
                            .padding(8).background(Color(hex: 0xEFEFDC), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(alignment: .topLeading) {
                                if nextStep.isEmpty { Text(L("下一步补预算…", "Finish the budget next…")).font(.system(size: 13)).foregroundStyle(DeskStyle.secondary).padding(13).allowsHitTesting(false) }
                            }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        formLabel(L("相关资料", "Resources"), hint: L("只保存引用，不移动原文件", "References only; original files stay in place"))
                        HStack {
                            Button { add(ResourceImport.chooseFiles()) } label: { Label(L("添加文件 / 文件夹", "Add Files / Folders"), systemImage: "paperclip") }.buttonStyle(SecondaryButtonStyle())
                            Button { showLink = true } label: { Label(L("添加网页", "Add Web Link"), systemImage: "link") }.buttonStyle(SecondaryButtonStyle())
                        }
                        ForEach(resources) { resource in
                            HStack(spacing: 8) {
                                Image(systemName: resource.kind.symbol).foregroundStyle(DeskStyle.green)
                                Text(resource.title).lineLimit(1)
                                Spacer()
                                Button { resources.removeAll { $0.id == resource.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DeskStyle.secondary) }.buttonStyle(.plain)
                                    .accessibilityLabel(L("移除资料 ", "Remove resource ") + resource.title)
                            }.font(.system(size: 11)).padding(9).background(.white, in: RoundedRectangle(cornerRadius: 7))
                        }
                        HStack { Image(systemName: "tray.and.arrow.down"); Text(L("也可以把资料拖到这里", "Or drop resources here")) }
                            .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(dropTarget ? DeskStyle.paleGreen : Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(DeskStyle.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier], isTargeted: $dropTarget) { providers in
                                ResourceImport.load(providers, completion: add); return true
                            }
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        formLabel(L("记录当前桌面", "Capture Desktop"), hint: L("可选，按系统授权情况保存", "Optional; requires system permissions"))
                        Toggle(isOn: $windows) { captureOption(L("常见应用窗口位置", "App Window Positions"), note: workspace.accessibilityGranted ? L("记录窗口标题、大小和位置", "Remember window titles, sizes, and positions") : L("先在「设置与恢复支持」中授予辅助功能权限", "Enable Accessibility in Settings & Permissions first"), symbol: "macwindow") }
                            .disabled(!workspace.accessibilityGranted)
                        Toggle(isOn: $browserTabs) { captureOption(L("Safari / Chrome 网页标签", "Safari / Chrome Tabs"), note: L("勾选后读取标签网址，macOS 可能请求自动化权限", "Read open tab URLs; macOS may ask for Automation access"), symbol: "safari") }
                        Toggle(isOn: $screenshot) { captureOption(L("桌面缩略图", "Desktop Thumbnail"), note: workspace.screenCaptureGranted ? L("保存主屏幕此刻的截图", "Capture the current primary display") : L("先在「设置与恢复支持」中授予屏幕录制权限", "Enable Screen Recording in Settings & Permissions first"), symbol: "photo") }
                            .disabled(!workspace.screenCaptureGranted)
                    }.toggleStyle(.checkbox)
                }.padding(28)
            }.frame(height: 470).disabled(saving)
            Divider().overlay(DeskStyle.line)
            HStack {
                Label(L("本地保存，无需账号", "Local storage. No account needed."), systemImage: "lock").font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle()).disabled(saving)
                Button { save() } label: {
                    HStack { if saving { ProgressView().controlSize(.small) }; Text(saving ? L("正在保存…", "Saving…") : L("保存现场", "Save Scene")) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }.padding(22)
        }.frame(width: 580).background(DeskStyle.background).foregroundStyle(DeskStyle.ink)
            .interactiveDismissDisabled(saving)
            .sheet(isPresented: $showLink) { AddLinkView { add([$0]) } }
            .onAppear { workspace.refreshPermissions(); windows = workspace.accessibilityGranted }
            .environment(\.locale, languageSettings.language.locale)
    }

    private func formLabel(_ title: String, hint: String) -> some View {
        HStack { Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Text(hint).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary) }
    }

    private func captureOption(_ title: String, note: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 16).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(note).font(.system(size: 9)).foregroundStyle(DeskStyle.secondary)
            }
        }
    }

    private func add(_ new: [SceneResource]) {
        for resource in new where !resources.contains(where: { $0.location == resource.location }) { resources.append(resource) }
    }

    private func save() {
        saving = true
        Task { @MainActor in
            var scene = WorkScene(title: title.trimmingCharacters(in: .whitespacesAndNewlines), tint: tint,
                                  nextStep: nextStep.trimmingCharacters(in: .whitespacesAndNewlines), resources: resources)
            var issues: [String] = []
            if windows {
                scene.windows = workspace.captureWindows()
                if scene.windows.isEmpty { issues.append(L("没有读取到可恢复的普通窗口", "No restorable app windows were found")) }
            }
            if browserTabs {
                let capture = workspace.captureBrowserTabs()
                for resource in capture.resources where !scene.resources.contains(where: { $0.location == resource.location }) { scene.resources.append(resource) }
                issues.append(contentsOf: capture.issues)
            }
            if screenshot {
                let capture = await workspace.captureDesktop()
                if let data = capture.data {
                    do { scene.thumbnailName = try store.storeThumbnail(data, for: scene.id) }
                    catch { issues.append(L("缩略图保存失败：", "Could not save thumbnail: ") + error.localizedDescription) }
                }
                if let message = capture.message { issues.append(message) }
            }
            let saved = store.save(scene)
            saving = false
            if saved { completion(scene, issues); dismiss() }
        }
    }
}

@MainActor
struct AddLinkView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let completion: (SceneResource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    private var validURL: URL? {
        guard let candidate = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(candidate.scheme?.lowercased() ?? ""), candidate.host != nil else { return nil }
        return candidate
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("收好一个网页", "Save a web link")).font(.system(size: 21, weight: .semibold))
            TextField("https://…", text: $url).textFieldStyle(.roundedBorder)
            TextField(L("网页名称（选填）", "Page title (optional)"), text: $title).textFieldStyle(.roundedBorder)
            Text(L("只保存链接，继续现场时在默认浏览器中打开。", "The saved link opens in your default browser when you resume."))
                .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button(L("添加网页", "Add Web Link")) {
                    guard let validURL, var resource = ResourceImport.resource(for: validURL) else { return }
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { resource.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                    completion(resource); dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(validURL == nil)
            }
        }.padding(28).frame(width: 450).background(DeskStyle.background).foregroundStyle(DeskStyle.ink)
            .environment(\.locale, languageSettings.language.locale)
    }
}

@MainActor
struct CheckpointView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let scene: WorkScene
    @ObservedObject var store: SceneStore
    let notify: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var nextStep = ""
    @State private var nextStepBaseline = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L("今天，先到这里。", "A good place to pause."), systemImage: "moon").font(.system(size: 23, weight: .medium))
            Text(L("用十秒，给下次的自己留一条线索。", "Take ten seconds to leave a clue for your return."))
                .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
            Text(L("做到哪里了？", "Where did you leave off?")).font(.system(size: 12, weight: .semibold))
            TextEditor(text: $note).accessibilityLabel(L("做到哪里了", "Where you left off")).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 95)
                .padding(9).background(.white, in: RoundedRectangle(cornerRadius: 9))
            Text(L("回来后，下一步", "Next time, start here")).font(.system(size: 12, weight: .semibold))
            TextField(L("接下来做什么？", "What comes next?"), text: $nextStep).textFieldStyle(.plain).padding(13)
                .background(Color(hex: 0xEFEFDC), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button(L("留下记录，收工", "Save Checkpoint")) {
                    guard var updated = store.scene(scene.id) else { return }
                    let checkpoint = SceneCheckpoint(note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                    updated.checkpoints.insert(checkpoint, at: 0)
                    if nextStep != nextStepBaseline { updated.nextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if store.save(updated) { notify(L("今天的进度已记下。下次见。", "Your progress is saved. See you next time.")); dismiss() }
                }.buttonStyle(PrimaryButtonStyle()).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width: 470).background(DeskStyle.background).foregroundStyle(DeskStyle.ink)
            .onAppear { nextStepBaseline = scene.localizedNextStep; nextStep = nextStepBaseline }
            .onChange(of: languageSettings.language) {
                if nextStep == nextStepBaseline { nextStepBaseline = scene.localizedNextStep; nextStep = nextStepBaseline }
            }
            .environment(\.locale, languageSettings.language.locale)
    }
}

@MainActor
struct ExportSceneView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let scene: WorkScene
    @ObservedObject var store: SceneStore
    let notify: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(L("把现场整理成资料包", "Package your scene"), systemImage: "shippingbox").font(.system(size: 21, weight: .semibold))
            Text(L("链接、下一步和收工记录会一起导出。\n勾选的文件会复制进包，原资料保留在原处。", "Links, next steps, and checkpoints are included.\nSelected files are copied; the originals stay in place."))
                .font(.system(size: 12)).lineSpacing(5).foregroundStyle(DeskStyle.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(scene.resources) { resource in
                        HStack {
                            if resource.kind == .web {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(DeskStyle.green)
                            } else {
                                Toggle("", isOn: Binding(get: { selected.contains(resource.id) }, set: { value in
                                    if value { selected.insert(resource.id) } else { selected.remove(resource.id) }
                                })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel(L("包含文件 ", "Include file ") + scene.localizedResourceTitle(resource))
                            }
                            Image(systemName: resource.kind.symbol).foregroundStyle(DeskStyle.secondary)
                            Text(scene.localizedResourceTitle(resource)).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            if resource.kind == .web { Text(L("链接", "Link")).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary) }
                        }
                    }
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 9))
            }.frame(maxHeight: 220)
            Text(L("资料包是一个文件夹，包含说明、网页链接、存档数据和选定文件。", "The package includes a readme, web links, scene data, and selected files."))
                .font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
            if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button(L("选择位置并导出", "Choose Location & Export")) { export() }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(30).frame(width: 510).background(DeskStyle.background).foregroundStyle(DeskStyle.ink)
            .environment(\.locale, languageSettings.language.locale)
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.title = L("选择资料包的保存位置", "Choose where to save the package")
        panel.prompt = L("导出到这里", "Export Here")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var package = scene
            package.resources = scene.resources.filter { $0.kind == .web || selected.contains($0.id) }
            let result = try store.export(scene: package, to: url, includeFiles: !selected.isEmpty)
            NSWorkspace.shared.activateFileViewerSelecting([result])
            notify(L("资料包已导出：", "Package exported: ") + result.lastPathComponent)
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
