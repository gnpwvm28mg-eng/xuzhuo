import Combine
import Foundation

@MainActor
final class SceneStore: ObservableObject {
    @Published var scenes: [WorkScene] = []
    @Published var errorMessage: String?

    let directory: URL
    private var canPersist = true
    private var archiveURL: URL { directory.appendingPathComponent("scenes.json") }
    private var thumbnailsDirectory: URL { directory.appendingPathComponent("thumbnails", isDirectory: true) }

    private struct Archive: Codable {
        let version: Int
        let scenes: [WorkScene]
    }

    init(directory: URL? = nil, seedExamples: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                              in: .userDomainMask)[0]
            .appendingPathComponent("XuZhuo", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                let data = try Data(contentsOf: archiveURL)
                let archive = try Self.decoder().decode(Archive.self, from: data)
                guard archive.version == 1 else { throw StoreError.unsupportedArchive }
                guard Set(archive.scenes.map(\.id)).count == archive.scenes.count else {
                    throw StoreError.duplicateSceneIDs
                }
                scenes = archive.scenes
            } else if seedExamples {
                persist(Self.examples())
            }
        } catch {
            canPersist = false
            errorMessage = L("无法读取本地存档，原文件已保留。为避免覆盖，当前改动暂时无法保存。\n\(archiveURL.path)\n\(error.localizedDescription)", "Could not read the local archive. The original file was kept. Changes cannot be saved until it is repaired.\n\(archiveURL.path)\n\(Self.errorDetail(error))")
        }
    }

    func scene(_ id: UUID) -> WorkScene? { scenes.first { $0.id == id } }

    @discardableResult
    func save(_ scene: WorkScene) -> Bool {
        var updated = scene
        updated.updatedAt = Date()
        var candidate = scenes
        if let index = candidate.firstIndex(where: { $0.id == scene.id }) {
            candidate[index] = updated
        } else {
            candidate.insert(updated, at: 0)
        }
        return persist(candidate)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard scene(id) != nil else { return false }
        let thumbnail = scene(id).flatMap { thumbnailURL(for: $0) }
        let candidate = scenes.filter { $0.id != id }
        guard persist(candidate) else { return false }
        if let thumbnail,
           !scenes.contains(where: { thumbnailURL(for: $0) == thumbnail }) {
            try? FileManager.default.removeItem(at: thumbnail)
        }
        return true
    }

    @discardableResult
    func toggleFavorite(_ id: UUID) -> Bool {
        guard var item = scene(id) else { return false }
        item.isFavorite.toggle()
        return save(item)
    }

    @discardableResult
    func addResources(_ resources: [SceneResource], to id: UUID) -> Bool {
        guard var item = scene(id) else { return false }
        for resource in resources {
            let canonical = resource.resolvedURL()?.standardized.absoluteString ?? resource.location
            let duplicate = item.resources.contains {
                $0.kind == resource.kind && ($0.resolvedURL()?.standardized.absoluteString ?? $0.location) == canonical
            }
            if !duplicate { item.resources.append(resource) }
        }
        return save(item)
    }

    @discardableResult
    func recordCheckpoint(sceneID: UUID, note: String) -> Bool {
        guard var item = scene(sceneID) else { return false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        item.nextStep = trimmed
        item.checkpoints.insert(SceneCheckpoint(note: trimmed), at: 0)
        return save(item)
    }

    @discardableResult
    func markOpened(_ id: UUID) -> Bool {
        guard var item = scene(id) else { return false }
        item.lastOpenedAt = Date()
        return save(item)
    }

    func thumbnailURL(for scene: WorkScene) -> URL? {
        guard let name = scene.thumbnailName, !name.isEmpty,
              name == (name as NSString).lastPathComponent, name != ".", name != ".." else { return nil }
        let url = thumbnailsDirectory.appendingPathComponent(name)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }

    func storeThumbnail(_ data: Data, for id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        let name = "\(id.uuidString)-\(UUID().uuidString).png"
        try data.write(to: thumbnailsDirectory.appendingPathComponent(name), options: .withoutOverwriting)
        return name
    }

    /// Creates a new directory; source files and previous exports are never modified.
    func export(scene: WorkScene, to destination: URL, includeFiles: Bool) throws -> URL {
        let manager = FileManager.default
        let destinationAccess = destination.startAccessingSecurityScopedResource()
        defer { if destinationAccess { destination.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw StoreError.invalidDestination }

        let package = Self.availableURL(in: destination,
                                       name: "\(Self.safeFileName(scene.title))-\(L("资料包", "Resources"))", isDirectory: true)
        try manager.createDirectory(at: package, withIntermediateDirectories: false)
        do {
            let files = package.appendingPathComponent("files", isDirectory: true)
            var exportedScene = scene
            exportedScene.thumbnailName = nil
            var report: [String] = []
            for index in exportedScene.resources.indices {
                let resource = scene.resources[index]
                exportedScene.resources[index].bookmarkData = nil
                if resource.kind == .web {
                    report.append(L("- \(Self.markdownText(resource.title))：\(resource.resolvedURL() == nil ? "链接无效，未加入网页清单" : "已收录网页链接")", "- \(Self.markdownText(resource.title)): \(resource.resolvedURL() == nil ? "Invalid URL; excluded from the link list" : "Web link included")"))
                    continue
                }
                guard includeFiles else {
                    report.append(L("- \(Self.markdownText(resource.title))：仅保留原位置，未复制文件", "- \(Self.markdownText(resource.title)): Original location kept; file not copied"))
                    continue
                }
                guard let source = resource.resolvedURL() else {
                    report.append(L("- \(Self.markdownText(resource.title))：原位置无效，未复制", "- \(Self.markdownText(resource.title)): Invalid original location; not copied"))
                    continue
                }
                let sourceAccess = source.startAccessingSecurityScopedResource()
                defer { if sourceAccess { source.stopAccessingSecurityScopedResource() } }
                do {
                    try Self.validateCopySource(source)
                    let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
                    let packagePath = package.standardizedFileURL.resolvingSymlinksInPath().path
                    guard packagePath != sourcePath,
                          !packagePath.hasPrefix(sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/") else {
                        throw StoreError.destinationInsideSource
                    }
                    try manager.createDirectory(at: files, withIntermediateDirectories: true)
                    let target = Self.availableURL(in: files, name: Self.safeFileName(source.lastPathComponent),
                                                   isDirectory: resource.kind == .folder)
                    do {
                        try manager.copyItem(at: source, to: target)
                    } catch {
                        try? manager.removeItem(at: target)
                        throw error
                    }
                    exportedScene.resources[index].location = "files/\(target.lastPathComponent)"
                    report.append(L("- \(Self.markdownText(resource.title))：已复制到 files/\(Self.markdownText(target.lastPathComponent))", "- \(Self.markdownText(resource.title)): Copied to files/\(Self.markdownText(target.lastPathComponent))"))
                } catch {
                    report.append(L("- \(Self.markdownText(resource.title))：未复制（\(Self.markdownText(error.localizedDescription))）", "- \(Self.markdownText(resource.title)): Not copied (\(Self.markdownText(Self.errorDetail(error))))"))
                }
            }
            try Self.encoder().encode(exportedScene).write(to: package.appendingPathComponent("scene.json"),
                                                         options: .withoutOverwriting)
            try Data(Self.linksHTML(for: scene).utf8).write(to: package.appendingPathComponent("links.html"),
                                                          options: .withoutOverwriting)
            try Data(Self.readme(for: scene, report: report).utf8).write(to: package.appendingPathComponent("README.md"),
                                                                      options: .withoutOverwriting)
            return package
        } catch {
            try? manager.removeItem(at: package)
            throw error
        }
    }

    @discardableResult
    private func persist(_ candidate: [WorkScene]) -> Bool {
        guard canPersist else {
            errorMessage = L("原存档无法读取，已保留且未覆盖。当前改动尚未保存，请先备份并检查：\n\(archiveURL.path)", "The original archive could not be read and has not been overwritten. Your changes are not saved. Back up and check this file first:\n\(archiveURL.path)")
            return false
        }
        do {
            try Self.encoder().encode(Archive(version: 1, scenes: candidate))
                .write(to: archiveURL, options: .atomic)
            scenes = candidate
            errorMessage = nil
            return true
        } catch {
            errorMessage = L("改动尚未保存：\(error.localizedDescription)", "Changes have not been saved: \(Self.errorDetail(error))")
            return false
        }
    }

    private static func errorDetail(_ error: Error) -> String {
        if let storeError = error as? StoreError { return storeError.errorDescription ?? "" }
        if LanguageSettings.shared.language == .chinese { return error.localizedDescription }
        let error = error as NSError
        return "System error (\(error.domain) \(error.code))."
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder { JSONDecoder() }

    static func safeFileName(_ text: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let replaced = text.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let shortened = String(replaced.prefix(100))
        return shortened.isEmpty ? "XuZhuo" : shortened
    }

    private static func availableURL(in directory: URL, name: String, isDirectory: Bool) -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path)
            || (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            let fileName: String
            if !isDirectory, !(name as NSString).pathExtension.isEmpty {
                fileName = "\((name as NSString).deletingPathExtension)-\(suffix).\((name as NSString).pathExtension)"
            } else {
                fileName = "\(name)-\(suffix)"
            }
            candidate = directory.appendingPathComponent(fileName, isDirectory: isDirectory)
            suffix += 1
        }
        return candidate
    }

    /// Reject links and special files before copying a folder recursively.
    static func validateCopySource(_ url: URL) throws {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        func validate(_ item: URL) throws -> Bool {
            let values = try item.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw StoreError.symbolicLink(item.lastPathComponent) }
            guard values.isDirectory == true || values.isRegularFile == true else {
                throw StoreError.unsupportedFile(item.lastPathComponent)
            }
            return values.isDirectory == true
        }
        guard try validate(url) else { return }
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                 options: [], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw StoreError.unreadableFolder }
        for case let item as URL in enumerator { _ = try validate(item) }
        if let enumerationError { throw enumerationError }
    }

    private static func markdownText(_ string: String) -> String {
        string.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    private static func htmlText(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func linksHTML(for scene: WorkScene) -> String {
        let items = scene.resources.filter { $0.kind == .web }.compactMap { resource -> String? in
            guard let url = resource.resolvedURL() else { return nil }
            return "<li><a href=\"\(htmlText(url.absoluteString))\">\(htmlText(resource.title))</a></li>"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="\(L("zh-CN", "en"))"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(htmlText(scene.title)) · \(L("续桌资料包", "XuZhuo Resource Pack"))</title>
        <style>body{font:17px -apple-system,sans-serif;max-width:760px;margin:60px auto;padding:0 24px;line-height:1.7;color:#253832}a{color:#3c7161}li{margin:12px 0}pre{white-space:pre-wrap;font:inherit}</style></head>
        <body><h1>\(htmlText(scene.title))</h1><p>\(htmlText(scene.subtitle))</p><h2>\(L("下一步", "Next step"))</h2><pre>\(htmlText(scene.nextStep))</pre><h2>\(L("网页资料", "Web links"))</h2><ul>\(items)</ul></body></html>
        """
    }

    private static func readme(for scene: WorkScene, report: [String]) -> String {
        let formatter = ISO8601DateFormatter()
        let checkpoints = scene.checkpoints.map { "- \(formatter.string(from: $0.date)) · \(markdownText($0.note))" }
        return """
        # \(markdownText(scene.title))

        \(scene.subtitle)

        ## \(L("下一步", "Next step"))

        \(scene.nextStep.isEmpty ? L("尚未填写", "No next step yet.") : scene.nextStep)

        ## \(L("使用资料包", "Using this resource pack"))

        \(L("打开 links.html 查看网页链接和下一步；files 文件夹内是选择复制的资料。scene.json 保存项目备注、进度和窗口信息，已去除系统授权书签。文件路径以 files/ 开头时，表示相对于本资料包的位置。原文件保持在原处。", "Open links.html to view web links and the next step. The files folder contains resources you chose to copy. scene.json stores notes, progress, and window details with system access bookmarks removed. Paths beginning with files/ are relative to this pack. Original files stay in place."))

        \(L("未复制的资料可能保留本机绝对路径，分享前请检查 scene.json。", "Resources that were not copied may retain absolute paths on this Mac. Review scene.json before sharing."))

        \(L("窗口位置仅用于留档。资料包不会安装应用或自动授予访问权限。", "Window positions are included for reference. This pack does not install apps or grant access permissions."))

        ## \(L("资料处理结果", "Resource results"))

        \(report.isEmpty ? L("没有资料。", "No resources.") : report.joined(separator: "\n"))

        ## \(L("收工记录", "Checkpoints"))

        \(checkpoints.isEmpty ? L("暂无记录。", "No checkpoints yet.") : checkpoints.joined(separator: "\n"))

        \(L("导出时间", "Exported")): \(formatter.string(from: Date()))
        """
    }

    private static func examples() -> [WorkScene] {
        let now = Date()
        return [
            WorkScene(title: "把论文写完", subtitle: "示例 · 思路、文献和下一段", symbol: "text.book.closed",
                      tint: "sage", nextStep: "把研究问题写成一句话，再补三篇相关文献。",
                      createdAt: now, updatedAt: now, isDemo: true,
                      resources: [.init(kind: .web, title: "Google Scholar", location: "https://scholar.google.com/")]),
            WorkScene(title: "新一轮设计", subtitle: "示例 · 灵感、规范和待完善的细节", symbol: "paintpalette",
                      tint: "peach", nextStep: "先梳理首页的阅读顺序，再画一版简单的线框。",
                      createdAt: now, updatedAt: now.addingTimeInterval(-60), isDemo: true,
                      resources: [.init(kind: .web, title: "Apple 人机交互指南", location: "https://developer.apple.com/design/human-interface-guidelines/")]),
            WorkScene(title: "计划一次旅行", subtitle: "示例 · 路线、清单和出发前的小事", symbol: "map",
                      tint: "sky", nextStep: "选定第一站，把交通时间和住宿预算记下来。",
                      createdAt: now, updatedAt: now.addingTimeInterval(-120), isDemo: true,
                      resources: [.init(kind: .web, title: "Wikivoyage 旅行指南", location: "https://zh.wikivoyage.org/")])
        ]
    }
}

enum StoreError: LocalizedError {
    case unsupportedArchive, duplicateSceneIDs, invalidDestination, unreadableFolder, destinationInsideSource
    case symbolicLink(String), unsupportedFile(String)

    // LocalizedError is queried outside the main actor by Foundation.
    // Read the persisted preference here instead of accessing UI state.
    var errorDescription: String? {
        let english = UserDefaults.standard.string(forKey: "XuZhuo.language") == "en"
        switch self {
        case .unsupportedArchive:
            return english ? "This archive version is not supported." : "存档版本暂不支持。"
        case .duplicateSceneIDs:
            return english ? "The archive contains duplicate session IDs." : "存档中存在重复的项目标识。"
        case .invalidDestination:
            return english ? "Choose an existing folder for the export." : "请选择一个现有文件夹作为导出位置。"
        case .unreadableFolder:
            return english ? "Could not read the resource folder." : "无法读取资料文件夹。"
        case .destinationInsideSource:
            return english ? "The export destination is inside the source folder; the folder was skipped to prevent recursive copying" : "导出位置位于原资料文件夹中，已跳过该文件夹以避免递归复制"
        case .symbolicLink(let name):
            return english ? "Contains the symbolic link \(name); skipped to avoid copying files outside the source" : "包含符号链接 \(name)，为避免复制目标外的资料已跳过"
        case .unsupportedFile(let name):
            return english ? "\(name) is not a regular file or folder that can be copied" : "\(name) 不是可复制的普通文件或文件夹"
        }
    }
}
