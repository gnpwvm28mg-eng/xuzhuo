import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
struct ContentView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var store: SceneStore
    @ObservedObject var workspace: WorkspaceService
    @State private var section = "全部现场"
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var showSave = false
    @State private var showPermissions = false
    @State private var toast: String?
    @State private var restoring = false

    private var selected: WorkScene? { selectedID.flatMap { store.scene($0) } }
    private var sectionTitle: String {
        switch section {
        case "我的收藏": return L(section, "Favorites")
        case "最近继续": return L(section, "Recently Resumed")
        default: return L(section, "All Scenes")
        }
    }
    private var filtered: [WorkScene] {
        let scenes = store.scenes.filter {
            (section != "我的收藏" || $0.isFavorite) &&
            (search.isEmpty || ($0.localizedTitle + $0.localizedNextStep + $0.title + $0.nextStep + $0.resources.map(\.title).joined()).localizedCaseInsensitiveContains(search))
        }
        return scenes.sorted { section == "最近继续" ? ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) : $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(DeskStyle.line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                if let selected {
                    SceneDetailView(scene: selected, store: store, workspace: workspace, restoring: restoring,
                                    back: { selectedID = nil }, restore: { restore(selected) }, notify: { toast = $0 })
                } else {
                    gallery
                }
            }.background(DeskStyle.background)
        }
        .foregroundStyle(DeskStyle.ink)
        .sheet(isPresented: $showSave) {
            SaveSceneView(store: store, workspace: workspace) { scene, issues in
                selectedID = scene.id
                toast = issues.isEmpty ? L("现场已留好。下次回来，从这里接着做。", "Scene saved. Pick up here next time.") : L("现场已保存。", "Scene saved. ") + issues.joined(separator: L("；", "; "))
            }
        }
        .sheet(isPresented: $showPermissions) { PermissionsView(service: workspace) }
        .onReceive(NotificationCenter.default.publisher(for: .saveScene)) { _ in showSave = true }
        .overlay(alignment: .bottom) {
            if let toast {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DeskStyle.green)
                    Text(toast).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button { self.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(L("关闭提示", "Dismiss message"))
                }.padding(15).frame(maxWidth: 680)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DeskStyle.line))
                    .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
                    .padding(.bottom, 22).padding(.leading, 205)
            }
        }
        .alert(L("本地存储需要处理", "Local storage needs attention"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(L("知道了", "OK"), role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .environment(\.locale, languageSettings.language.locale)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 37)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("续桌", "XuZhuo")).font(.system(size: 23, weight: .semibold))
                    Text(L("给工作一个存档点", "A save point for your work")).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
                }
            }.padding(.top, 49).padding(.horizontal, 22)
            Text(L("工作空间", "WORKSPACE")).font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(DeskStyle.secondary).padding(.top, 43).padding(.horizontal, 26).padding(.bottom, 12)
            ForEach([("全部现场", "square.grid.2x2", "All Scenes"), ("我的收藏", "star", "Favorites"), ("最近继续", "clock.arrow.circlepath", "Recently Resumed")], id: \.0) { item in
                Button {
                    section = item.0; selectedID = nil
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.1).frame(width: 16)
                        Text(L(item.0, item.2))
                        Spacer()
                        if item.0 == "全部现场" {
                            Text("\(store.scenes.count)").font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
                        }
                    }.font(.system(size: 12, weight: section == item.0 ? .semibold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(section == item.0 ? Color.white.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 3)
            }
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 17)).foregroundStyle(DeskStyle.green)
                Text(L("不用重新开始，\n只要接着上次。", "Pick up where\nyou left off.")).font(.system(size: 14, weight: .medium)).lineSpacing(6)
                Text(L("保存资料，也保存思路。", "Keep your files and your train of thought.")).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(DeskStyle.paleGreen.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20).padding(.top, 35)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(Color(hex: 0x789B6B)).frame(width: 6, height: 6)
                Text(L("只在这台 Mac 上保存", "Stored only on this Mac")).font(.system(size: 10))
            }.foregroundStyle(DeskStyle.secondary).padding(.horizontal, 24).padding(.bottom, 18)
            Button { showPermissions = true } label: {
                Label(L("设置与恢复支持", "Settings & Permissions"), systemImage: "slider.horizontal.3").font(.system(size: 11))
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 25)
        }.frame(width: 205).frame(maxHeight: .infinity).background(DeskStyle.sidebar)
    }

    private var topbar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack").foregroundStyle(DeskStyle.secondary)
                Text(selected?.localizedTitle ?? sectionTitle).font(.system(size: 11, weight: .medium))
            }
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(DeskStyle.secondary)
                TextField(L("搜索现场、资料或下一步", "Search scenes, files, or next steps"), text: $search)
                    .textFieldStyle(.plain).font(.system(size: 11)).frame(width: languageSettings.language == .english ? 205 : 172)
                    .onChange(of: search) { selectedID = nil }
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel(L("清除搜索", "Clear search"))
                }
            }.padding(.horizontal, 11).padding(.vertical, 8).background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            Text(Date.now.localizedSceneDate()).font(.system(size: 11)).foregroundStyle(DeskStyle.secondary).padding(.leading, 14)
        }.padding(.horizontal, 32).frame(height: 68)
            .overlay(alignment: .bottom) { Rectangle().fill(DeskStyle.line).frame(height: 1) }
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("接着上次，继续。", "Welcome back.")).font(.system(size: 29, weight: .semibold))
                        Text(L("把散落的资料，收成一个可以回来的现场。", "Keep everything you need to return to your work."))
                            .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
                    }
                    Spacer()
                    Button { showSave = true } label: { Label(L("保存当前现场", "Save Current Scene"), systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
                        .help(L("保存当前现场 ⇧⌘S", "Save current scene ⇧⌘S"))
                }.padding(.top, 10)
                ritualBanner
                HStack {
                    Text(section == "全部现场" ? L("我的现场", "My Scenes") : sectionTitle).font(.system(size: 16, weight: .semibold))
                    Text("\(filtered.count)").font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                    Spacer()
                    Image(systemName: "arrow.down").font(.system(size: 9))
                    Text(section == "最近继续" ? L("最近打开", "Last opened") : L("最近保存", "Last saved")).font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                }
                if filtered.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: search.isEmpty ? "rectangle.stack.badge.plus" : "magnifyingglass").font(.system(size: 30)).foregroundStyle(DeskStyle.secondary)
                        Text(search.isEmpty ? L("这里，等着你的第一个现场", "Your first scene starts here") : L("没有找到这个现场", "No scenes found")).font(.system(size: 15, weight: .medium))
                        Text(search.isEmpty ? L("资料还在原处，进度留在这里。", "Files stay where they are. Your progress stays here.") : L("试试项目名、网页标题或下一步。", "Try a project name, page title, or next step."))
                            .font(.system(size: 12)).foregroundStyle(DeskStyle.secondary)
                        if search.isEmpty {
                            Button(L("保存一个现场", "Save a Scene")) { showSave = true }.buttonStyle(SecondaryButtonStyle())
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 75)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], alignment: .leading, spacing: 20) {
                        ForEach(filtered) { scene in
                            SceneCard(scene: scene, store: store, open: { selectedID = scene.id }, notify: { toast = $0 })
                        }
                        newSceneCard
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").font(.system(size: 11))
                    Text(L("本地保存 · 无需账号 · 资料保留在原位置", "Local storage · No account · Original files stay in place")).font(.system(size: 10))
                }.foregroundStyle(DeskStyle.secondary).frame(maxWidth: .infinity).padding(.top, 5).padding(.bottom, 20)
            }.padding(32)
        }
    }

    private var ritualBanner: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xBDD5A8)).frame(width: 5, height: 5)
                    Text(L("给今天，留一个存档点", "SAVE A PLACE TO RETURN TO")).font(.system(size: 10, weight: .medium)).tracking(1)
                }.foregroundStyle(Color(hex: 0xD3DFC9))
                Text(L("关掉工作，别关掉思路。", "Leave work. Keep your place.")).font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                Text(L("离开前记一句「下一步」，\n回来时，就知道该从哪里开始。", "Leave a next step before you go.\nReturn knowing exactly where to begin."))
                    .font(.system(size: 12)).lineSpacing(5).foregroundStyle(Color(hex: 0xCBD7CA))
                Button { showSave = true } label: {
                    HStack(spacing: 7) { Text(L("留住此刻", "Save this moment")); Image(systemName: "arrow.up.right") }.font(.system(size: 11, weight: .semibold))
                }.buttonStyle(.plain).foregroundStyle(.white).padding(.top, 4)
            }
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)).frame(width: 170, height: 130).rotationEffect(.degrees(-9)).offset(x: -15, y: -3)
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Image(systemName: "bookmark.fill"); Spacer(); Text("NEXT").font(.system(size: 9, weight: .medium)).tracking(2) }
                        .foregroundStyle(DeskStyle.green)
                    Text(L("下一步\n补完方案预算", "Next up\nFinish the budget")).font(.system(size: 16, weight: .medium)).lineSpacing(6)
                    HStack { Text(L("留给下一次的自己", "For your future self")).font(.system(size: 9)).foregroundStyle(DeskStyle.secondary); Spacer(); Image(systemName: "arrow.right").font(.system(size: 11)) }
                }.padding(18).frame(width: 184, height: 137).background(Color(hex: 0xF4F3E8), in: RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(5)).shadow(color: .black.opacity(0.1), radius: 10, y: 8)
            }.frame(width: 240).padding(.trailing, 12)
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0x284A39), Color(hex: 0x3E6148)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
    }

    private var newSceneCard: some View {
        Button { showSave = true } label: {
            VStack(spacing: 13) {
                Image(systemName: "plus").font(.system(size: 22, weight: .light)).frame(width: 45, height: 45)
                    .background(DeskStyle.paleGreen, in: RoundedRectangle(cornerRadius: 13))
                Text(L("为新项目留一个位置", "Make room for a new project")).font(.system(size: 13, weight: .medium))
                Text(L("你的下一个现场，从这里开始", "Your next scene starts here")).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
            }.frame(maxWidth: .infinity).frame(height: 303)
                .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(DeskStyle.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }.buttonStyle(.plain)
    }

    private func restore(_ scene: WorkScene) {
        guard !restoring else { return }
        restoring = true
        Task {
            let report = await workspace.restore(scene)
            store.markOpened(scene.id)
            restoring = false
            toast = L("已打开 \(report.opened) 项资料，恢复 \(report.positioned) 个窗口位置。", "Opened \(report.opened) resources and restored \(report.positioned) window positions.") + (report.issues.isEmpty ? "" : " " + report.issues.joined(separator: L("；", "; ")))
        }
    }
}

