import AppKit
import UniformTypeIdentifiers

@MainActor
enum ResourceImport {
    static func resource(for url: URL) -> SceneResource? {
        if url.isFileURL {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            return SceneResource(kind: folder ? .folder : .file, title: url.lastPathComponent, location: url.path, bookmarkData: bookmark)
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return SceneResource(kind: .web, title: url.host ?? url.absoluteString, location: url.absoluteString)
    }

    static func chooseFiles() -> [SceneResource] {
        let panel = NSOpenPanel()
        panel.title = L("添加到现场", "Add to Session")
        panel.message = L("文件只保存引用，仍保留在原位置。", "Files stay in their original locations. Only references are saved.")
        panel.prompt = L("添加资料", "Add Resources")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls.compactMap(resource(for:)) : []
    }

    static func load(_ providers: [NSItemProvider], completion: @escaping ([SceneResource]) -> Void) {
        Task { @MainActor in
            var resources: [SceneResource] = []
            for provider in providers {
                let identifier = [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier].first { provider.hasItemConformingToTypeIdentifier($0) }
                guard let identifier else { continue }
                let item: NSSecureCoding? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in continuation.resume(returning: item) }
                }
                var url = item as? URL
                if url == nil, let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if url == nil, let string = item as? String {
                    url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if let url, let resource = resource(for: url), !resources.contains(where: { $0.location == resource.location }) { resources.append(resource) }
            }
            completion(resources)
        }
    }
}
