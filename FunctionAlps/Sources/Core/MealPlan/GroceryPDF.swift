import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The grocery PDF: an A4 page (more when the list is long), the title, then each aisle with a tick box per line.
/// The layout is pure (`paginate`) so the page breaks are tested without a renderer; `render` draws it with
/// `UIGraphicsPDFRenderer` and needs no permission, no EventKit, no network.
enum GroceryPDF {
    enum Row: Sendable, Equatable {
        case heading(String)
        case line(String)
    }

    struct Metrics: Sendable, Equatable {
        var pageWidth: Double = 595
        var pageHeight: Double = 842
        var margin: Double = 48
        var titleBlock: Double = 70
        var headingHeight: Double = 34
        var lineHeight: Double = 22

        var contentHeight: Double { pageHeight - margin * 2 }
    }

    /// Splits the sections into pages. The title sits on page 1. A heading is never the last row of a page: it moves
    /// to the next page together with its first line.
    static func paginate(_ sections: [GroceryShareSection], metrics m: Metrics = Metrics()) -> [[Row]] {
        var pages: [[Row]] = [[]]
        var used = m.titleBlock
        for section in sections where !section.lines.isEmpty {
            if used + m.headingHeight + m.lineHeight > m.contentHeight, !(pages.last ?? []).isEmpty {
                pages.append([]); used = 0
            }
            pages[pages.count - 1].append(.heading(section.title))
            used += m.headingHeight
            for line in section.lines {
                if used + m.lineHeight > m.contentHeight {
                    pages.append([]); used = 0
                }
                pages[pages.count - 1].append(.line(line))
                used += m.lineHeight
            }
        }
        return pages
    }

    #if canImport(UIKit)
    static func render(sections: [GroceryShareSection], title: String, subtitle: String?, metrics m: Metrics = Metrics()) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: m.pageWidth, height: m.pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let pages = paginate(sections, metrics: m)
        let ink = UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x16 / 255, alpha: 1)
        let muted = UIColor(red: 0x7A / 255, green: 0x79 / 255, blue: 0x6F / 255, alpha: 1)
        let forest = UIColor(red: 0x2E / 255, green: 0x54 / 255, blue: 0x38 / 255, alpha: 1)
        let titleFont = UIFont(name: "DMSerifDisplay-Regular", size: 24) ?? UIFont.systemFont(ofSize: 24, weight: .bold)
        let headingFont = UIFont.systemFont(ofSize: 11, weight: .bold)
        let lineFont = UIFont.systemFont(ofSize: 13)
        let width = m.pageWidth - m.margin * 2

        return renderer.pdfData { context in
            for (index, rows) in pages.enumerated() {
                context.beginPage()
                var y = m.margin
                if index == 0 {
                    (title as NSString).draw(in: CGRect(x: m.margin, y: y, width: width, height: 32),
                                             withAttributes: [.font: titleFont, .foregroundColor: ink])
                    if let subtitle {
                        (subtitle as NSString).draw(in: CGRect(x: m.margin, y: y + 34, width: width, height: 18),
                                                    withAttributes: [.font: lineFont, .foregroundColor: muted])
                    }
                    y += m.titleBlock
                }
                for row in rows {
                    switch row {
                    case .heading(let text):
                        (text.uppercased() as NSString).draw(
                            in: CGRect(x: m.margin, y: y + 12, width: width, height: 16),
                            withAttributes: [.font: headingFont, .foregroundColor: forest, .kern: 0.9])
                        y += m.headingHeight
                    case .line(let text):
                        let box = CGRect(x: m.margin, y: y + 3, width: 11, height: 11)
                        let path = UIBezierPath(roundedRect: box, cornerRadius: 2)
                        path.lineWidth = 1
                        muted.setStroke()
                        path.stroke()
                        (text as NSString).draw(in: CGRect(x: m.margin + 20, y: y, width: width - 20, height: m.lineHeight),
                                                withAttributes: [.font: lineFont, .foregroundColor: ink])
                        y += m.lineHeight
                    }
                }
            }
        }
    }

    /// Writes the PDF to a temporary file the share sheet can hand on (Files, Mail, AirDrop, print).
    static func writeTemporaryFile(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
    #endif
}
