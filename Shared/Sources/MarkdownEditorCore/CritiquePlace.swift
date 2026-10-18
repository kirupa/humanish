import Foundation

/// Where a critique note is, said the way the author would say it:
/// "Why caching matters · paragraph 2".
///
/// Worked out from where the note is anchored rather than taken from the
/// critic. The critic writes a location with every finding, and the rail used
/// to print it as written — which was not the same from one run to the next.
/// The same paragraph was "Opening, paragraph 2" on one read and "Opening,
/// paragraph 1" on the next, because whether the title counts as a paragraph
/// is a judgement the model makes afresh every time. It was also fixed at the
/// moment of the read, so a paragraph added above a note left its label naming
/// the one before.
public struct CritiquePlace: Equatable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case title, heading, paragraph, list, quote, code
    }

    /// The heading of the section the passage is in, as the page shows it:
    /// markup taken out, and shortened when long. Nil before the first
    /// section heading. A heading's section is itself.
    public let section: String?
    public let kind: Kind
    /// Which of its kind in its section, from 1.
    ///
    /// Paragraphs are always numbered, because that is how people point at
    /// them. A list, quote or code block is numbered only when its section
    /// has more than one: "list 1" sends the reader looking for a list 2.
    public let number: Int?
    /// Whether the draft has section headings at all, which is what decides
    /// between "Opening · paragraph 2" and plain "Paragraph 2". A draft that
    /// is all opening has no opening.
    public let isSectioned: Bool

    public init(section: String?, kind: Kind, number: Int?, isSectioned: Bool) {
        self.section = section
        self.kind = kind
        self.number = number
        self.isSectioned = isSectioned
    }

    public var label: String {
        if kind == .title { return "Title" }
        let part: String
        switch kind {
        case .title, .heading: part = "heading"
        case .paragraph: part = "paragraph \(number ?? 1)"
        case .list: part = number.map { "list \($0)" } ?? "list"
        case .quote: part = number.map { "quote \($0)" } ?? "quote"
        case .code: part = number.map { "code block \($0)" } ?? "code block"
        }
        if let section { return "\(section) · \(part)" }
        if isSectioned { return "Opening · \(part)" }
        return part.prefix(1).uppercased() + part.dropFirst()
    }
}

/// The draft's blocks, each with the place a note in it is named for.
///
/// Counted the way the editor draws the draft rather than the way CommonMark
/// would parse it. Humanish's renderer is line-based — ATX headings only, a list
/// or quote line is one wherever it falls, a fence hides everything until it
/// closes — and a label that disagreed with the page would be one more way of
/// pointing at the wrong paragraph.
///
/// One linear pass. It is rebuilt when a critique lands and when an edit can
/// change the draft's shape (see `mayMovePlaces`), never per keystroke inside
/// a paragraph.
public struct CritiqueOutline: Sendable {
    struct Block: Equatable, Sendable {
        let range: NSRange
        let place: CritiquePlace
    }

    /// In document order, without overlaps. Blank lines, rules and front
    /// matter belong to none of them.
    let blocks: [Block]

    public init(_ text: String) {
        blocks = Scan(text as NSString).blocks()
    }

    /// Where a passage is: the block it starts in, or — for a passage that
    /// starts in the gap before a block — the first block it reaches.
    public func place(of range: NSRange) -> CritiquePlace? {
        var low = 0
        var high = blocks.count
        while low < high {
            let middle = (low + high) / 2
            if blocks[middle].range.location <= range.location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let before = low - 1
        if before >= 0, range.location < NSMaxRange(blocks[before].range) {
            return blocks[before].place
        }
        if low < blocks.count, NSIntersectionRange(range, blocks[low].range).length > 0 {
            return blocks[low].place
        }
        return before >= 0 ? blocks[before].place : nil
    }

    /// Whether an edit could have changed any note's place.
    ///
    /// Places only move when the draft's shape does: a line broken or joined,
    /// a line that changes what it is — text to heading, item to paragraph,
    /// blank to anything — or a heading's own words, since every note under
    /// it is named for them. Typing inside a paragraph, which is nearly every
    /// keystroke, is none of those and costs a line's worth of looking rather
    /// than a pass over the draft.
    public static func mayMovePlaces(
        from previous: String,
        to current: String,
        through edit: CritiqueAnchorTracking.Edit
    ) -> Bool {
        let before = previous as NSString
        let after = current as NSString
        let removed = NSRange(location: edit.location, length: edit.removed)
        let inserted = NSRange(location: edit.location, length: edit.inserted)
        guard NSMaxRange(removed) <= before.length,
              NSMaxRange(inserted) <= after.length
        else { return true }
        // Every line terminator `NSString` knows, not just "\n": the outline
        // breaks lines where `getLineStart` does, and a pasted U+2028 is one.
        if edit.removed > 0,
           before.rangeOfCharacter(from: .newlines, options: [], range: removed).location != NSNotFound {
            return true
        }
        if edit.inserted > 0,
           after.rangeOfCharacter(from: .newlines, options: [], range: inserted).location != NSNotFound {
            return true
        }
        // Front matter is decided by its first two lines, an opening `---`
        // and a key under it, so a key typed there can make or unmake it.
        if edit.location <= Scan.endOfSecondLine(in: before),
           Scan.opensFrontMatter(before) || Scan.opensFrontMatter(after) {
            return true
        }
        let was = Scan.kind(ofLineAt: edit.location, in: before)
        let now = Scan.kind(ofLineAt: edit.location, in: after)
        if was != now { return true }
        switch was {
        case .heading, .fence: return true
        default: return false
        }
    }
}

// MARK: - The pass

extension CritiqueOutline {
    /// What one line is, by the renderer's rules and in the renderer's order.
    enum Line: Equatable {
        case blank, fence, rule, quote, bullet, numbered, indented, text
        case heading(level: Int)
    }

