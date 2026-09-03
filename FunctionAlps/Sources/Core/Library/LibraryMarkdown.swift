import Foundation

/// Tiny markdown → block parser for the reader — deliberately NOT a markdown library. The
/// corpus is prose, bullets, bold/italic runs and block-level images (the Article Block
/// System survey, 2026-08-11: zero tables). Same rules as the Expo `lib/library/markdown.ts`.
enum LibraryMarkdown {
    struct Run: Equatable, Sendable {
        let text: String
        var bold = false
        var italic = false
    }

    enum Block: Equatable, Sendable {
        case heading(level: Int, runs: [Run])
        case paragraph([Run])
        case bullets([[Run]])
        case numbered([[Run]])
        case image(src: String, alt: String)
    }

    /// `**bold**`, `*italic*` and `_italic_` runs; everything else is plain text.
    static func parseInline(_ text: String) -> [Run] {
        var runs: [Run] = []
        let pattern = #"(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(_([^_]+)_)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [Run(text: text)] }
        let ns = text as NSString
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                runs.append(Run(text: ns.substring(with: NSRange(location: last, length: m.range.location - last))))
            }
            if m.range(at: 2).location != NSNotFound {
                runs.append(Run(text: ns.substring(with: m.range(at: 2)), bold: true))
            } else {
                let r = m.range(at: 4).location != NSNotFound ? m.range(at: 4) : m.range(at: 6)
                runs.append(Run(text: ns.substring(with: r), italic: true))
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length { runs.append(Run(text: ns.substring(from: last))) }
        return runs.isEmpty ? [Run(text: text)] : runs
    }

    static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        var para: [String] = []
        var list: (ordered: Bool, items: [String])?

        func flushPara() {
            let text = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(parseInline(text))) }
            para = []
        }
        func flushList() {
            if let list, !list.items.isEmpty {
                let items = list.items.map(parseInline)
                blocks.append(list.ordered ? .numbered(items) : .bullets(items))
            }
            list = nil
        }

        let imageLine = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^\s)]+)\)$"#)
        let heading = try! NSRegularExpression(pattern: #"^(#{1,3})\s+(.*)$"#)
        let bullet = try! NSRegularExpression(pattern: #"^[-*•]\s+(.*)$"#)
        let numbered = try! NSRegularExpression(pattern: #"^\d+[.)]\s+(.*)$"#)

        for raw in md.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let ns = trimmed as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let m = imageLine.firstMatch(in: trimmed, range: full) {
                flushPara(); flushList()
                blocks.append(.image(src: ns.substring(with: m.range(at: 2)), alt: ns.substring(with: m.range(at: 1))))
                continue
            }
            if let m = heading.firstMatch(in: trimmed, range: full) {
                flushPara(); flushList()
                blocks.append(.heading(level: m.range(at: 1).length, runs: parseInline(ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces))))
                continue
            }
            if let m = bullet.firstMatch(in: trimmed, range: full) {
                flushPara()
                if list == nil || list!.ordered { flushList(); list = (false, []) }
                list!.items.append(ns.substring(with: m.range(at: 1)))
                continue
            }
            if let m = numbered.firstMatch(in: trimmed, range: full) {
                flushPara()
                if list == nil || !list!.ordered { flushList(); list = (true, []) }
                list!.items.append(ns.substring(with: m.range(at: 1)))
                continue
            }
            if trimmed.isEmpty { flushPara(); flushList(); continue }
            // A plain line continues the paragraph. A list is interrupted by prose, not continued by it.
            flushList()
            para.append(trimmed)
        }
        flushPara(); flushList()
        return blocks
    }
}
