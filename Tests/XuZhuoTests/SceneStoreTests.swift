import XCTest
@testable import XuZhuo

final class SceneStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("XuZhuoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSavedProgressAndResourcesSurviveRestart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory, seedExamples: false)
            let source = directory.appendingPathComponent("预算.txt")
            try Data("预算初稿".utf8).write(to: source)
            let window = SavedWindow(bundleID: "com.apple.Preview", applicationName: "预览", title: "预算.pdf", x: 80, y: 60, width: 900, height: 640)
            let scene = WorkScene(title: "项目方案", subtitle: "本周提案", nextStep: "补预算", windows: [window])
            store.save(scene)
            store.toggleFavorite(scene.id)
            let file = SceneResource(kind: .file, title: "预算", location: source.path)
            let sameFile = SceneResource(kind: .file, title: "同一文件", location: source.absoluteString)
            let web = SceneResource(kind: .web, title: "参考", location: "https://example.com/research")
            store.addResources([file, sameFile, web], to: scene.id)
            store.recordCheckpoint(sceneID: scene.id, note: "  下一步补预算\n")
            store.recordCheckpoint(sceneID: scene.id, note: " \n ")
            store.markOpened(scene.id)

            let restored = SceneStore(directory: directory, seedExamples: false)
            let saved = try XCTUnwrap(restored.scene(scene.id))
            XCTAssertNil(restored.errorMessage)
            XCTAssertTrue(saved.isFavorite)
            XCTAssertEqual(saved.resources.count, 2, "相同原文件应去重")
            XCTAssertEqual(saved.windows, [window])
            XCTAssertEqual(saved.nextStep, "下一步补预算")
            XCTAssertEqual(saved.checkpoints.map(\.note), ["下一步补预算"])
            XCTAssertNotNil(saved.lastOpenedAt)
            XCTAssertEqual(try Data(contentsOf: source), Data("预算初稿".utf8))

            restored.delete(scene.id)
            XCTAssertTrue(SceneStore(directory: directory, seedExamples: false).scenes.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "删除存档不应删除原资料")
        }
    }

    func testCorruptArchiveIsPreservedAcrossMutations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let archive = directory.appendingPathComponent("scenes.json")
            let corrupt = Data("{ unfinished archive and original data".utf8)
            try corrupt.write(to: archive)
            let store = SceneStore(directory: directory)
            XCTAssertNotNil(store.errorMessage)
            let scene = WorkScene(title: "尚未保存")
            store.save(scene)
            store.toggleFavorite(scene.id)
            store.recordCheckpoint(sceneID: scene.id, note: "待修复")
            store.delete(scene.id)
            XCTAssertEqual(try Data(contentsOf: archive), corrupt)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testUnknownVersionAndDuplicateIDsDoNotOverwriteArchive() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        struct Archive: Encodable { var version: Int; var scenes: [WorkScene] }
        try await MainActor.run {
            let archiveURL = directory.appendingPathComponent("scenes.json")
            let scene = WorkScene(title: "原存档")
            for archive in [Archive(version: 99, scenes: [scene]), Archive(version: 1, scenes: [scene, scene])] {
                let bytes = try JSONEncoder().encode(archive)
                try bytes.write(to: archiveURL)
                let store = SceneStore(directory: directory, seedExamples: false)
                XCTAssertNotNil(store.errorMessage)
                store.save(WorkScene(title: "新存档"))
                XCTAssertEqual(try Data(contentsOf: archiveURL), bytes)
            }
        }
    }

    func testExportCopiesFilesAndReportsMissingResourcesWithoutMovingOriginals() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let source = directory.appendingPathComponent("方案.pdf")
            let original = Data("source document".utf8)
            try original.write(to: source)
            let sourceFolder = directory.appendingPathComponent("设计", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            let nested = sourceFolder.appendingPathComponent("草稿.txt")
            try Data("nested document".utf8).write(to: nested)
            let exports = directory.appendingPathComponent("exports", isDirectory: true)
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            let scene = WorkScene(title: "提案/秋季", nextStep: "补预算", resources: [
                SceneResource(kind: .file, title: "方案", location: source.path),
                SceneResource(kind: .folder, title: "设计目录", location: sourceFolder.path),
                SceneResource(kind: .file, title: "丢失的资料", location: directory.appendingPathComponent("missing.pdf").path),
                SceneResource(kind: .web, title: "参考网页", location: "https://example.com")
            ])
            let store = SceneStore(directory: directory.appendingPathComponent("store"), seedExamples: false)
            let package = try store.export(scene: scene, to: exports, includeFiles: true)
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent("files/方案.pdf")), original)
            XCTAssertEqual(try String(contentsOf: nested), "nested document")
            XCTAssertEqual(try String(contentsOf: package.appendingPathComponent("files/设计/草稿.txt")), "nested document")
            let report = try String(contentsOf: package.appendingPathComponent("README.md"))
            XCTAssertTrue(report.contains("丢失的资料：未复制"))
            let exported = try JSONDecoder().decode(WorkScene.self, from: Data(contentsOf: package.appendingPathComponent("scene.json")))
            XCTAssertEqual(exported.resources.first?.location, "files/方案.pdf")
            XCTAssertTrue(exported.resources.allSatisfy { $0.bookmarkData == nil })
            let second = try store.export(scene: scene, to: exports, includeFiles: false)
            XCTAssertNotEqual(package, second, "再次导出应创建新目录")
            XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent("files").path))
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    func testExportEscapesHTMLAndRejectsExecutableURLSchemes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory.appendingPathComponent("store"), seedExamples: false)
            let scene = WorkScene(title: "<script>alert('title')</script>", subtitle: "A & B", nextStep: "<img src=x onerror=alert(1)>", resources: [
                SceneResource(kind: .web, title: "<b>标题</b>", location: "https://example.com/?a=1&b=2"),
                SceneResource(kind: .web, title: "恶意链接", location: "javascript:alert(1)"),
                SceneResource(kind: .web, title: "本地资源", location: "file:///etc/passwd")
            ])
            let package = try store.export(scene: scene, to: directory, includeFiles: false)
            let html = try String(contentsOf: package.appendingPathComponent("links.html"))
            XCTAssertFalse(html.contains("<script>"))
            XCTAssertFalse(html.contains("<img "))
            XCTAssertFalse(html.contains("javascript:"))
            XCTAssertFalse(html.contains("file:///"))
            XCTAssertTrue(html.contains("&lt;b&gt;标题&lt;/b&gt;"))
            XCTAssertTrue(html.contains("?a=1&amp;b=2"))
        }
    }

    func testExportDoesNotFollowSymbolicLinks() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let outside = directory.appendingPathComponent("原始资料.txt")
            try Data("private document".utf8).write(to: outside)
            let folder = directory.appendingPathComponent("带链接目录", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let link = folder.appendingPathComponent("资料链接")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            let store = SceneStore(directory: directory.appendingPathComponent("store"), seedExamples: false)
            let scene = WorkScene(title: "符号链接测试", resources: [
                SceneResource(kind: .file, title: "符号链接", location: link.path),
                SceneResource(kind: .folder, title: "带链接目录", location: folder.path)
            ])
            let package = try store.export(scene: scene, to: directory, includeFiles: true)
            let report = try String(contentsOf: package.appendingPathComponent("README.md"))
            XCTAssertTrue(report.contains("符号链接：未复制"))
            XCTAssertTrue(report.contains("带链接目录：未复制"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent("files/资料链接").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent("files/带链接目录").path))
            XCTAssertEqual(try String(contentsOf: outside), "private document")
        }
    }

    func testThumbnailRejectsTraversalAndSymbolicLinks() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory, seedExamples: false)
            let scene = WorkScene(title: "桌面")
            let bytes = Data("thumbnail bytes".utf8)
            let name = try store.storeThumbnail(bytes, for: scene.id)
            var saved = scene
            saved.thumbnailName = name
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.thumbnailURL(for: saved))), bytes)
            saved.thumbnailName = "../scenes.json"
            XCTAssertNil(store.thumbnailURL(for: saved))
            let linkName = "symbolic.png"
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("thumbnails/\(linkName)"), withDestinationURL: directory.appendingPathComponent("thumbnails/\(name)"))
            saved.thumbnailName = linkName
            XCTAssertNil(store.thumbnailURL(for: saved))
        }
    }

    func testExportInsideSourceFolderSkipsRecursiveCopy() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let source = directory.appendingPathComponent("项目", isDirectory: true)
            let destination = source.appendingPathComponent("交接", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let sourceFile = source.appendingPathComponent("原稿.txt")
            try Data("original document".utf8).write(to: sourceFile)
            let scene = WorkScene(title: "项目交接", resources: [SceneResource(kind: .folder, title: "项目目录", location: source.path)])
            let store = SceneStore(directory: directory.appendingPathComponent("store"), seedExamples: false)
            let package = try store.export(scene: scene, to: destination, includeFiles: true)
            let report = try String(contentsOf: package.appendingPathComponent("README.md"))
            XCTAssertTrue(report.contains("项目目录：未复制"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent("files/项目").path))
            XCTAssertEqual(try String(contentsOf: sourceFile), "original document")
        }
    }
}