    struct Scan {
        let source: NSString

        init(_ source: NSString) {
            self.source = source
        }

        private struct Draft {
            var start: Int
            var end: Int
            let kind: CritiquePlace.Kind
            /// Bullet or numbered, for a list: a numbered list after a
            /// bulleted one is a second list, not more of the first.
            let style: Line?
            let section: Int?
            let ordinal: Int
        }

        private struct Tally: Hashable {
            let section: Int?
            let kind: CritiquePlace.Kind
        }

        func blocks() -> [Block] {
            var drafts: [Draft] = []
            var names: [String] = []
            var section: Int?
            var counts: [CritiquePlace.Kind: Int] = [:]
            var open: Draft?
            // A list closed by a blank line, kept back in case the next line
            // is its next item. A loose list — items with a blank line
            // between — is one list to the reader, and numbering each item as
            // a list of its own sent them looking for lists that are not
            // there.
            var held: Draft?
            var fence: MarkdownFence?
            var isFirstLine = true

            func start(
                _ kind: CritiquePlace.Kind,
                _ line: (start: Int, end: Int),
                style: Line? = nil
            ) -> Draft {
                counts[kind, default: 0] += 1
                return Draft(
                    start: line.start, end: line.end, kind: kind, style: style,
                    section: section, ordinal: counts[kind] ?? 1
                )
            }
            func settle() {
                if let list = held {
                    drafts.append(list)
                    held = nil
                }
                if let block = open {
                    drafts.append(block)
                    open = nil
                }
            }

            var location = Self.endOfFrontMatter(in: source)
            while location < source.length {
                var lineStart = 0
                var lineEnd = 0
                var contentsEnd = 0
                source.getLineStart(
                    &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                    for: NSRange(location: location, length: 0)
                )
                location = max(lineEnd, location + 1)
                let text = source.substring(
                    with: NSRange(location: lineStart, length: contentsEnd - lineStart)
                )
                let line = (start: lineStart, end: lineEnd)

                if let active = fence {
                    open?.end = lineEnd
                    if MarkdownFence.isClosing(text, for: active) {
                        fence = nil
                        settle()
                    }
                    continue
                }

                let kind = Self.kind(of: text)
                defer { if kind != .blank { isFirstLine = false } }
                switch kind {
                case .blank:
                    if let block = open {
                        if block.kind == .list {
                            held = block
                            open = nil
                        } else {
                            settle()
                        }
                    }
                case .fence:
                    settle()
                    fence = MarkdownFence.opening(in: text)
                    open = start(.code, line)
                case .rule:
                    settle()
                case let .heading(level):
                    settle()
                    if isFirstLine, level == 1 {
                        // The title. What follows it is the opening, not a
                        // section named after the document.
                        drafts.append(Draft(
                            start: line.start, end: line.end, kind: .title,
                            style: nil, section: nil, ordinal: 1
                        ))
                    } else {
                        names.append(Self.sectionName(ofHeading: text))
                        section = names.count - 1
                        counts = [:]
                        drafts.append(Draft(
                            start: line.start, end: line.end, kind: .heading,
                            style: nil, section: section, ordinal: 1
                        ))
                    }
                case .quote:
                    if open?.kind == .quote {
                        open?.end = lineEnd
                    } else {
                        settle()
                        open = start(.quote, line)
                    }
                case .bullet, .numbered:
                    if let block = open, block.kind == .list, block.style == kind {
                        open?.end = lineEnd
                    } else if open == nil, var list = held, list.style == kind {
                        list.end = lineEnd
                        open = list
                        held = nil
                    } else {
                        settle()
                        open = start(.list, line, style: kind)
                    }
                case .indented:
                    // More of whatever it is under: a wrapped item, an
                    // item's second paragraph, a paragraph's next line. Only
                    // a quote is left by it, since the renderer draws an
                    // unmarked line outside the quote.
                    if let block = open, block.kind != .quote {
                        open?.end = lineEnd
                    } else if open == nil, var list = held {
                        list.end = lineEnd
                        open = list
                        held = nil
                    } else {
                        settle()
                        open = start(.paragraph, line)
                    }
                case .text:
                    if open?.kind == .paragraph {
                        open?.end = lineEnd
                    } else {
                        settle()
                        open = start(.paragraph, line)
                    }
                }
            }
            settle()

            let isSectioned = !names.isEmpty
            var totals: [Tally: Int] = [:]
            for draft in drafts {
                totals[Tally(section: draft.section, kind: draft.kind), default: 0] += 1
            }
            return drafts.map { draft in
                let number: Int?
                switch draft.kind {
                case .title, .heading:
                    number = nil
                case .paragraph:
                    number = draft.ordinal
                case .list, .quote, .code:
                    let total = totals[Tally(section: draft.section, kind: draft.kind)] ?? 1
                    number = total > 1 ? draft.ordinal : nil
                }
                return Block(
                    range: NSRange(location: draft.start, length: draft.end - draft.start),
                    place: CritiquePlace(
                        section: draft.section.map { names[$0] },
                        kind: draft.kind,
                        number: number,
                        isSectioned: isSectioned
                    )
                )
            }
        }

