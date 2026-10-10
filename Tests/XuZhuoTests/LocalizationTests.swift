import XCTest
@testable import XuZhuo

final class LocalizationTests: XCTestCase {
    func testLanguageChoicePersistsAcrossSettingsInstances() async throws {
        let suite = "XuZhuoLanguageTests-\(UUID().uuidString)"
        try await MainActor.run {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = LanguageSettings(defaults: defaults)
            XCTAssertEqual(settings.language, .chinese)
            settings.language = .english
            XCTAssertEqual(defaults.string(forKey: LanguageSettings.storageKey), "en")
            XCTAssertEqual(LanguageSettings(defaults: defaults).language, .english)
            settings.language = .chinese
            XCTAssertEqual(LanguageSettings(defaults: defaults).language, .chinese)
        }
    }

    func testUnknownStoredLanguageFallsBackToChinese() async throws {
        let suite = "XuZhuoLanguageTests-\(UUID().uuidString)"
        try await MainActor.run {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("unsupported-language", forKey: LanguageSettings.storageKey)
            XCTAssertEqual(LanguageSettings(defaults: defaults).language, .chinese)
        }
    }

    func testEnglishPresentationKeepsUserContentAndStoredDemoUnchanged() async throws {
        try await MainActor.run {
            let settings = LanguageSettings.shared
            let previousLanguage = settings.language
            let previousStoredValue = UserDefaults.standard.object(forKey: LanguageSettings.storageKey)
            defer {
                settings.language = previousLanguage
                if let previousStoredValue { UserDefaults.standard.set(previousStoredValue, forKey: LanguageSettings.storageKey) }
                else { UserDefaults.standard.removeObject(forKey: LanguageSettings.storageKey) }
            }
            let resource = SceneResource(kind: .web, title: "Apple 人机交互指南", location: "https://developer.apple.com/design/")
            let demo = WorkScene(title: "把论文写完", nextStep: "把研究问题写成一句话，再补三篇相关文献。", isDemo: true, resources: [resource])
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let original = try encoder.encode(demo)
            settings.language = .english
            XCTAssertEqual(L("保存现场", "Save Scene"), "Save Scene")
            XCTAssertEqual(demo.localizedTitle, "Finish the thesis")
            XCTAssertEqual(demo.localizedResourceTitle(resource), "Apple Human Interface Guidelines")
            XCTAssertTrue(demo.localizedNextStep.hasPrefix("Write the research question"))
            XCTAssertEqual(try encoder.encode(demo), original)
            var userScene = demo
            userScene.isDemo = false
            XCTAssertEqual(userScene.localizedTitle, userScene.title)
            XCTAssertEqual(userScene.localizedNextStep, userScene.nextStep)
            XCTAssertEqual(userScene.localizedResourceTitle(resource), resource.title)
            var editedDemo = demo
            editedDemo.title = "我的论文 My thesis"
            editedDemo.nextStep = "先把第三章写完"
            XCTAssertEqual(editedDemo.localizedTitle, editedDemo.title)
            XCTAssertEqual(editedDemo.localizedNextStep, editedDemo.nextStep)
            settings.language = .chinese
            XCTAssertEqual(demo.localizedTitle, demo.title)
            XCTAssertEqual(ResourceKind.folder.localizedTitle, "文件夹")
        }
    }
}
