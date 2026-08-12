import SwiftUI

enum XDContent {

    struct Result {
        var text: AttributedString
        var paragraphs: [AttributedString]
        var hasHidden: Bool
        var plain: String
        var plainMasked: String
    }

    private final class ResultBox {
        let value: Result
        init(_ value: Result) { self.value = value }
    }

    private static let cache: NSCache<NSString, ResultBox> = {
        let c = NSCache<NSString, ResultBox>()
        c.countLimit = 600
        return c
    }()

    static let refScheme = "cookiejar"

    static func referenceURL(_ id: Int) -> URL {
        URL(string: "\(refScheme)://ref?id=\(id)")!
    }

    static func postId(fromRefURL url: URL) -> Int? {
        guard url.scheme == refScheme, url.host == "ref" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value.flatMap(Int.init)
    }

    static func parse(_ html: String, revealHidden: Bool) -> Result {
        let key = "\(revealHidden ? 1 : 0)|\(html.count)|\(html.hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let result = render(html, revealHidden: revealHidden)
        cache.setObject(ResultBox(result), forKey: key)
        return result
    }

    private static func render(_ html: String, revealHidden: Bool) -> Result {
        let quoteColor = XDTheme.quote
        let linkColor = XDTheme.link
        let hiddenBackground = XDTheme.hiddenBackground

        var runs: [Run] = []
        var style = Style()
        var hasHidden = false

        let scalars = Array(html)
        var i = 0
        var buffer = ""

        while i < scalars.count {
            let ch = scalars[i]
            if ch == "<" {
                var j = i + 1
                var tag = ""
                while j < scalars.count, scalars[j] != ">" {
                    tag.append(scalars[j]); j += 1
                }
                if j >= scalars.count { buffer.append(ch); i += 1; continue }
                if !buffer.isEmpty {
                    runs.append(Run(text: buffer, style: style))
                    buffer = ""
                }
                applyTag(tag.lowercased(), raw: tag, style: &style, runs: &runs)
                i = j + 1
                continue
            }
            if ch == "&" {
                var j = i + 1
                var ent = ""
                while j < scalars.count, scalars[j] != ";", ent.count < 10 {
                    ent.append(scalars[j]); j += 1
                }
                if j < scalars.count, scalars[j] == ";", let decoded = entity(ent) {
                    buffer.append(decoded)
                    i = j + 1
                    continue
                }
            }
            if ch == "\n" || ch == "\r" {
                i += 1
                continue
            }
            buffer.append(ch)
            i += 1
        }
        if !buffer.isEmpty {
            runs.append(Run(text: buffer, style: style))
            buffer = ""
        }

        var processed: [Run] = []
        var hiding = false
        for run in runs {
            var text = run.text
            while let range = XDContent.firstHiddenTag(in: text) {
                let isOpen = text[range] == "[h]"
                let head = String(text[text.startIndex..<range.lowerBound])
                if !head.isEmpty {
                    var s = run.style; s.hidden = hiding
                    processed.append(Run(text: head, style: s))
                }
                hiding = isOpen
                if isOpen { hasHidden = true }
                text = String(text[range.upperBound...])
            }
            if !text.isEmpty {
                var s = run.style; s.hidden = hiding
                processed.append(Run(text: text, style: s))
            }
        }

        var out = AttributedString()
        var paragraphs: [AttributedString] = []
        var current = AttributedString()
        var plain = ""
        var masked = ""
        for run in processed {
            plain += run.text
            masked += run.style.hidden ? (masked.hasSuffix("[隐藏]") ? "" : "[隐藏]") : run.text
            for piece in linkify(run.text) {
                var attr = AttributedString(piece.text)
                if run.style.bold { attr.inlinePresentationIntent = .stronglyEmphasized }
                if run.style.italic { attr.inlinePresentationIntent = .emphasized }
                if run.style.strike { attr.strikethroughStyle = .single }
                if run.style.underline { attr.underlineStyle = .single }
                if let c = run.style.color { attr.foregroundColor = c }
                if run.style.isQuote { attr.foregroundColor = quoteColor }

                switch piece.kind {
                case .plain:
                    break
                case .url(let u):
                    attr.link = u
                    attr.foregroundColor = linkColor
                    attr.underlineStyle = .single
                case .reference(_, let u):
                    attr.link = u
                    attr.foregroundColor = quoteColor
                }

                if run.style.hidden && !revealHidden {
                    attr.backgroundColor = hiddenBackground
                    attr.foregroundColor = hiddenBackground
                    attr.link = nil
                } else if run.style.hidden {
                    attr.backgroundColor = hiddenBackground.opacity(0.35)
                }
                out.append(attr)
                if piece.text == "\n" {
                    paragraphs.append(current)
                    current = AttributedString()
                } else {
                    current.append(attr)
                }
            }
        }
        paragraphs.append(current)
        while let last = paragraphs.last, last.characters.isEmpty { paragraphs.removeLast() }

        return Result(text: out, paragraphs: paragraphs, hasHidden: hasHidden,
                      plain: plain.trimmingCharacters(in: .whitespacesAndNewlines),
                      plainMasked: masked.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func plainText(_ html: String) -> String {
        parse(html, revealHidden: true).plain
    }

    static func previewText(_ html: String) -> String {
        parse(html, revealHidden: true).plainMasked
    }

    private static func firstHiddenTag(in text: String) -> Range<String.Index>? {
        let open = text.range(of: "[h]")
        let close = text.range(of: "[/h]")
        switch (open, close) {
        case (nil, nil): return nil
        case (let o?, nil): return o
        case (nil, let c?): return c
        case (let o?, let c?): return o.lowerBound <= c.lowerBound ? o : c
        }
    }

    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var color: Color?
        var isQuote = false
        var hidden = false
    }

    private struct Run {
        var text: String
        var style: Style
    }

    private static func applyTag(_ tag: String, raw: String, style: inout Style, runs: inout [Run]) {
        if tag.hasPrefix("br") {
            runs.append(Run(text: "\n", style: style))
            return
        }
        if tag.hasPrefix("/") {
            let name = String(tag.dropFirst())
            switch name {
            case "b", "strong": style.bold = false
            case "i", "em": style.italic = false
            case "u": style.underline = false
            case "del", "s", "strike": style.strike = false
            case "font", "span": style.color = nil; style.isQuote = false
            case "p", "div": runs.append(Run(text: "\n", style: style))
            default: break
            }
            return
        }
        let name = tag.split(separator: " ").first.map(String.init) ?? tag
        switch name {
        case "b", "strong": style.bold = true
        case "i", "em": style.italic = true
        case "u": style.underline = true
        case "del", "s", "strike": style.strike = true
        case "font", "span":
            if let raw = firstGroup(colorRegex, in: raw) {
                if raw.lowercased() == "789922" {
                    style.isQuote = true
                } else {
                    style.color = parseColor(raw)
                }
            }
        default: break
        }
    }

    private static let colorRegex = try! NSRegularExpression(
        pattern: "color\\s*[:=]\\s*[\"']?#?([0-9a-zA-Z]+)", options: [])

    private static let namedColors: [String: String] = [
        "black": "000000", "white": "FFFFFF", "red": "FF0000", "lime": "00FF00",
        "blue": "0000FF", "yellow": "FFFF00", "cyan": "00FFFF", "aqua": "00FFFF",
        "magenta": "FF00FF", "fuchsia": "FF00FF", "silver": "C0C0C0", "gray": "808080",
        "grey": "808080", "maroon": "800000", "olive": "808000", "green": "008000",
        "purple": "800080", "teal": "008080", "navy": "000080", "orange": "FFA500",
        "pink": "FFC0CB", "hotpink": "FF69B4", "deeppink": "FF1493", "gold": "FFD700",
        "deepskyblue": "00BFFF", "skyblue": "87CEEB", "lightblue": "ADD8E6",
        "royalblue": "4169E1", "dodgerblue": "1E90FF", "steelblue": "4682B4",
        "seagreen": "2E8B57", "limegreen": "32CD32", "forestgreen": "228B22",
        "darkgreen": "006400", "springgreen": "00FF7F", "yellowgreen": "9ACD32",
        "tomato": "FF6347", "coral": "FF7F50", "salmon": "FA8072", "crimson": "DC143C",
        "firebrick": "B22222", "darkred": "8B0000", "chocolate": "D2691E",
        "peru": "CD853F", "tan": "D2B48C", "beige": "F5F5DC", "ivory": "FFFFF0",
        "violet": "EE82EE", "orchid": "DA70D6", "plum": "DDA0DD", "indigo": "4B0082",
        "slateblue": "6A5ACD", "darkviolet": "9400D3", "turquoise": "40E0D0",
        "lightgreen": "90EE90", "khaki": "F0E68C", "lavender": "E6E6FA",
        "brown": "A52A2A", "darkorange": "FF8C00", "orangered": "FF4500",
    ]

    private static func parseColor(_ raw: String) -> Color? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.count == 6 || s.count == 3, s.allSatisfy({ $0.isHexDigit }) {
            return Color(hex: s.count == 3 ? s.map { "\($0)\($0)" }.joined() : s)
        }
        if let hex = namedColors[s.lowercased()] { return Color(hex: hex) }
        return nil
    }

