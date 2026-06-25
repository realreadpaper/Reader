import Foundation

final class KindleParser: BookParser {
    private let mobiParser: MOBIParser

    init(converter: MOBIConverting = MOBIConverter()) {
        self.mobiParser = MOBIParser(converter: converter)
    }

    func parse(fileAt url: URL) async throws -> ParsedBook {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        BookLog.mobi.info("KindleParser: start url=\(url.lastPathComponent, privacy: .public) size=\(fileSize)")

        if (try? isDRMProtected(url)) == true {
            BookLog.mobi.notice("KindleParser: DRM detected, falling back to calibre")
            return try await mobiParser.parseViaCalibre(fileAt: url)
        }

        do {
            let result = try await mobiParser.parse(fileAt: url)
            BookLog.mobi.info("KindleParser: native OK chapters=\(result.chapters.count)")
            return result
        } catch {
            BookLog.mobi.error("KindleParser: native failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func isDRMProtected(_ url: URL) throws -> Bool {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        let header = try MOBIHeader.read(pdb: pdb)
        BookLog.mobi.info("KindleParser: DRM check drmOffset=\(header.drmOffset) hasDRM=\(header.hasDRM)")
        return header.hasDRM
    }
}
