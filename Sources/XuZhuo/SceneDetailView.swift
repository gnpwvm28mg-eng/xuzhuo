import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
struct SceneDetailView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let scene: WorkScene
    @ObservedObject var store: SceneStore
    @ObservedObject var workspace: WorkspaceService
    let restoring: Bool
    let back: () -> Void
    let restore: () -> Void
    let notify: (String) -> Void
    @State private var nextStep = ""
    @State private var nextStepBaseline = ""
    @State private var showCheckpoint = false
    @State private var showLink = false
    @State private var showExport = false
    @State private var showDelete = false
    @State private var dropTarget = false
    @State private var renaming = false
    @State private var name = ""
    private var hasThumbnail: Bool {
        store.thumbnailURL(for: scene).flatMap { NSImage(contentsOf: $0) } != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Button(action: back) { Label(L("返回画廊", "Back to Gallery"), systemImage: "arrow.left").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(DeskStyle.secondary)
                HStack(spacing: 16) {
                    Image(systemName: scene.symbol).font(.system(size: 23)).foregroundStyle(DeskStyle.tint(scene.tint))
                        .frame(width: 51, height: 51).background(DeskStyle.tint(scene.tint).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(scene.localizedTitle).font(.system(size: 25, weight: .semibold))
                            if scene.isDemo { Tag(text: L("示例现场", "Example")) }
                        }
                        Text(L("保存于 ", "Saved ") + scene.updatedAt.localizedSceneDate(includeTime: true))
                            .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                    }
                    Spacer()
                    Button { store.toggleFavorite(scene.id) } label: {
                        Image(systemName: scene.isFavorite ? "star.fill" : "star").foregroundStyle(scene.isFavorite ? Color(hex: 0xB18C44) : DeskStyle.secondary)
                    }.buttonStyle(.plain).padding(.trailing, 7)
                        .accessibilityLabel(scene.isFavorite ? L("取消收藏", "Remove from Favorites") : L("收藏现场", "Add to Favorites"))
                    Button(action: restore) {
                        HStack(spacing: 8) {
                            if restoring { ProgressView().controlSize(.small).tint(.white) }
                            else { Image(systemName: "play.fill") }
                            Text(restoring ? L("正在恢复…", "Restoring…") : L("继续这个现场", "Resume Scene"))
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(restoring)
                }
                if scene.isDemo {
                    Label(L("这是一张示例卡：展示资料组织方式，封面是布局示意。你可以添加资料、修改提醒，或保存自己的现场。", "This example shows how a scene keeps your work together. Add resources, edit its next step, or save a scene of your own."), systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DeskStyle.paleGreen.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 22) {
                        SceneCover(scene: scene, store: store).frame(height: 254).clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(alignment: .bottomLeading) {
                                Text(hasThumbnail ? L("保存时的桌面", "Captured desktop") : L("没有桌面截图 · 布局示意", "Layout preview · No desktop capture"))
                                    .font(.system(size: 10)).padding(9).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7)).padding(12)
                            }
                        resourcesSection
                        if !scene.windows.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L("窗口布局", "Window Layout")).font(.system(size: 14, weight: .semibold))
                                ForEach(scene.windows) { window in
                                    HStack {
                                        Image(systemName: "macwindow").foregroundStyle(DeskStyle.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(window.title).font(.system(size: 11)).lineLimit(1)
                                            Text(window.applicationName).font(.system(size: 9)).foregroundStyle(DeskStyle.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }.padding(18).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 20) {
                        nextStepCard
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(L("收工记录", "Checkpoints")).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button { showCheckpoint = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).accessibilityLabel(L("添加收工记录", "Add checkpoint"))
                            }
                            if scene.checkpoints.isEmpty {
                                Text(L("今天做到哪儿了？\n花十秒，给下次的自己留句话。", "Where did you leave off?\nLeave a quick note for next time."))
                                    .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary).lineSpacing(5)
                            } else {
                                ForEach(scene.checkpoints.sorted { $0.date > $1.date }.prefix(5)) { checkpoint in
                                    HStack(alignment: .top, spacing: 9) {
                                        Circle().fill(DeskStyle.tint(scene.tint)).frame(width: 5, height: 5).padding(.top, 5)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(checkpoint.note).font(.system(size: 11)).lineSpacing(3)
                                            Text(checkpoint.date.localizedSceneDate(includeTime: true)).font(.system(size: 9)).foregroundStyle(DeskStyle.secondary)
                                        }
                                    }
                                }
                            }
                            Button { showCheckpoint = true } label: { Label(L("记一句，收工", "Leave a Checkpoint"), systemImage: "moon") }
                                .buttonStyle(SecondaryButtonStyle())
                        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("项目资料包", "Project Package")).font(.system(size: 14, weight: .semibold))
                            Text(L("把链接、备注和选定文件整理好，\n方便交接，也方便带走。", "Bundle links, notes, and selected files\nfor handoff or taking with you."))
                                .font(.system(size: 11)).foregroundStyle(DeskStyle.secondary).lineSpacing(4)
                            Button { showExport = true } label: { Label(L("导出资料包", "Export Package"), systemImage: "square.and.arrow.up") }.buttonStyle(SecondaryButtonStyle())
                        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
                            .background(DeskStyle.paleGreen.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }.frame(width: 280)
                }
                HStack(spacing: 15) {
                    Button(L("重命名", "Rename")) { name = scene.title; renaming = true }.buttonStyle(.plain)
                    Button(L("删除存档", "Delete Scene")) { showDelete = true }.buttonStyle(.plain)
                    Spacer()
                    Text(L("删除存档不会删除原资料", "Deleting a scene keeps the original files")).font(.system(size: 10))
                }.font(.system(size: 11)).foregroundStyle(DeskStyle.secondary).padding(.top, 6)
            }.padding(32)
        }
        .onAppear { loadNextStep() }
        .onChange(of: scene.id) { loadNextStep() }
        .onChange(of: scene.nextStep) { loadNextStep() }
        .onChange(of: languageSettings.language) { if nextStep == nextStepBaseline { loadNextStep() } }
        .environment(\.locale, languageSettings.language.locale)
        .sheet(isPresented: $showCheckpoint) { CheckpointView(scene: scene, store: store, notify: notify) }
        .sheet(isPresented: $showLink) { AddLinkView { resource in store.addResources([resource], to: scene.id) } }
        .sheet(isPresented: $showExport) { ExportSceneView(scene: scene, store: store, notify: notify) }
        .alert(L("删除「\(scene.localizedTitle)」的存档？", "Delete the scene “\(scene.localizedTitle)”?"), isPresented: $showDelete) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("删除存档", "Delete Scene"), role: .destructive) { if store.delete(scene.id) { back() } }
        } message: { Text(L("仅删除本地存档、备注和缩略图，原文件和网页不会被删除。", "This removes the local scene, notes, and thumbnail. Original files and web pages are kept.")) }
        .alert(L("重命名现场", "Rename Scene"), isPresented: $renaming) {
            TextField(L("现场名称", "Scene Name"), text: $name)
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("保存", "Save")) {
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                var updated = scene; updated.title = name.trimmingCharacters(in: .whitespacesAndNewlines); updated.updatedAt = .now; store.save(updated)
            }
        }
    }

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("回来后，先做这件事", "YOUR NEXT STEP"), systemImage: "bookmark.fill").font(.system(size: 11, weight: .medium))
                Spacer()
            }.foregroundStyle(DeskStyle.green)
            TextEditor(text: $nextStep).accessibilityLabel(L("下一步提醒", "Next step reminder")).font(.system(size: 16, weight: .medium)).scrollContentBackground(.hidden)
                .frame(height: 89).lineSpacing(5)
                .overlay(alignment: .topLeading) {
                    if nextStep.isEmpty { Text(L("下一步做什么？", "What comes next?")).font(.system(size: 16)).foregroundStyle(DeskStyle.secondary).padding(.top, 1).padding(.leading, 5).allowsHitTesting(false) }
                }
            HStack {
                Text(L("留给下一次的自己", "For your future self")).font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
                Spacer()
                Button(L("保存提醒", "Save Note")) {
                    var updated = scene
                    updated.nextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.updatedAt = .now
                    if store.save(updated) { notify(L("下一步已留好。", "Your next step is saved.")) }
                }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(DeskStyle.green).disabled(nextStep == nextStepBaseline)
            }
        }.padding(19).background(Color(hex: 0xEFEFDC), in: RoundedRectangle(cornerRadius: 12))
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L("现场资料", "Resources")).font(.system(size: 15, weight: .semibold))
                Text("\(scene.resources.count)").font(.system(size: 11)).foregroundStyle(DeskStyle.secondary)
                Spacer()
                Button { store.addResources(ResourceImport.chooseFiles(), to: scene.id) } label: { Image(systemName: "paperclip") }.buttonStyle(.plain).help(L("添加文件或文件夹", "Add files or folders")).accessibilityLabel(L("添加文件或文件夹", "Add files or folders"))
                Button { showLink = true } label: { Image(systemName: "link") }.buttonStyle(.plain).help(L("添加网页链接", "Add web link")).accessibilityLabel(L("添加网页链接", "Add web link"))
            }
            ForEach(scene.resources) { resource in
                Button {
                    Task {
                        var single = scene; single.resources = [resource]; single.windows = []
                        let report = await workspace.restore(single)
                        if !report.issues.isEmpty { notify(report.issues.joined(separator: L("；", "; "))) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: resource.kind.symbol).font(.system(size: 15)).foregroundStyle(DeskStyle.tint(scene.tint))
                            .frame(width: 35, height: 35).background(DeskStyle.background, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scene.localizedResourceTitle(resource)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(resource.kind == .web ? resource.location : (resource.location as NSString).deletingLastPathComponent)
                                .font(.system(size: 10)).foregroundStyle(DeskStyle.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(DeskStyle.secondary)
                    }
                }.buttonStyle(.plain)
                    .contextMenu {
                        Button(L("从现场移除引用", "Remove from Scene")) {
                            removeResource(resource.id)
                        }
                    }
            }
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                Text(L("文件、链接、截图拖进来就收好", "Drop files, links, or screenshots here")).font(.system(size: 11))
            }.foregroundStyle(DeskStyle.secondary).frame(maxWidth: .infinity).padding(.vertical, 23)
                .background(dropTarget ? DeskStyle.paleGreen : DeskStyle.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(dropTarget ? DeskStyle.green : DeskStyle.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }.padding(19).background(.white, in: RoundedRectangle(cornerRadius: 12))
            .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier], isTargeted: $dropTarget) { providers in
                ResourceImport.load(providers) { resources in
                    if resources.isEmpty { notify(L("请拖入文件或有效的网页链接。", "Drop files or valid web links here.")); return }
                    let before = store.scene(scene.id)?.resources.count ?? 0
                    if store.addResources(resources, to: scene.id) {
                        let added = (store.scene(scene.id)?.resources.count ?? before) - before
                        notify(added == 0 ? L("这些资料已经收在这个现场了。", "These resources are already in this scene.") : L("已添加 \(added) 项资料。", "Added \(added) resources."))
                    }
                }
                return true
            }
    }

    private func removeResource(_ id: UUID) {
        var updated = scene
        updated.resources = updated.resources.filter { $0.id != id }
        updated.updatedAt = .now
        store.save(updated)
    }

    private func loadNextStep() {
        nextStepBaseline = scene.localizedNextStep
        nextStep = nextStepBaseline
    }
}
