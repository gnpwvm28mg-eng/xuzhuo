import XCTest
@testable import XuZhuo

/// These smoke tests deliberately contain no real resources or saved windows.
/// They never call browser automation or the explicit permission request APIs.
final class WorkspaceServiceTests: XCTestCase {
    @MainActor
    func testEmptySceneRestoresWithoutReportingSuccessOrOpeningAnything() async {
        let service = WorkspaceService()
        let report = await service.restore(WorkScene(title: "空现场"))

        XCTAssertEqual(report.opened, 0)
        XCTAssertEqual(report.positioned, 0)
        XCTAssertTrue(report.issues.isEmpty)
    }

    @MainActor
    func testMissingFilesAndFoldersAreReportedWithoutBeingOpened() async {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("XuZhuo-missing-\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingRoot.path))
        let resources = [
            SceneResource(kind: .file, title: "缺失预算", location: missingRoot.appendingPathComponent("budget.pdf").path),
            SceneResource(kind: .folder, title: "缺失设计目录", location: missingRoot.appendingPathComponent("design", isDirectory: true).path)
        ]
        let report = await WorkspaceService().restore(WorkScene(title: "缺失资料", resources: resources))

        XCTAssertEqual(report.opened, 0, "原资料缺失时不能计为已打开")
        XCTAssertEqual(report.positioned, 0)
        XCTAssertEqual(report.issues.count, resources.count)
        for resource in resources {
            XCTAssertTrue(report.issues.contains { $0.contains(resource.title) && $0.contains("原文件已移动、删除或无法访问") })
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingRoot.path), "恢复失败不应创建原资料")
    }

    @MainActor
    func testInvalidWebProtocolsAreRejectedBeforeAnyWorkspaceOpen() async {
        let locations = ["javascript:alert(1)", "data:text/plain,example", "mailto:nobody@example.invalid", "file:///not-a-web-resource", "https://"]
        let resources = locations.enumerated().map {
            SceneResource(kind: .web, title: "非法协议 \($0.offset)", location: $0.element)
        }
        XCTAssertTrue(resources.allSatisfy { $0.resolvedURL() == nil })
        let report = await WorkspaceService().restore(WorkScene(title: "无效链接", resources: resources))

        XCTAssertEqual(report.opened, 0, "无效或可执行协议不能计为已打开")
        XCTAssertEqual(report.positioned, 0)
        XCTAssertEqual(report.issues.count, resources.count)
        for resource in resources {
            XCTAssertTrue(report.issues.contains { $0.contains(resource.title) && $0.contains("地址无效") })
        }
    }

    @MainActor
    func testDesktopCaptureWithoutPermissionReturnsFallbackWithoutRequestingAccess() async throws {
        let service = WorkspaceService()
        // When the test runner already has permission, skip the call entirely:
        // this suite must never take a screenshot of the user's desktop.
        guard !service.screenCaptureGranted else {
            throw XCTSkip("测试进程已有录屏权限；为避免截取真实桌面，跳过捕获调用。")
        }
        let result = await service.captureDesktop()

        XCTAssertNil(result.data)
        XCTAssertTrue(result.message?.contains("尚未开启屏幕录制权限") == true)
        XCTAssertFalse(service.screenCaptureGranted)
    }
}
