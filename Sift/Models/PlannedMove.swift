import Foundation

struct ScannedFile: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let fileExtension: String
    let createdAt: Date

    init(url: URL, createdAt: Date) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        self.fileExtension = ext.isEmpty ? LocalizationManager.noExtensionToken : ext
        self.createdAt = createdAt
    }
}

struct PlannedMove: Identifiable, Hashable {
    let id: URL
    let source: URL
    let destination: URL
    let groupName: String

    var fileName: String { source.lastPathComponent }

    var destinationFolder: String {
        destination.deletingLastPathComponent().lastPathComponent
    }
}

enum OrganizeResult {
    case success(moved: Int, skipped: Int)
    case failure(String)
}