@MainActor
struct SceneCard: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let scene: WorkScene
    @ObservedObject var store: SceneStore
    let open: () -> Void
    let notify: (String) -> Void
    @State private var hovering = false
    @State private var dropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                SceneCover(scene: scene, store: store).frame(height: 159)
                    .overlay(alignment: .topTrailing) {
                        if scene.isDemo { Text(L("示例", "Example")).font(.system(size: 9)).padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.8), in: Capsule()).padding(11) }
                    }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: scene.symbol).font(.system(size: 12)).foregroundStyle(DeskStyle.tint(scene.tint))
                    Button(action: open) { Text(scene.localizedTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1) }.buttonStyle(.plain)
                    Spacer(minLength: 5)
                    Button { store.toggleFavorite(scene.id) } label: {
                        Image(systemName: scene.isFavorite ? "star.fill" : "star").font(.system(size: 12)).foregroundStyle(scene.isFavorite ? Color(hex: 0xB18C44) : DeskStyle.secondary.opacity(0.6))
                    }.buttonStyle(.plain).help(scene.isFavorite ? L("取消收藏", "Remove from Favorites") : L("收藏现场", "Add to Favorites"))
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).padding(.top, 2)
                    Text(scene.nextStep.isEmpty ? L("还没有下一步，留一句给未来的自己", "Leave a next step for your future self") : scene.localizedNextStep).font(.system(size: 11)).lineLimit(2).frame(height: 29, alignment: .topLeading)
                }.foregroundStyle(DeskStyle.secondary)
                HStack(spacing: 5) {
                    Tag(text: L("\(scene.resources.count) 项资料", "\(scene.resources.count) resources"), symbol: "paperclip")
                    if !scene.windows.isEmpty { Tag(text: L("\(scene.windows.count) 个窗口", "\(scene.windows.count) windows"), symbol: "macwindow") }
                    Spacer(minLength: 0)
                    Text(scene.updatedAt.localizedSceneDate()).font(.system(size: 9)).foregroundStyle(DeskStyle.secondary)
                }
            }.padding(16)
        }.background(Color.white, in: RoundedRectangle(cornerRadius: 13))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(dropTarget ? DeskStyle.green : DeskStyle.line, lineWidth: dropTarget ? 2 : 1))
            .shadow(color: .black.opacity(hovering ? 0.06 : 0.02), radius: hovering ? 12 : 3, y: hovering ? 4 : 1)
            .onHover { hovering = $0 }
            .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier], isTargeted: $dropTarget) { providers in
                ResourceImport.load(providers) { resources in
                    if resources.isEmpty { notify(L("没有找到可添加的文件或网页链接。", "No files or web links were found.")); return }
                    let before = store.scene(scene.id)?.resources.count ?? 0
                    if store.addResources(resources, to: scene.id) {
                        let added = (store.scene(scene.id)?.resources.count ?? before) - before
                        notify(added == 0 ? L("这些资料已经收在这个现场了。", "These resources are already in this scene.") : L("已收好 \(added) 项资料，原文件保留在原处。", "Added \(added) resources. Original files stay in place."))
                    }
                }
                return true
            }
    }
}
