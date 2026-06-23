import Foundation
import SwiftData

@MainActor
final class BookLibrary {
    private let storageService: StorageService
    private let appSupportDirectory: URL

    init(storageService: StorageService, appSupportDirectory: URL? = nil) {
        self.storageService = storageService
        self.appSupportDirectory = appSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    func importBook(at url: URL) throws -> Book {
        let fileManager = FileManager.default
        let booksDir = booksDirectory
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

    func deleteBook(_ book: Book) throws {
        let fileURL = URL(fileURLWithPath: book.filePath)
        BookParseCache.shared.invalidate(for: fileURL)
        deleteBookFiles(book)

        if shouldDeleteImportedBookFile(at: fileURL),
           FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        storageService.deleteBook(book)
    }

    func deleteBookFiles(_ book: Book) {
        if let path = book.coverPath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private var booksDirectory: URL {
        appSupportDirectory.appendingPathComponent("Books", isDirectory: true)
    }

    private func shouldDeleteImportedBookFile(at url: URL) -> Bool {
        let filePath = url.standardizedFileURL.path
        let booksPath = booksDirectory.standardizedFileURL.path
        return filePath == booksPath || filePath.hasPrefix(booksPath + "/")
    }
}
