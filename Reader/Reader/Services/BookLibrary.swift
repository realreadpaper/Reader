import Foundation
import SwiftData

@MainActor
final class BookLibrary {
    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    func importBook(at url: URL) throws -> Book {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let booksDir = appSupport.appendingPathComponent("Books", isDirectory: true)
        try fileManager.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let destination = booksDir.appendingPathComponent(url.lastPathComponent)
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: url, to: destination)
        }

        let ext = url.pathExtension.lowercased()
        let fileType = FileType(rawValue: ext) ?? .epub
        let title = url.deletingPathExtension().lastPathComponent

        return storageService.addBook(title: title, filePath: destination.path, fileType: fileType)
    }

    func deleteBookFiles(_ book: Book) {
        if let path = book.coverPath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
