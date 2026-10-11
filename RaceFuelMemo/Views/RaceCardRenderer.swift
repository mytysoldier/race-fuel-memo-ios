import UIKit

final class RaceCardExport {
    let directory: URL
    let pdfURL: URL
    let imageURLs: [URL]
    let renderer: RaceCardRenderer

    init(directory: URL, pdfURL: URL, imageURLs: [URL], renderer: RaceCardRenderer) {
        self.directory = directory
        self.pdfURL = pdfURL
        self.imageURLs = imageURLs
        self.renderer = renderer
    }

    deinit { removeTemporaryFiles() }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The same TextKit glyph layout is drawn into PDF and PNG. Text flows into additional
/// pages (or physical bands) instead of being truncated or scaled to an unreadable size.
@MainActor
final class RaceCardRenderer {
    static let pageSize = CGSize(width: 595.28, height: 841.89) // A4 in points
    static let bandSize = CGSize(width: 180 * 72 / 25.4, height: 55 * 72 / 25.4)

    let document: RaceCardDocument
    let format: RaceCardFormat
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    private(set) var containers: [NSTextContainer] = []
    private(set) var glyphRanges: [NSRange] = []

    var slotsPerPage: Int { format == .card ? 1 : 4 }
    var pageCount: Int { (containers.count + slotsPerPage - 1) / slotsPerPage }

    init(document: RaceCardDocument, format: RaceCardFormat) throws {
        self.document = document
        self.format = format
        let bodySize: CGFloat = format == .card ? 11 : 9
        let text = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = format == .card ? 4 : 2
        paragraph.lineSpacing = 1
        for section in document.sections {
            text.append(NSAttributedString(string: section.title + "\n", attributes: [
                .font: UIFont.boldSystemFont(ofSize: bodySize + 2),
                .foregroundColor: UIColor(red: 0.05, green: 0.27, blue: 0.36, alpha: 1),
                .paragraphStyle: paragraph
            ]))
            text.append(NSAttributedString(string: section.lines.joined(separator: "\n") + "\n\n", attributes: [
                .font: UIFont.systemFont(ofSize: bodySize), .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]))
        }
        storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(manager)
        manager.allowsNonContiguousLayout = false
        let size = format == .card ? CGSize(width: Self.pageSize.width - 60, height: Self.pageSize.height - 112)
            : CGSize(width: Self.bandSize.width - 20, height: Self.bandSize.height - 34)
        var consumed = 0
        repeat {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            let range = manager.glyphRange(for: container)
            guard range.length > 0, NSMaxRange(range) > consumed else { throw RaceCardError.generationFailed }
            containers.append(container)
            glyphRanges.append(range)
            consumed = NSMaxRange(range)
        } while consumed < manager.numberOfGlyphs
    }

    /// Exposed internally for content-coverage tests, including Japanese and long notes.
    var renderedCharacterRanges: [NSRange] {
        glyphRanges.map { manager.characterRange(forGlyphRange: $0, actualGlyphRange: nil) }
    }

    func image(page: Int, scale: CGFloat = 2) -> UIImage {
        let settings = UIGraphicsImageRendererFormat()
        settings.scale = scale
        settings.opaque = true
        return UIGraphicsImageRenderer(size: Self.pageSize, format: settings).image { context in
            draw(page: page, context: context.cgContext)
        }
    }

