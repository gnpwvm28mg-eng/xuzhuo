import XCTest
@testable import XuZhuo

final class SceneStoreFailureTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("XuZhuoFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A directory at the archive path forces a deterministic write failure
    /// without changing filesystem permissions or requesting system access.
    private func blockArchive(in directory: URL) throws {
        let archive = directory.appendingPathComponent("scenes.json")
        if FileManager.default.fileExists(atPath: archive.path) {
            try FileManager.default.moveItem(at: archive, to: directory.appendingPathComponent("previous-scenes.json"))
        }
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
    }

    func testFailedMutationsDoNotChangeCurrentScenes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory, seedExamples: false)
            let scene = WorkScene(title: "已保存项目", nextStep: "补预算")
            XCTAssertTrue(store.save(scene))
            let before = store.scenes
            try blockArchive(in: directory)

            XCTAssertFalse(store.save(WorkScene(title: "保存失败的项目")))
            XCTAssertEqual(store.scenes, before)
            var changed = try XCTUnwrap(store.scene(scene.id))
            changed.title = "保存失败的改名"
            XCTAssertFalse(store.save(changed))
            XCTAssertEqual(store.scenes, before)
            XCTAssertFalse(store.toggleFavorite(scene.id))
            XCTAssertEqual(store.scenes, before)
            XCTAssertFalse(store.addResources([SceneResource(kind: .web, title: "参考", location: "https://example.com")], to: scene.id))
            XCTAssertEqual(store.scenes, before)
            XCTAssertFalse(store.markOpened(scene.id))
            XCTAssertEqual(store.scenes, before)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testFailedDeletePreservesSceneAndThumbnail() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory, seedExamples: false)
            var scene = WorkScene(title: "留在这里")
            let data = Data("thumbnail".utf8)
            scene.thumbnailName = try store.storeThumbnail(data, for: scene.id)
            XCTAssertTrue(store.save(scene))
            let before = store.scenes
            let thumbnail = try XCTUnwrap(store.thumbnailURL(for: scene))
            try blockArchive(in: directory)

            XCTAssertFalse(store.delete(scene.id))
            XCTAssertEqual(store.scenes, before)
            XCTAssertEqual(try Data(contentsOf: thumbnail), data)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testSuccessfulRetryClearsErrorAndSavesOnlyOneScene() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory, seedExamples: false)
            try blockArchive(in: directory)
            XCTAssertFalse(store.save(WorkScene(title: "重试项目")))
            XCTAssertFalse(store.save(WorkScene(title: "重试项目")))
            XCTAssertTrue(store.scenes.isEmpty)
            XCTAssertNotNil(store.errorMessage)

            try FileManager.default.removeItem(at: directory.appendingPathComponent("scenes.json"))
            let scene = WorkScene(title: "重试项目")
            XCTAssertTrue(store.save(scene))
            XCTAssertNil(store.errorMessage)
            XCTAssertEqual(store.scenes.map(\.id), [scene.id])
            let reloaded = SceneStore(directory: directory, seedExamples: false)
            XCTAssertEqual(reloaded.scenes, store.scenes)
        }
    }

    func testFailedCheckpointDoesNotDuplicateRecordOnRetry() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = SceneStore(directory: directory, seedExamples: false)
            let scene = WorkScene(title: "收工", nextStep: "补预算")
            XCTAssertTrue(store.save(scene))
            let before = store.scenes
            try blockArchive(in: directory)

            XCTAssertFalse(store.recordCheckpoint(sceneID: scene.id, note: "预算初稿完成"))
            XCTAssertFalse(store.recordCheckpoint(sceneID: scene.id, note: "预算初稿完成"))
            XCTAssertEqual(store.scenes, before)

            try FileManager.default.removeItem(at: directory.appendingPathComponent("scenes.json"))
            XCTAssertTrue(store.recordCheckpoint(sceneID: scene.id, note: "预算初稿完成"))
            XCTAssertNil(store.errorMessage)
            let saved = try XCTUnwrap(store.scene(scene.id))
            XCTAssertEqual(saved.checkpoints.map(\.note), ["预算初稿完成"])
            XCTAssertEqual(saved.nextStep, "预算初稿完成", "保留旧 API 的提醒语义")
            XCTAssertEqual(SceneStore(directory: directory, seedExamples: false).scene(scene.id), saved)
        }
    }
}
