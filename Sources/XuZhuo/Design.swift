import SwiftUI
import AppKit

enum DeskStyle {
    static let background = Color(hex: 0xF7F7F2)
    static let sidebar = Color(hex: 0xEEEEE6)
    static let ink = Color(hex: 0x243A2F)
    static let secondary = Color(hex: 0x7E867C)
    static let line = Color(hex: 0xE3E5DC)
    static let green = Color(hex: 0x315D48)
    static let paleGreen = Color(hex: 0xE7EDE2)
    static func tint(_ name: String) -> Color {
        switch name {
        case "clay", "orange", "peach": return Color(hex: 0xC28361)
        case "blue", "sky": return Color(hex: 0x6E91A0)
        case "lavender", "purple": return Color(hex: 0x9C8CAA)
        default: return Color(hex: 0x73917B)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

@MainActor
struct BrandMark: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(DeskStyle.ink)
            RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.35), lineWidth: 1.4)
                .frame(width: size * 0.43, height: size * 0.32).offset(x: -3, y: -4)
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xD9E5CB))
                .frame(width: size * 0.43, height: size * 0.32).offset(x: 3, y: 3)
            Image(systemName: "arrow.right").font(.system(size: size * 0.20, weight: .bold))
                .foregroundStyle(DeskStyle.ink).offset(x: 3, y: 3)
        }.frame(width: size, height: size)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 17).padding(.vertical, 12)
            .background(DeskStyle.green.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.42)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(DeskStyle.ink)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(configuration.isPressed ? DeskStyle.paleGreen : Color.white, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(DeskStyle.line))
    }
}

@MainActor
struct Tag: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10)) }
            Text(text).font(.system(size: 10, weight: .medium))
        }.foregroundStyle(DeskStyle.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(DeskStyle.background, in: Capsule())
    }
}

@MainActor
struct DesktopPreview: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let scene: WorkScene
    var compact = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [DeskStyle.tint(scene.tint).opacity(0.68), DeskStyle.tint(scene.tint).opacity(0.35), Color(hex: 0xDFE5D7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.12)).frame(width: geo.size.width * 0.8).offset(x: geo.size.width * 0.4, y: geo.size.height * 0.3)
                Circle().stroke(.white.opacity(0.16), lineWidth: 35).frame(width: geo.size.width * 0.9).offset(x: -geo.size.width * 0.38, y: geo.size.height * 0.3)
                // Illustrative windows are deliberately labeled as a preview, never a captured desktop.
                miniatureWindow(title: scene.isDemo ? L("项目笔记", "Project Notes") : scene.localizedTitle, browser: false)
                    .frame(width: geo.size.width * 0.48, height: geo.size.height * 0.67)
                    .rotationEffect(.degrees(-3)).offset(x: -geo.size.width * 0.14, y: 4)
                miniatureWindow(title: scene.resources.first.map { scene.localizedResourceTitle($0) } ?? L("相关资料", "Resources"), browser: true)
                    .frame(width: geo.size.width * 0.47, height: geo.size.height * 0.60)
                    .rotationEffect(.degrees(3)).offset(x: geo.size.width * 0.19, y: -geo.size.height * 0.05)
                VStack {
                    HStack {
                        Text(L("布局示意", "Layout Preview")).font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.7), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(["safari.fill", "folder.fill", "doc.text.fill", "note.text"], id: \.self) { icon in
                            Image(systemName: icon).font(.system(size: compact ? 9 : 12))
                                .foregroundStyle(DeskStyle.ink.opacity(0.65))
                                .frame(width: compact ? 18 : 23, height: compact ? 18 : 23)
                                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }.padding(5).background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                }.padding(compact ? 10 : 14)
            }.clipped()
        }
    }

    private func miniatureWindow(title: String, browser: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([0xDF9D95, 0xE3C38B, 0xA7BE96], id: \.self) { hex in
                    Circle().fill(Color(hex: UInt32(hex))).frame(width: 4, height: 4)
                }
                Text(title).font(.system(size: 6)).foregroundStyle(DeskStyle.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(6).background(Color(hex: 0xF2F1EC))
            if browser {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(DeskStyle.tint(scene.tint).opacity(0.5)).frame(width: 20, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(DeskStyle.ink.opacity(0.22)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 1).fill(DeskStyle.ink.opacity(0.1)).frame(height: 3)
                    }
                }.padding(9)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scene.isDemo ? L("思路，从这里接上。", "Pick up your ideas here.") : L("下一步", "Next Step")).font(.system(size: 8, weight: .semibold))
                        ForEach(0..<3) { index in
                            RoundedRectangle(cornerRadius: 1).fill(DeskStyle.ink.opacity(0.09))
                                .frame(maxWidth: index == 2 ? 45 : .infinity).frame(height: 3)
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(10)
            }
            Spacer(minLength: 0)
        }.background(Color(hex: 0xFFFFFB), in: RoundedRectangle(cornerRadius: 5))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

@MainActor
struct SceneCover: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let scene: WorkScene
    let store: SceneStore
    var body: some View {
        if let url = store.thumbnailURL(for: scene), let image = NSImage(contentsOf: url) {
            GeometryReader { geometry in
                Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        } else {
            DesktopPreview(scene: scene)
        }
    }
}

extension ResourceKind {
    var symbol: String {
        switch self { case .file: return "doc.text"; case .folder: return "folder"; case .web: return "link" }
    }
    @MainActor var label: String { localizedTitle }
}