    func export() throws -> RaceCardExport {
        let directory = try createPDF()
        do {
            let images = try (0..<pageCount).map { try writeImage(page: $0, directory: directory) }
            return exportedFiles(directory: directory, images: images)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func exportForSharing() async throws -> RaceCardExport {
        try Task.checkCancellation()
        let directory = try createPDF()
        do {
            var images: [URL] = []
            for page in 0..<pageCount {
                try Task.checkCancellation()
                images.append(try writeImage(page: page, directory: directory))
                // Keep controls and the progress indicator responsive for long courses.
                await Task.yield()
            }
            try Task.checkCancellation()
            return exportedFiles(directory: directory, images: images)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func createPDF() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RaceCard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let pdfURL = directory.appendingPathComponent("\(format.title).pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
            try renderer.writePDF(to: pdfURL) { context in
                for page in 0..<pageCount {
                    context.beginPage()
                    draw(page: page, context: context.cgContext)
                }
            }
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func writeImage(page: Int, directory: URL) throws -> URL {
        try autoreleasepool {
            let url = directory.appendingPathComponent("\(format.title)-\(page + 1).png")
            guard let data = image(page: page).pngData() else { throw RaceCardError.generationFailed }
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    private func exportedFiles(directory: URL, images: [URL]) -> RaceCardExport {
        RaceCardExport(directory: directory, pdfURL: directory.appendingPathComponent("\(format.title).pdf"),
                       imageURLs: images, renderer: self)
    }

    func draw(page: Int, context: CGContext) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: Self.pageSize))
        let header = "Running Race Mate / \(format.title) / \(document.audience.title)"
        header.draw(at: CGPoint(x: 30, y: 22), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.black
        ])
        for index in (page * slotsPerPage)..<min((page + 1) * slotsPerPage, containers.count) {
            let origin: CGPoint
            if format == .card {
                origin = CGPoint(x: 30, y: 52)
            } else {
                let rect = CGRect(x: (Self.pageSize.width - Self.bandSize.width) / 2,
                                  y: 52 + CGFloat(index % slotsPerPage) * (Self.bandSize.height + 20),
                                  width: Self.bandSize.width, height: Self.bandSize.height)
                drawBand(index: index, rect: rect, context: context)
                continue
            }
            manager.drawBackground(forGlyphRange: glyphRanges[index], at: origin)
            manager.drawGlyphs(forGlyphRange: glyphRanges[index], at: origin)
        }
        let footer = "\(page + 1) / \(pageCount)" + (format == .paceBand ? "　A4・100%（実際のサイズ）で印刷し、点線に沿って切り取ってください" : "　時刻は月/日・24時間表示")
        footer.draw(at: CGPoint(x: 30, y: Self.pageSize.height - 30), withAttributes: [
            .font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray
        ])
    }

    func drawBand(index: Int, rect: CGRect, context: CGContext) {
        context.setStrokeColor(UIColor.gray.cgColor)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
        "帯 \(index + 1)/\(containers.count)・180 × 55 mm".draw(
            at: CGPoint(x: rect.minX + 10, y: rect.minY + 5),
            withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
        let origin = CGPoint(x: rect.minX + 10, y: rect.minY + 22)
        manager.drawBackground(forGlyphRange: glyphRanges[index], at: origin)
        manager.drawGlyphs(forGlyphRange: glyphRanges[index], at: origin)
    }
}

/// AirPrint lays out bands at their physical size, repaginating for the printable area
/// instead of letting the print system shrink an entire A4 PDF to fit printer margins.
@MainActor
class RaceCardPrintRenderer: UIPrintPageRenderer {
    let source: RaceCardRenderer

    init(source: RaceCardRenderer) { self.source = source; super.init() }

    static func bandsPerPage(in area: CGRect) -> Int {
        max(1, Int((area.height + 12) / (RaceCardRenderer.bandSize.height + 12)))
    }

    override var numberOfPages: Int {
        guard source.format == .paceBand else { return source.pageCount }
        let count = Self.bandsPerPage(in: printableRect)
        return (source.containers.count + count - 1) / count
    }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if source.format == .card {
            let scale = min(printableRect.width / RaceCardRenderer.pageSize.width,
                            printableRect.height / RaceCardRenderer.pageSize.height)
            context.translateBy(x: printableRect.minX, y: printableRect.minY)
            context.scaleBy(x: scale, y: scale)
            source.draw(page: pageIndex, context: context)
        } else {
            // A4/Letter printers fit the 180 mm band without scaling. A narrower
            // printable area cannot hold the physical band; tell the user to select A4.
            guard printableRect.width >= RaceCardRenderer.bandSize.width,
                  printableRect.height >= RaceCardRenderer.bandSize.height else {
                "ペースバンドの原寸印刷には、180 × 55 mm以上の印刷可能領域が必要です。A4用紙を選択してください。".draw(
                    in: printableRect, withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                return
            }
            let slots = Self.bandsPerPage(in: printableRect)
            for index in (pageIndex * slots)..<min((pageIndex + 1) * slots, source.containers.count) {
                let rect = CGRect(x: printableRect.midX - RaceCardRenderer.bandSize.width / 2,
                    y: printableRect.minY + CGFloat(index % slots) * (RaceCardRenderer.bandSize.height + 12),
                    width: RaceCardRenderer.bandSize.width, height: RaceCardRenderer.bandSize.height)
                source.drawBand(index: index, rect: rect, context: context)
            }
        }
    }
}