        // MARK: Lines

        static func kind(ofLineAt location: Int, in source: NSString) -> Line {
            var lineStart = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart, end: nil, contentsEnd: &contentsEnd,
                for: NSRange(location: min(location, source.length), length: 0)
            )
            return kind(of: source.substring(
                with: NSRange(location: lineStart, length: contentsEnd - lineStart)
            ))
        }

        /// The renderer's checks, in its order: a fence before anything, a
        /// rule before a heading or a list (`- - -` is a rule), a heading
        /// before a quote.
        static func kind(of line: String) -> Line {
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let rest = line.dropFirst(indent.count)
            if rest.isEmpty { return .blank }
            if MarkdownFence.opening(in: line) != nil { return .fence }
            if isRule(line) { return .rule }
            if indent.count <= 3 {
                let hashes = rest.prefix { $0 == "#" }
                if (1...6).contains(hashes.count),
                   let next = rest.dropFirst(hashes.count).first,
                   next == " " || next == "\t" {
                    return .heading(level: hashes.count)
                }
            }
            if rest.first == ">" { return .quote }
            if let marker = rest.first, marker == "-" || marker == "+" || marker == "*",
               let next = rest.dropFirst().first, next == " " || next == "\t" {
                return .bullet
            }
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            if !digits.isEmpty {
                let after = rest.dropFirst(digits.count)
                if let mark = after.first, mark == "." || mark == ")",
                   let next = after.dropFirst().first, next == " " || next == "\t" {
                    return .numbered
                }
            }
            return indent.isEmpty ? .text : .indented
        }

        /// `MarkdownRenderModel`'s rule: three or more of one of `-`, `*` or
        /// `_`, with any spacing, and nothing else.
        static func isRule(_ line: String) -> Bool {
            let compact = line.filter { !$0.isWhitespace }
            guard compact.count >= 3, let first = compact.first,
                  first == "-" || first == "*" || first == "_"
            else { return false }
            return compact.allSatisfy { $0 == first }
        }

        // MARK: Front matter

        /// Where the draft starts once a YAML block at the very top is set
        /// aside, by `MarkdownProse`'s rule: `---` on the first line, a key
        /// on the second, and a closing `---` or `...`. Unclosed, it is a rule
        /// and the draft beneath it is prose.
        static func endOfFrontMatter(in source: NSString) -> Int {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            func line(at location: Int) -> String {
                source.getLineStart(
                    &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                    for: NSRange(location: location, length: 0)
                )
                return source.substring(
                    with: NSRange(location: lineStart, length: contentsEnd - lineStart)
                )
            }
            guard source.length > 0,
                  isOnly("-", line(at: 0)),
                  lineEnd < source.length,
                  startsWithKey(line(at: lineEnd))
            else { return 0 }
            var location = lineEnd
            while location < source.length {
                let text = line(at: location)
                if isOnly("-", text) || isOnly(".", text) { return lineEnd }
                location = max(lineEnd, location + 1)
            }
            return 0
        }