    private static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "bull": "•", "middot": "·", "hellip": "…", "mdash": "—", "ndash": "–",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "laquo": "«", "raquo": "»", "times": "×", "divide": "÷", "deg": "°", "plusmn": "±",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶", "dagger": "†",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔",
        "spades": "♠", "clubs": "♣", "hearts": "♥", "diams": "♦",
        "star": "☆", "check": "✓", "cross": "✗", "ensp": " ", "emsp": " ", "thinsp": " ",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "pi": "π", "omega": "ω",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "infin": "∞", "ne": "≠",
        "le": "≤", "ge": "≥", "asymp": "≈", "prime": "′", "Prime": "″",
    ]

    private static func entity(_ name: String) -> String? {
        if let v = namedEntities[name] { return v }
        if name.hasPrefix("#") {
            let body = name.dropFirst()
            let code: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                code = UInt32(body.dropFirst(), radix: 16)
            } else {
                code = UInt32(body)
            }
            if let code, let scalar = Unicode.Scalar(code) { return String(Character(scalar)) }
        }
        return nil
    }

    private enum PieceKind {
        case plain
        case url(URL)
        case reference(Int, URL)
    }

    private struct Piece {
        var text: String
        var kind: PieceKind
    }

    private static let linkPattern =
        "(https?://[\\w\\-\\.]+\\.[a-zA-Z]{2,}[-\\w@%_+.~#?&/=|:;,]*|www[0-9]*\\.[\\w\\-]+\\.[a-zA-Z]{2,}[-\\w@%_+.~#?&/=|:;,]*)"
    private static let refPattern = "(?:>|＞)*No\\.(\\d+)|(?:>|＞)+(\\d+)|(\\d{8,})"

    private static let combinedRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\(linkPattern)|\(refPattern)", options: [])
    }()

    private static func linkify(_ text: String) -> [Piece] {
        guard let re = combinedRegex, !text.isEmpty else { return [Piece(text: text, kind: .plain)] }
        let ns = text as NSString
        var pieces: [Piece] = []
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            var kind: PieceKind = .plain
            if let link = group(1) {
                let normalized = link.hasPrefix("http") ? link : "https://\(link)"
                if let u = URL(string: normalized) { kind = .url(u) }
            } else {
                var idString = group(2) ?? group(3)
                if idString == nil, let bare = group(4), let n = Int(bare), n >= 50_000_000 {
                    idString = bare
                }
                guard let s = idString, let id = Int(s) else { continue }
                kind = .reference(id, referenceURL(id))
            }
            if case .plain = kind { continue }
            if m.range.location > last {
                pieces.append(Piece(text: ns.substring(with: NSRange(location: last, length: m.range.location - last)), kind: .plain))
            }
            pieces.append(Piece(text: ns.substring(with: m.range), kind: kind))
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            pieces.append(Piece(text: ns.substring(from: last), kind: .plain))
        }
        return pieces.isEmpty ? [Piece(text: text, kind: .plain)] : pieces
    }
}

struct XDRichText: View {
    let paragraphs: [AttributedString]
    var font: Font
    var lineSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph.characters.isEmpty ? AttributedString(" ") : paragraph)
                    .font(font)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        if s.count == 8 {
            a = Double((value >> 24) & 0xFF) / 255
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            a = 1
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "000000"
        #endif
    }
}
