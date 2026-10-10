import Foundation

enum ResourceKind: String, Codable, CaseIterable {
    case file, folder, web
}

struct SceneResource: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ResourceKind
    var title: String
    var location: String
    var bookmarkData: Data?

    init(id: UUID = UUID(), kind: ResourceKind, title: String, location: String,
         bookmarkData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.location = location
        self.bookmarkData = bookmarkData
    }

    /// Resolves a bookmark when available, falling back to the original location.
    /// The caller starts security-scoped access while reading or opening a file.
    func resolvedURL() -> URL? {
        if kind == .web {
            guard let url = URL(string: location),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else { return nil }
            return url
        }
        if let bookmarkData {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData,
                                  options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        if let url = URL(string: location), url.isFileURL { return url }
        guard location.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: location, isDirectory: kind == .folder)
    }

    /// Access is balanced even when the supplied operation throws.
    func withResolvedURL<T>(_ operation: (URL) throws -> T) rethrows -> T? {
        guard let url = resolvedURL() else { return nil }
        let accessing = kind != .web && url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try operation(url)
    }
}

struct SavedWindow: Identifiable, Codable, Equatable {
    var id: UUID
    var bundleID: String
    var applicationName: String
    var title: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(id: UUID = UUID(), bundleID: String, applicationName: String, title: String,
         x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.bundleID = bundleID
        self.applicationName = applicationName
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct SceneCheckpoint: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), note: String) {
        self.id = id
        self.date = date
        self.note = note
    }
}

struct WorkScene: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var subtitle: String
    var symbol: String
    var tint: String
    var nextStep: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isFavorite: Bool
    var isDemo: Bool
    var resources: [SceneResource]
    var windows: [SavedWindow]
    var checkpoints: [SceneCheckpoint]
    var thumbnailName: String?

    init(id: UUID = UUID(), title: String, subtitle: String = "", symbol: String = "folder",
         tint: String = "sage", nextStep: String = "", createdAt: Date = Date(),
         updatedAt: Date = Date(), lastOpenedAt: Date? = nil, isFavorite: Bool = false,
         isDemo: Bool = false, resources: [SceneResource] = [], windows: [SavedWindow] = [],
         checkpoints: [SceneCheckpoint] = [], thumbnailName: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.nextStep = nextStep
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.isFavorite = isFavorite
        self.isDemo = isDemo
        self.resources = resources
        self.windows = windows
        self.checkpoints = checkpoints
        self.thumbnailName = thumbnailName
    }
}
