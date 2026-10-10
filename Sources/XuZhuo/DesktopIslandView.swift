import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum IslandPage: Hashable {
    case scenes
    case save
    case checkpoint(UUID)
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var page: IslandPage = .scenes
    @Published var status: String?
    @Published var busy = false
    @Published var activeID: UUID?
    @Published var isDragging = false
    @Published var saveRequest = UUID()
}

/// A desktop shelf with one focused workspace and a compact scene dock.
@MainActor
struct DesktopIslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var store: SceneStore
    @ObservedObject var workspace: WorkspaceService
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let onManage: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    @State private var draftTitle = ""
    @State private var draftNextStep = ""
    @State private var draftResources: [SceneResource] = []
    @State private var draftURL = ""
    @State private var captureWindows = true
    @State private var captureBrowserTabs = false
    @State private var captureScreenshot = false
    @State private var checkpointNote = ""
    @State private var checkpointNextStep = ""
    @State private var checkpointNextStepBaseline = ""
    @State private var reportIssues: [String] = []
    @State private var resourceSceneID: UUID?
    @State private var dropTarget = false
    @State private var hoveredSceneID: UUID?

    private let accent = Color(hex: 0x90D4FF)
    private let muted = Color.white.opacity(0.48)
    private let card = Color.white.opacity(0.035)
    private var activeScene: WorkScene? {
        model.activeID.flatMap { store.scene($0) } ?? store.scenes.first
    }
    private var trimmedTitle: String { draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }
    private var corner: CGFloat { model.expanded ? 30 : 22 }

    var body: some View {
        Group {
            if model.expanded {
                VStack(spacing: 0) {
                    header
                    if model.page == .scenes {
                        scenesPage
                    } else {
                        hairline
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                statusMessages
                                switch model.page {
                                case .save: savePage
                                case .checkpoint(let id): checkpointPage(id)
                                case .scenes: EmptyView()
                                }
                            }
                            .padding(.horizontal, 23).padding(.vertical, 20)
                        }
                        .scrollIndicators(.hidden).id(model.page)
                    }
                    footer
                }
                .frame(width: IslandPlacement.expandedSize.width,
                       height: model.page == .scenes ? IslandPlacement.expandedSize.height : IslandPlacement.workflowSize.height)
            } else {
                collapsed.frame(width: 196, height: 44)
            }
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
                LinearGradient(colors: [Color(hex: 0x20242E).opacity(reduceTransparency ? 1 : 0.94),
                                        Color(hex: 0x11131B).opacity(reduceTransparency ? 1 : 0.96),
                                        Color(hex: 0x0C0D13).opacity(reduceTransparency ? 1 : 0.98)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if !reduceTransparency {
                    RadialGradient(colors: [Color(hex: 0x5B7DA3).opacity(model.expanded ? 0.12 : 0.04), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 330)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.08),
                                                Color.white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .animation(motion, value: model.activeID)
        .animation(motion, value: resourceSceneID)
        .onAppear { workspace.refreshPermissions() }
        .onChange(of: model.expanded) { _, expanded in
            if expanded {
                workspace.refreshPermissions()
                if model.activeID == nil { model.activeID = store.scenes.first?.id }
            }
        }
        .onChange(of: model.saveRequest) { _, _ in beginSave() }
        .onChange(of: languageSettings.language) { _, _ in
            if case .checkpoint(let id) = model.page,
               let scene = store.scene(id), checkpointNextStep == checkpointNextStepBaseline {
                checkpointNextStep = scene.localizedNextStep
                checkpointNextStepBaseline = checkpointNextStep
            }
        }
        .onChange(of: store.scenes.map(\.id)) { _, ids in
            if let active = model.activeID, !ids.contains(active) { model.activeID = store.scenes.first?.id }
        }
    }

    private var collapsed: some View {
        Button {
            guard !model.busy else { return }
            model.expanded = true
        } label: {
            HStack(spacing: 9) {
                LiquidSceneIcon(symbol: "play.fill", compact: true).frame(width: 23, height: 23)
                Text(activeScene?.localizedTitle ?? L("续桌", "Resume"))
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if model.busy {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 8)
                } else {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(muted)
                }
            }.padding(.horizontal, 14).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("展开续桌桌面岛", "Expand Resume island"))
        .help(L("点击展开；按住顶部中央可拖动位置", "Click to expand; drag the top center to move"))
        .onDrop(of: dropTypes, isTargeted: nil) { providers in
            guard !model.busy else { return false }
            model.expanded = true
            guard let id = activeScene?.id else {
                model.status = L("先选一个现场，再把资料拖进来。", "Choose a workspace before adding items.")
                return false
            }
            model.activeID = id
            return importResources(providers, into: id)
        }
    }

    /// The top center remains clear for the panel's native dragging handle.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                LiquidSceneIcon(symbol: "play.fill", compact: true).frame(width: 20, height: 20)
                Text(L("续桌", "Resume")).font(.system(size: 11, weight: .semibold)).tracking(0.2)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            languagePicker
            Button {
                guard !model.busy else { return }
                model.expanded = false
            } label: {
                Image(systemName: "chevron.up").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(muted).frame(width: 26, height: 26)
            }.buttonStyle(.plain).disabled(model.busy).padding(.leading, 8)
                .accessibilityLabel(L("收起桌面岛", "Collapse island"))
        }.padding(.horizontal, 22).frame(height: 44)
            .overlay {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 24, height: 2.5)
                    .allowsHitTesting(false)
            }
    }

    private var languagePicker: some View {
        HStack(spacing: 1) {
            languageButton("中", language: .chinese)
            languageButton("EN", language: .english)
        }
        .padding(2).background(Color.white.opacity(0.045), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 0.5))
        .disabled(model.busy)
    }

    private func languageButton(_ text: String, language: AppLanguage) -> some View {
        Button {
            languageSettings.language = language
        } label: {
            Text(text).font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.white.opacity(languageSettings.language == language ? 0.94 : 0.37))
                .frame(width: 24, height: 18)
                .background(Color.white.opacity(languageSettings.language == language ? 0.12 : 0), in: Capsule())
        }.buttonStyle(.plain)
            .accessibilityLabel(language == .chinese ? "切换为简体中文" : "Switch to English")
            .accessibilityAddTraits(languageSettings.language == language ? .isSelected : [])
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.page {
        case .scenes: scenesFooter
        case .save:
            workflowFooter(L("保存现场", "Save workspace"), symbol: "rectangle.stack.badge.plus", disabled: trimmedTitle.isEmpty,
                           action: saveScene)
        case .checkpoint(let id):
            workflowFooter(L("留下记录，收工", "Save & wrap up"), symbol: "moon.fill",
                           disabled: checkpointNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.scene(id) == nil) {
                saveCheckpoint(id)
            }
        }
    }

    private var scenesFooter: some View {
        HStack(spacing: 14) {
            Button(action: beginSave) {
                Label(L("保存现场", "Save workspace"), systemImage: "plus")
                    .font(.system(size: 10, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.77))
            Spacer()
            Button(action: onManage) { Image(systemName: "square.grid.2x2").font(.system(size: 11)) }
                .accessibilityLabel(L("管理全部存档", "Manage all workspaces"))
                .help(L("管理全部存档", "Manage all workspaces"))
            Button(action: onSettings) { Image(systemName: "slider.horizontal.3").font(.system(size: 11)) }
                .accessibilityLabel(L("权限与设置", "Permissions & settings"))
                .help(L("权限与设置", "Permissions & settings"))
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 0.5, height: 10)
            Label(L("本机", "Local"), systemImage: "lock.fill").font(.system(size: 8))
                .foregroundStyle(Color.white.opacity(0.29))
        }
        .buttonStyle(.plain).foregroundStyle(muted)
        .padding(.horizontal, 26).frame(height: 43)
        .disabled(model.busy)
    }

    private func workflowFooter(_ title: String, symbol: String, disabled: Bool,
                                action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            hairline
            HStack(spacing: 12) {
                Button(L("取消", "Cancel")) {
                    guard !model.busy else { return }
                    model.page = .scenes
                    model.status = nil
                    reportIssues = []
                }.buttonStyle(IslandButtonStyle())
                Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
                    .buttonStyle(IslandButtonStyle(primary: true)).disabled(disabled)
            }.padding(.horizontal, 23).frame(height: 64)
        }.background(Color.black.opacity(0.10)).disabled(model.busy)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if model.busy {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(accent)
                Text(model.status ?? L("正在处理现场…", "Working on your workspace…"))
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.75))
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(card, in: RoundedRectangle(cornerRadius: 10))
        } else if let status = model.status {
            Label(status, systemImage: reportIssues.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 11)).lineSpacing(3)
                .foregroundStyle(reportIssues.isEmpty ? Color.white.opacity(0.72) : Color(hex: 0xEDD1A3))
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(card, in: RoundedRectangle(cornerRadius: 10))
        }
        if !reportIssues.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(reportIssues.enumerated()), id: \.offset) { _, issue in
                    Text("• " + issue).font(.system(size: 10)).lineSpacing(3)
                }
            }.foregroundStyle(Color(hex: 0xEDD1A3))
        }
        if let error = store.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10)).lineSpacing(3).foregroundStyle(Color(hex: 0xFFB4A4))
                .padding(12).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var scenesPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    statusMessages
                    if let scene = activeScene {
                        sceneHero(scene)
                        if resourceSceneID == scene.id { resourceList(scene) }
                    } else {
                        emptyScene
                    }
                }
                .padding(.horizontal, 26).padding(.top, 17).padding(.bottom, 10)
            }.scrollIndicators(.hidden)
            if !store.scenes.isEmpty { sceneDock }
        }
        .onDrop(of: dropTypes, isTargeted: $dropTarget) { providers in
            guard !model.busy, let id = activeScene?.id else { return false }
            model.activeID = id
            return importResources(providers, into: id)
        }
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .padding(12).allowsHitTesting(false)
            }
        }
        .disabled(model.busy)
    }

    private var emptyScene: some View {
        HStack(spacing: 24) {
            LiquidSceneIcon(symbol: "play.fill").frame(width: 91, height: 91)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("留住这一刻", "Pick up where you left off"))
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("资料与下一步，都在这里等你。", "Your files and next step, ready when you are."))
                    .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3)
                Button(action: beginSave) { Label(L("第一个现场", "Your first workspace"), systemImage: "plus") }
                    .buttonStyle(IslandButtonStyle(primary: true)).padding(.top, 4)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
    }

    private func sceneHero(_ scene: WorkScene) -> some View {
        HStack(alignment: .top, spacing: 23) {
            heroArtwork(scene).frame(width: 91, height: 91).padding(.top, 13)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(L("当前现场", "CURRENT WORKSPACE"))
                        .font(.system(size: 8, weight: .medium)).tracking(languageSettings.language == .english ? 1.1 : 0.8)
                        .foregroundStyle(muted)
                    if scene.isDemo {
                        Text(L("示例", "DEMO")).font(.system(size: 7, weight: .medium)).foregroundStyle(Color.white.opacity(0.35))
                    }
                }.padding(.bottom, 8)
                Text(scene.localizedTitle).font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                    .lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(Color.white.opacity(0.97))
                    .padding(.bottom, 9)
                Text(scene.nextStep.isEmpty ? L("记下下一步，下次从这里继续。", "Leave a next step for your return.") : scene.localizedNextStep)
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.60)).lineSpacing(4)
                    .lineLimit(2).frame(height: 33, alignment: .top)
                    .padding(.bottom, 15)
                HStack(spacing: 7) {
                    Button { restore(scene) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "play.fill").font(.system(size: 8, weight: .semibold))
                            Text(L("继续现场", "Continue"))
                        }
                    }.buttonStyle(IslandButtonStyle(primary: true))
                    Button { beginCheckpoint(scene) } label: { Image(systemName: "moon").frame(width: 10) }
                        .buttonStyle(IslandButtonStyle())
                        .accessibilityLabel(L("记一句，收工", "Leave a note & wrap up"))
                        .help(L("记一句，收工", "Leave a note & wrap up"))
                    Button {
                        resourceSceneID = resourceSceneID == scene.id ? nil : scene.id
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "paperclip")
                            Text("\(scene.resources.count)").monospacedDigit()
                        }
                    }.buttonStyle(IslandButtonStyle())
                        .accessibilityLabel(L("展开资料，\(scene.resources.count) 项", scene.resources.count == 1 ? "Show 1 item" : "Show \(scene.resources.count) items"))
                        .help(L("查看资料 · 拖入可添加", "View items · Drag to add"))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(scene.id)
        .transition(.opacity)
    }

    private func heroArtwork(_ scene: WorkScene) -> some View {
        Group {
            if let image = store.thumbnailURL(for: scene).flatMap({ NSImage(contentsOf: $0) }) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 91, height: 72).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.25), lineWidth: 0.7))
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
                    .accessibilityLabel(L("保存时的桌面截图", "Saved desktop screenshot"))
            } else {
                LiquidSceneIcon(symbol: scene.symbol, tint: scene.tint)
                    .accessibilityLabel(L("项目图标", "Workspace icon"))
            }
        }.accessibilityElement(children: .ignore)
    }

    private var sceneDock: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.scenes) { scene in
                    let selected = activeScene?.id == scene.id
                    Button {
                        model.activeID = scene.id
                        resourceSceneID = nil
                        model.status = nil
                        reportIssues = []
                    } label: {
                        HStack(spacing: 9) {
                            sceneThumbnail(scene)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(scene.localizedTitle).font(.system(size: 10, weight: selected ? .medium : .regular))
                                    .lineLimit(1).foregroundStyle(Color.white.opacity(selected ? 0.96 : 0.59))
                                HStack(spacing: 4) {
                                    Circle().fill(selected ? accent : Color.white.opacity(0.18)).frame(width: 3, height: 3)
                                    Text(selected ? L("已选中", "Selected") : L("\(scene.resources.count) 项资料", scene.resources.count == 1 ? "1 item" : "\(scene.resources.count) items"))
                                        .font(.system(size: 8)).foregroundStyle(Color.white.opacity(selected ? 0.48 : 0.30))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 8).frame(width: 160, height: 52)
                        .background(Color.white.opacity(selected ? 0.08 : (hoveredSceneID == scene.id ? 0.04 : 0.018)),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(selected ? 0.16 : 0.035), lineWidth: 0.6))
                        .contentShape(RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(L("切换到\(scene.localizedTitle)", "Switch to \(scene.localizedTitle)"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .onHover { hoveredSceneID = $0 ? scene.id : nil }
                        .onDrop(of: dropTypes, isTargeted: nil) { providers in
                            guard !model.busy else { return false }
                            model.activeID = scene.id
                            return importResources(providers, into: scene.id)
                        }
                }
            }.padding(.horizontal, 23).padding(.vertical, 8)
        }.scrollIndicators(.hidden).frame(height: 68)
    }

    private func sceneThumbnail(_ scene: WorkScene) -> some View {
        Group {
            if let image = store.thumbnailURL(for: scene).flatMap({ NSImage(contentsOf: $0) }) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LiquidSceneIcon(symbol: scene.symbol, tint: scene.tint, compact: true)
            }
        }.frame(width: 32, height: 32).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private func resourceList(_ scene: WorkScene) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L("现场资料", "WORKSPACE ITEMS")).font(.system(size: 8, weight: .medium)).tracking(0.7)
                Spacer()
                Text(L("\(scene.windows.count) 个窗口", scene.windows.count == 1 ? "1 window" : "\(scene.windows.count) windows")).font(.system(size: 9))
            }.foregroundStyle(muted).padding(.bottom, 9)
            if scene.resources.isEmpty {
                Text(L("拖入文件、文件夹或链接。", "Drop files, folders, or links here."))
                    .font(.system(size: 11)).foregroundStyle(muted).padding(.vertical, 7)
            }
            ForEach(scene.resources) { resource in
                Button { openResource(resource, in: scene) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: resource.kind.symbol).frame(width: 15).foregroundStyle(accent.opacity(0.7))
                        Text(scene.localizedResourceTitle(resource)).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(muted)
                    }.font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.76))
                        .padding(.vertical, 9).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Button { chooseResources(for: scene.id) } label: {
                Label(L("添加文件或文件夹", "Add files or folders"), systemImage: "plus")
                    .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.65)).padding(.top, 9)
            }.buttonStyle(.plain)
        }.padding(.top, 9).padding(.bottom, 8)
    }

    private var savePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeading(L("保存现场", "Save workspace"), subtitle: L("文件、网页与工作进度", "Files, links, and your next step"))
            VStack(alignment: .leading, spacing: 12) {
                field(L("项目名称", "Workspace name"), placeholder: L("为这个现场命名", "Name this workspace"), text: $draftTitle)
                hairline
                field(L("下一步", "Next step"), placeholder: L("回来后先做什么？", "What will you do when you return?"), text: $draftNextStep)
            }.padding(13).background(card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.065), lineWidth: 0.6))
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    sectionLabel(L("资料", "Items"))
                    Text("\(draftResources.count)").font(.system(size: 10)).foregroundStyle(muted)
                    Spacer()
                    Button {
                        guard !model.busy else { return }
                        model.busy = true
                        appendDraftResources(ResourceImport.chooseFiles())
                        model.busy = false
                    } label: { Label(L("选择文件", "Choose files"), systemImage: "paperclip") }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.70))
                        .accessibilityLabel(L("选择文件或文件夹", "Choose files or folders"))
                }
                ForEach(draftResources) { resource in
                    HStack(spacing: 8) {
                        Image(systemName: resource.kind.symbol).foregroundStyle(muted).frame(width: 13)
                        Text(resource.title).lineLimit(1)
                        Spacer()
                        Button { draftResources.removeAll { $0.id == resource.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(muted)
                        }.buttonStyle(.plain).accessibilityLabel(L("移除 \(resource.title)", "Remove \(resource.title)"))
                    }.font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.78))
                }
                HStack(spacing: 9) {
                    Image(systemName: "link").font(.system(size: 11)).foregroundStyle(muted)
                    TextField(L("粘贴网页链接", "Paste a web link"), text: $draftURL).textFieldStyle(.plain)
                        .font(.system(size: 11)).onSubmit(addDraftURL)
                    Button(action: addDraftURL) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 16))
                            .foregroundStyle(Color.white.opacity(validDraftURL == nil ? 0.15 : 0.65))
                    }.buttonStyle(.plain).disabled(validDraftURL == nil)
                        .accessibilityLabel(L("添加网页链接", "Add web link"))
                }.padding(11).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                Text(L("也可将文件、文件夹或链接拖到这里。", "You can also drop files, folders, or links here."))
                    .font(.system(size: 10)).foregroundStyle(muted)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(dropTarget ? accent.opacity(0.06) : card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(dropTarget ? accent.opacity(0.4) : Color.white.opacity(0.065), lineWidth: 0.6))
                .onDrop(of: dropTypes, isTargeted: $dropTarget) { providers in
                    guard !model.busy else { return false }
                    model.busy = true
                    ResourceImport.load(providers) { resources in
                        appendDraftResources(resources)
                        model.busy = false
                        if resources.isEmpty { model.status = L("请拖入文件或有效的 HTTP / HTTPS 链接。", "Drop files or valid HTTP / HTTPS links.") }
                    }
                    return true
                }
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(L("额外记录", "Also capture"))
                captureOption(L("窗口布局", "Window layout"), detail: workspace.accessibilityGranted ? L("常见应用的窗口位置与尺寸", "Position and size of supported windows") : L("需辅助功能权限", "Requires Accessibility permission"), value: $captureWindows,
                              enabled: workspace.accessibilityGranted)
                captureOption(L("浏览器标签页", "Browser tabs"), detail: L("Safari / Chrome，可能请求自动化授权", "Safari / Chrome; may request Automation permission"), value: $captureBrowserTabs)
                captureOption(L("桌面缩略图", "Desktop thumbnail"), detail: workspace.screenCaptureGranted ? L("保存时截图，自动排除续桌", "Capture your desktop, excluding Resume") : L("需屏幕录制权限", "Requires Screen Recording permission"), value: $captureScreenshot,
                              enabled: workspace.screenCaptureGranted)
            }.padding(.horizontal, 2)
            Label(L("本机保存 · 原资料保留原位", "Stored locally · Original items stay in place"), systemImage: "lock")
                .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.32))
        }.disabled(model.busy)
    }

    private func checkpointPage(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeading(L("收工记录", "Wrap up"), subtitle: store.scene(id)?.localizedTitle ?? L("现场已被移除", "Workspace was removed"))
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(L("做到哪里了？", "Where did you leave off?"))
                TextEditor(text: $checkpointNote).font(.system(size: 13)).scrollContentBackground(.hidden)
                    .lineSpacing(4).frame(height: 118)
                    .overlay(alignment: .topLeading) {
                        if checkpointNote.isEmpty {
                            Text(L("记下今天的进度…", "Leave a note about today…")).font(.system(size: 13)).foregroundStyle(muted)
                                .padding(.leading, 5).padding(.top, 1).allowsHitTesting(false)
                        }
                    }.accessibilityLabel(L("收工进度", "Progress note"))
            }.padding(13).background(card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.065), lineWidth: 0.6))
            field(L("下一步", "Next step"), placeholder: L("下一次先做什么？", "What is your next step?"), text: $checkpointNextStep)
                .padding(13).background(card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.065), lineWidth: 0.6))
            HStack(spacing: 7) {
                Image(systemName: "moon").font(.system(size: 11))
                Text(L("回来时，提醒会和资料一起打开。", "Your next step will be waiting with your files."))
                    .font(.system(size: 10))
            }.foregroundStyle(muted).padding(.horizontal, 2)
        }.disabled(model.busy)
    }

    private func pageHeading(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                guard !model.busy else { return }
                model.page = .scenes
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64)).frame(width: 24, height: 28)
            }.buttonStyle(.plain).accessibilityLabel(L("返回现场", "Back to workspaces"))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 18, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
            }
            Spacer()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.54))
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            TextField(placeholder, text: text).textFieldStyle(.plain).font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.91)).accessibilityLabel(title)
        }
    }

    private func captureOption(_ title: String, detail: String, value: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.82))
                Text(detail).font(.system(size: 9)).foregroundStyle(muted)
            }.opacity(enabled ? 1 : 0.5)
            Spacer(minLength: 0)
            Toggle(title, isOn: value).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                .tint(accent).disabled(!enabled).accessibilityLabel(title)
        }
    }

    private func beginSave() {
        workspace.refreshPermissions()
        draftTitle = ""
        draftNextStep = ""
        draftResources = []
        draftURL = ""
        captureWindows = workspace.accessibilityGranted
        captureBrowserTabs = false
        captureScreenshot = false
        model.status = nil
        reportIssues = []
        model.page = .save
    }

    private func beginCheckpoint(_ scene: WorkScene) {
        checkpointNote = ""
        checkpointNextStep = scene.localizedNextStep
        checkpointNextStepBaseline = checkpointNextStep
        reportIssues = []
        model.status = nil
        model.page = .checkpoint(scene.id)
    }

    private var dropTypes: [String] {
        [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier]
    }

    private var validDraftURL: URL? {
        guard let url = URL(string: draftURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    private func addDraftURL() {
        guard let url = validDraftURL, let resource = ResourceImport.resource(for: url) else { return }
        appendDraftResources([resource])
        draftURL = ""
    }

    private func appendDraftResources(_ resources: [SceneResource]) {
        for resource in resources {
            let canonical = resource.resolvedURL()?.standardized.absoluteString ?? resource.location
            if !draftResources.contains(where: {
                $0.kind == resource.kind && ($0.resolvedURL()?.standardized.absoluteString ?? $0.location) == canonical
            }) { draftResources.append(resource) }
        }
    }

    private func saveScene() {
        guard !model.busy, !trimmedTitle.isEmpty else { return }
        model.busy = true
        model.status = L("正在保存此刻…", "Saving this moment…")
        reportIssues = []
        Task { @MainActor in
            var scene = WorkScene(title: trimmedTitle,
                                  nextStep: draftNextStep.trimmingCharacters(in: .whitespacesAndNewlines),
                                  resources: draftResources)
            var issues: [String] = []
            if captureWindows {
                scene.windows = workspace.captureWindows()
                if scene.windows.isEmpty { issues.append(L("没有读取到可恢复的普通窗口。", "No supported windows could be captured.")) }
            }
            if captureBrowserTabs {
                let result = workspace.captureBrowserTabs()
                for resource in result.resources where !scene.resources.contains(where: { $0.location == resource.location }) {
                    scene.resources.append(resource)
                }
                issues.append(contentsOf: result.issues)
            }
            if captureScreenshot {
                let result = await workspace.captureDesktop()
                if let data = result.data {
                    do { scene.thumbnailName = try store.storeThumbnail(data, for: scene.id) }
                    catch { issues.append(L("缩略图未保存：\(error.localizedDescription)", "Thumbnail was not saved: \(error.localizedDescription)")) }
                }
                if let message = result.message { issues.append(message) }
            }
            if store.save(scene) {
                model.activeID = scene.id
                model.page = .scenes
                model.status = issues.isEmpty ? L("「\(scene.localizedTitle)」已收好，下次从这里继续。", "\(scene.localizedTitle) is saved. Continue here next time.") : L("现场已保存，以下内容未完整记录。", "Workspace saved. Some items could not be captured.")
                reportIssues = issues
            } else {
                model.status = L("现场尚未保存，请检查下方原因。", "Workspace was not saved. See the details below.")
            }
            model.busy = false
        }
    }

    private func saveCheckpoint(_ id: UUID) {
        guard !model.busy, var scene = store.scene(id) else { return }
        let note = checkpointNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        model.busy = true
        if checkpointNextStep != checkpointNextStepBaseline {
            scene.nextStep = checkpointNextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        scene.checkpoints.insert(SceneCheckpoint(note: note), at: 0)
        if store.save(scene) {
            model.page = .scenes
            model.activeID = id
            model.status = L("今天的进度已记下。下次见。", "Progress saved. See you next time.")
            reportIssues = []
        } else { model.status = L("收工记录尚未保存，请检查下方原因。", "Your note was not saved. See the details below.") }
        model.busy = false
    }

    private func restore(_ scene: WorkScene) {
        guard !model.busy else { return }
        model.activeID = scene.id
        model.busy = true
        model.status = L("正在接回「\(scene.localizedTitle)」…", "Resuming \(scene.localizedTitle)…")
        reportIssues = []
        Task { @MainActor in
            let report = await workspace.restore(scene)
            var issues = report.issues
            if scene.resources.isEmpty && scene.windows.isEmpty {
                issues.append(L("这张现场还没有资料或窗口布局，可以先添加资料。", "This workspace has no items or saved windows yet. Add some items to get started."))
            }
            if !store.markOpened(scene.id) {
                issues.append(L("本次打开时间尚未保存，请检查本地存档错误。", "The opened time could not be saved. Check the local storage error."))
            }
            model.status = L("已打开 \(report.opened) 项资料，恢复 \(report.positioned) 个窗口。", "Opened \(report.opened) items and restored \(report.positioned) windows.")
            reportIssues = issues
            if issues.isEmpty {
                try? await Task.sleep(nanoseconds: 700_000_000)
                model.busy = false
                model.expanded = false
            } else {
                model.busy = false
                model.expanded = true
            }
        }
    }

    private func openResource(_ resource: SceneResource, in scene: WorkScene) {
        guard !model.busy else { return }
        model.busy = true
        model.status = L("正在打开「\(scene.localizedResourceTitle(resource))」…", "Opening \(scene.localizedResourceTitle(resource))…")
        reportIssues = []
        Task { @MainActor in
            var single = scene
            single.resources = [resource]
            single.windows = []
            let report = await workspace.restore(single)
            reportIssues = report.issues
            model.status = report.opened == 1 ? L("「\(scene.localizedResourceTitle(resource))」已打开。", "\(scene.localizedResourceTitle(resource)) is open.") : L("资料未完整打开，请检查下方原因。", "Some items could not be opened. See the details below.")
            model.busy = false
        }
    }

    private func chooseResources(for id: UUID) {
        guard !model.busy else { return }
        model.busy = true
        let resources = ResourceImport.chooseFiles()
        if !resources.isEmpty { saveImportedResources(resources, into: id) }
        model.busy = false
    }

    private func importResources(_ providers: [NSItemProvider], into id: UUID) -> Bool {
        guard !model.busy else { return false }
        model.busy = true
        ResourceImport.load(providers) { resources in
            saveImportedResources(resources, into: id)
            model.busy = false
        }
        return true
    }

    private func saveImportedResources(_ resources: [SceneResource], into id: UUID) {
        reportIssues = []
        guard !resources.isEmpty else {
            model.status = L("请拖入文件或有效的 HTTP / HTTPS 链接。", "Drop files or valid HTTP / HTTPS links.")
            return
        }
        guard let scene = store.scene(id) else {
            model.status = L("这个现场已被移除，请重新选择。", "This workspace was removed. Choose another one.")
            return
        }
        let before = scene.resources.count
        if store.addResources(resources, to: id) {
            let added = (store.scene(id)?.resources.count ?? before) - before
            model.status = added == 0 ? L("这些资料已经收在这个现场了。", "These items are already in this workspace.") : L("已收好 \(added) 项资料，原文件仍在原位。", "Added \(added) items. Original files stay in place.")
        } else { model.status = L("资料引用尚未保存，请检查下方原因。", "Item references were not saved. See the details below.") }
    }
}

/// A small vector icon: colored glass windows over an inky rounded tile.
/// Highlights follow the same light direction as the app icon.
private struct LiquidSceneIcon: View {
    var symbol: String
    var tint: String = "sky"
    var compact = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var front: Color {
        tint == "peach" ? Color(hex: 0xD6AAFF) : (tint == "sage" ? Color(hex: 0x79E2D1) : Color(hex: 0x65CFFF))
    }
    private var back: Color { tint == "peach" ? Color(hex: 0xFF8F9C) : Color(hex: 0x987AF7) }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x27374B), Color(hex: 0x182137), Color(hex: 0x101827)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05), front.opacity(0.2)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                Ellipse().fill(front.opacity(0.20)).blur(radius: 17).frame(width: 70, height: 28).offset(y: 28)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [back.opacity(0.95), back.opacity(0.45), Color(hex: 0x483B89)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.8), back.opacity(0.15), .white.opacity(0.22)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                    .frame(width: 59, height: 44).rotationEffect(.degrees(-12)).offset(x: -8, y: -10)
                    .shadow(color: .black.opacity(0.24), radius: 5, y: 4)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [front.opacity(0.94), front.opacity(0.66), Color(hex: 0x2B6D9C).opacity(0.91)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(stops: [.init(color: .white.opacity(0.34), location: 0),
                                                    .init(color: .white.opacity(0.04), location: 0.46),
                                                    .init(color: .white.opacity(0.17), location: 1)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if !compact {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.60)).frame(width: 2.4, height: 2.4) }
                            Spacer()
                        }.padding(.horizontal, 8).frame(maxHeight: .infinity, alignment: .top).padding(.top, 7)
                        Rectangle().fill(Color.white.opacity(0.19)).frame(height: 0.5).offset(y: -9)
                    }
                    Image(systemName: symbol).font(.system(size: compact ? 23 : 19, weight: .medium))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(Color.white.opacity(0.96))
                        .shadow(color: Color(hex: 0x195A87).opacity(0.35), radius: 1, y: 1).offset(y: compact ? 0 : 5)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.15), Color.white.opacity(0.46)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
                }.frame(width: 62, height: 47).rotationEffect(.degrees(5)).offset(x: 8, y: 9)
                    .shadow(color: Color(hex: 0x030B19).opacity(0.5), radius: 7, x: 1, y: 7)
            }
            .frame(width: 100, height: 100)
            .scaleEffect(size / 100, anchor: .topLeading)
            .frame(width: size, height: size, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
}

private struct IslandButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(primary ? Color(hex: 0x202635) : Color.white.opacity(0.71))
            .padding(.horizontal, primary ? 15 : 11).frame(height: 31)
            .modifier(IslandControlSurface(primary: primary, opaque: reduceTransparency))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.80 : 1) : 0.32)
    }
}

private struct IslandControlSurface: ViewModifier {
    var primary: Bool
    var opaque: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if primary {
            content.background {
                Capsule().fill(LinearGradient(colors: [Color.white, Color(hex: 0xDDE8F5)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
        } else if #available(macOS 26.0, *), !opaque {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(Color(hex: 0x292E39), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 0.6))
        }
    }
}
