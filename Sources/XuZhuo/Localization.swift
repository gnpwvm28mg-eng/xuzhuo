import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }
    var nativeName: String { self == .chinese ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: self == .chinese ? "zh-Hans" : "en") }
}

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    static let storageKey = "XuZhuo.language"
    private let defaults: UserDefaults

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .chinese
    }

    func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }
}

@MainActor
func L(_ chinese: String, _ english: String) -> String {
    LanguageSettings.shared.text(chinese, english)
}

extension ResourceKind {
    @MainActor var localizedTitle: String {
        switch self {
        case .file: return L("文件", "File")
        case .folder: return L("文件夹", "Folder")
        case .web: return L("网页", "Web link")
        }
    }
}

extension WorkScene {
    @MainActor var localizedTitle: String { localizedDemoText(title) }
    @MainActor var localizedSubtitle: String { localizedDemoText(subtitle) }
    @MainActor var localizedNextStep: String { localizedDemoText(nextStep) }

    @MainActor func localizedResourceTitle(_ resource: SceneResource) -> String {
        guard isDemo else { return resource.title }
        switch resource.title {
        case "Apple 人机交互指南": return L(resource.title, "Apple Human Interface Guidelines")
        case "Wikivoyage 旅行指南": return L(resource.title, "Wikivoyage Travel Guide")
        default: return resource.title
        }
    }

    /// Translation is presentation-only. Edited titles, notes, and saved JSON keep the user's text.
    @MainActor private func localizedDemoText(_ text: String) -> String {
        guard isDemo else { return text }
        let examples: [String: String] = [
            "把论文写完": "Finish the thesis",
            "新一轮设计": "The next design",
            "计划一次旅行": "Plan a trip",
            "示例 · 思路、文献和下一段": "Example · Ideas, sources, and the next paragraph",
            "示例 · 灵感、规范和待完善的细节": "Example · Inspiration, guidelines, and details",
            "示例 · 路线、清单和出发前的小事": "Example · Routes, checklists, and preparations",
            "把研究问题写成一句话，再补三篇相关文献。": "Write the research question in one sentence, then add three related papers.",
            "先梳理首页的阅读顺序，再画一版简单的线框。": "Map the homepage reading order, then sketch a simple wireframe.",
            "选定第一站，把交通时间和住宿预算记下来。": "Choose the first stop and note the travel time and accommodation budget."
        ]
        return L(text, examples[text] ?? text)
    }
}

extension Date {
    @MainActor func localizedSceneDate(includeTime: Bool = false) -> String {
        if includeTime {
            return formatted(.dateTime.month().day().hour().minute().locale(LanguageSettings.shared.language.locale))
        }
        return formatted(.dateTime.month().day().locale(LanguageSettings.shared.language.locale))
    }
}