        static func opensFrontMatter(_ source: NSString) -> Bool {
            var contentsEnd = 0
            source.getLineStart(
                nil, end: nil, contentsEnd: &contentsEnd,
                for: NSRange(location: 0, length: 0)
            )
            return isOnly("-", source.substring(to: contentsEnd))
        }

        static func endOfSecondLine(in source: NSString) -> Int {
            var end = 0
            for _ in 0..<2 where end < source.length {
                var lineEnd = 0
                source.getLineStart(
                    nil, end: &lineEnd, contentsEnd: nil,
                    for: NSRange(location: end, length: 0)
                )
                end = lineEnd
            }
            return end
        }

        private static func isOnly(_ marker: Character, _ line: String) -> Bool {
            let trimmed = line.reversed().drop { $0 == " " || $0 == "\t" }
            return trimmed.count == 3 && trimmed.allSatisfy { $0 == marker }
        }

        private static func startsWithKey(_ line: String) -> Bool {
            let key = line.prefix {
                ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-"
            }
            return !key.isEmpty && line.dropFirst(key.count).first == ":"
        }

        // MARK: Section names

        /// The longest a section's name is shown at. The label shares a row
        /// with the note's stamps in a rail 356 points wide, and a heading
        /// the length of a sentence pushed the place onto two lines of its
        /// own.
        static let longestName = 32

        static func sectionName(ofHeading line: String) -> String {
            let name = headingText(line)
            return name.isEmpty ? "Untitled section" : shortened(name)
        }

        /// A heading line's words as they read on the page: no `#` marks at
        /// either end and no inline markup. Empty for a heading with no words.
        static func headingText(_ line: String) -> String {
            var content: Substring = line.drop(while: { (c: Character) in c == " " || c == "\t" })
            content = content.drop(while: { (c: Character) in c == "#" })
            content = content.drop(while: { (c: Character) in c == " " || c == "\t" })
            while let last = content.last, last == " " || last == "\t" {
                content = content.dropLast()
            }
            // A closing run of hashes, `## Setup ##`, is markup too.
            let closing = content.reversed().prefix { $0 == "#" }.count
            if closing > 0 {
                let kept = content.dropLast(closing)
                if kept.isEmpty || kept.last == " " || kept.last == "\t" {
                    content = kept
                }
            }
            return plain(String(content))
        }

        /// The words of a heading without its inline markup — emphasis,
        /// code and strike markers, link and image destinations, escapes —
        /// so the label reads the way the heading looks on the page.
        static func plain(_ markdown: String) -> String {
            let characters = Array(markdown)
            var result = ""
            var index = 0
            func isWordy(_ at: Int) -> Bool {
                guard characters.indices.contains(at) else { return false }
                return characters[at].isLetter || characters[at].isNumber
            }
            while index < characters.count {
                let character = characters[index]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                switch character {
                case "\\":
                    if let next, next.isPunctuation || next.isSymbol {
                        result.append(next)
                        index += 2
                        continue
                    }
                case "*", "`":
                    index += 1
                    continue
                case "~":
                    if next == "~" {
                        index += 2
                        continue
                    }
                case "_":
                    // Emphasis at a word's edge; `snake_case` keeps its own.
                    if !(isWordy(index - 1) && isWordy(index + 1)) {
                        index += 1
                        continue
                    }
                case "!":
                    if next == "[" {
                        index += 1
                        continue
                    }
                case "[":
                    index += 1
                    continue
                case "]":
                    if let next, next == "(" || next == "[" {
                        let close: Character = next == "(" ? ")" : "]"
                        if let end = characters[(index + 2)...].firstIndex(of: close) {
                            index = end + 1
                            continue
                        }
                    }
                    index += 1
                    continue
                default:
                    break
                }
                result.append(character)
                index += 1
            }
            return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        /// Cut at a word, with an ellipsis, so the end of what is shown is
        /// still a word somebody wrote.
        static func shortened(_ name: String) -> String {
            guard name.count > longestName else { return name }
            let cut = name.prefix(longestName)
            var kept = Substring(cut)
            if name.dropFirst(longestName).first?.isWhitespace != true,
               let space = cut.lastIndex(of: " "),
               cut.distance(from: cut.startIndex, to: space) >= longestName / 2 {
                kept = cut[..<space]
            }
            let trimmed = kept.trimmingCharacters(
                in: CharacterSet.whitespaces.union(.punctuationCharacters)
            )
            return trimmed + "…"
        }
    }
}
