import Foundation

enum EngineError: Error { case invalidURL, fetchFailed, parseFailed }

// MARK: - 网络层
struct NetworkManager {
    static let shared = NetworkManager()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15"]
        self.session = URLSession(configuration: cfg)
    }

    func fetch(url: String, headers: [String: String]? = nil, charset: String? = nil,
              method: String = "GET", body: Data? = nil) async throws -> String {
        guard let u = URL(string: url) else { throw EngineError.invalidURL }
        var req = URLRequest(url: u)
        req.httpMethod = method
        if let headers = headers {
            for (k, v) in headers where !k.isEmpty { req.setValue(v, forHTTPHeaderField: k) }
        }
        if let body = body { req.httpBody = body }
        let (data, _) = try await session.data(for: req)
        let enc = charset.flatMap { EncodingUtil.from(name: $0) } ?? EncodingUtil.detect(data: data, hint: u.path)
        return String(data: data, encoding: enc) ?? ""
    }

    func fetchData(url: String, headers: [String: String]? = nil) async throws -> Data {
        guard let u = URL(string: url) else { throw EngineError.invalidURL }
        var req = URLRequest(url: u)
        if let headers = headers { for (k, v) in headers where !k.isEmpty { req.setValue(v, forHTTPHeaderField: k) } }
        let (data, _) = try await session.data(for: req)
        return data
    }
}

struct EncodingUtil {
    // 使用 CFString 编码常量，避免不同 SDK 上 String.Encoding 静态属性缺失
    static func from(name: String) -> String.Encoding? {
        let n = name.lowercased()
        switch n {
        case "utf-8", "utf8": return .utf8
        case "gbk":      return encoding(raw: 0x80000632)   // kCFStringEncodingGBK_95
        case "gb2312":   return encoding(raw: 0x80000632)
        case "gb18030":  return encoding(raw: 0x80000631)   // kCFStringEncodingGB_18030_2000
        case "big5":     return encoding(raw: 0x80000A03)   // kCFStringEncodingBig5
        default: return .utf8
        }
    }
    static func encoding(raw: UInt32) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(raw)))
    }
    static func detect(data: Data, hint: String) -> String.Encoding {
        if let _ = String(data: data, encoding: .utf8) { return .utf8 }
        if let _ = String(data: data, encoding: encoding(raw: 0x80000631)) { return encoding(raw: 0x80000631) }
        return .utf8
    }
}

// MARK: - 书源引擎（搜索 / 发现 / 详情 / 目录 / 正文）
struct BookSourceEngine {

    // 解析请求头 JSON
    static func parseHeaders(_ header: String?) -> [String: String] {
        guard let header = header, !header.isEmpty,
              let data = header.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict.compactMapValues { "\($0)" }
    }

    static func isJson(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("{") || t.hasPrefix("[")
    }

    // 关键字占位替换：{{key}} / %s / {{page}}
    static func buildUrl(_ url: String, keyword: String, page: Int = 1) -> String {
        let kw = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        return url
            .replacingOccurrences(of: "{{key}}", with: kw)
            .replacingOccurrences(of: "%s", with: kw)
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "{{searchKey}}", with: kw)
    }

    static func absolute(_ maybeRelative: String?, base: String) -> String? {
        guard let r = maybeRelative, !r.isEmpty else { return nil }
        if r.hasPrefix("http://") || r.hasPrefix("https://") || r.hasPrefix("//") { return r }
        guard let baseUrl = URL(string: base), let u = URL(string: r, relativeTo: baseUrl) else { return r }
        return u.absoluteString
    }

    // MARK: 聚合搜索（单源）
    static func search(source: BookSource, keyword: String) async -> [SearchResult] {
        guard source.enabled, let searchUrl = source.searchUrl, !searchUrl.isEmpty else { return [] }
        let url = buildUrl(searchUrl, keyword: keyword)
        let headers = parseHeaders(source.header)
        guard let html = try? await NetworkManager.shared.fetch(url: url, headers: headers, charset: source.contentCharset) else { return [] }
        return parseSearch(source: source, html: html)
    }

    static func parseSearch(source: BookSource, html: String) -> [SearchResult] {
        guard let rs = source.ruleSearch else { return [] }
        let isHtml = !isJson(html)
        let items = RuleEngine.eval(rule: rs.bookList, content: html, isHtml: isHtml)
        var results: [SearchResult] = []
        for item in items {
            let bookUrl = RuleEngine.first(rs.bookUrl, content: item, isHtml: isHtml) ?? ""
            if bookUrl.isEmpty { continue }
            results.append(SearchResult(
                name: RuleEngine.first(rs.name, content: item, isHtml: isHtml) ?? "",
                author: RuleEngine.first(rs.author, content: item, isHtml: isHtml) ?? "",
                coverUrl: absolute(RuleEngine.first(rs.coverUrl, content: item, isHtml: isHtml), base: source.bookSourceUrl),
                bookUrl: bookUrl,
                sourceId: source.id,
                sourceName: source.bookSourceName,
                kind: RuleEngine.first(rs.kind, content: item, isHtml: isHtml),
                lastChapter: RuleEngine.first(rs.lastChapter, content: item, isHtml: isHtml),
                intro: RuleEngine.first(rs.intro, content: item, isHtml: isHtml),
                wordCount: RuleEngine.first(rs.wordCount, content: item, isHtml: isHtml)
            ))
        }
        return results
    }

    // MARK: 发现页
    static func explore(source: BookSource, groupUrl: String) async -> [SearchResult] {
        guard source.enabledExplore, !groupUrl.isEmpty else { return [] }
        let headers = parseHeaders(source.header)
        guard let html = try? await NetworkManager.shared.fetch(url: groupUrl, headers: headers, charset: source.contentCharset) else { return [] }
        return parseSearch(source: source, html: html)
    }

    // MARK: 书籍详情
    static func bookInfo(source: BookSource, bookUrl: String) async -> (intro: String?, kind: String?, lastChapter: String?, coverUrl: String?, tocUrl: String?, wordCount: String?) {
        guard let rbi = source.ruleBookInfo else { return (nil, nil, nil, nil, nil, nil) }
        let headers = parseHeaders(source.header)
        guard let html = try? await NetworkManager.shared.fetch(url: bookUrl, headers: headers, charset: source.contentCharset) else { return (nil, nil, nil, nil, nil, nil) }
        let isHtml = !isJson(html)
        return (
            intro: RuleEngine.first(rbi.intro, content: html, isHtml: isHtml),
            kind: RuleEngine.first(rbi.kind, content: html, isHtml: isHtml),
            lastChapter: RuleEngine.first(rbi.lastChapter, content: html, isHtml: isHtml),
            coverUrl: absolute(RuleEngine.first(rbi.coverUrl, content: html, isHtml: isHtml), base: source.bookSourceUrl),
            tocUrl: absolute(RuleEngine.first(rbi.tocUrl, content: html, isHtml: isHtml), base: source.bookSourceUrl) ?? bookUrl,
            wordCount: RuleEngine.first(rbi.wordCount, content: html, isHtml: isHtml)
        )
    }

    // MARK: 目录
    static func toc(source: BookSource, bookUrl: String) async -> [Chapter] {
        guard let rt = source.ruleToc else { return [] }
        let headers = parseHeaders(source.header)
        var tocUrl = bookUrl
        var chapters: [Chapter] = []
        var guardCount = 0
        while guardCount < 10 {
            guardCount += 1
            guard let html = try? await NetworkManager.shared.fetch(url: tocUrl, headers: headers, charset: source.contentCharset) else { break }
            let isHtml = !isJson(html)
            let items = RuleEngine.eval(rule: rt.chapterList, content: html, isHtml: isHtml)
            for (i, item) in items.enumerated() {
                let title = RuleEngine.first(rt.chapterName, content: item, isHtml: isHtml) ?? "第\(i+1)章"
                let url = RuleEngine.first(rt.chapterUrl, content: item, isHtml: isHtml) ?? ""
                if url.isEmpty { continue }
                chapters.append(Chapter(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                       url: absolute(url, base: source.bookSourceUrl) ?? url, index: chapters.count))
            }
            if let next = RuleEngine.first(rt.nextTocUrl, content: html, isHtml: isHtml), !next.isEmpty {
                let n = absolute(next, base: source.bookSourceUrl) ?? next
                if n == tocUrl { break }
                tocUrl = n
            } else { break }
        }
        return chapters
    }

    // MARK: 正文（支持多页拼接 + 站内正则净化）
    static func content(source: BookSource, chapterUrl: String) async -> String {
        guard let rc = source.ruleContent else { return "" }
        let headers = parseHeaders(source.header)
        var url = chapterUrl
        var full: [String] = []
        var guardCount = 0
        while guardCount < 10 {
            guardCount += 1
            guard let html = try? await NetworkManager.shared.fetch(url: url, headers: headers, charset: source.contentCharset) else { break }
            let isHtml = !isJson(html)
            var part = RuleEngine.first(rc.content, content: html, isHtml: isHtml) ?? ""
            if let sr = rc.sourceRegex, !sr.isEmpty {
                part = CleanupEngine.applyRegexOnly(pattern: sr, on: part)
            }
            if let rr = rc.replaceRegex, !rr.isEmpty {
                part = CleanupEngine.applyRegexOnly(pattern: rr, on: part)
            }
            full.append(part)
            if let next = RuleEngine.first(rc.nextContentUrl, content: html, isHtml: isHtml), !next.isEmpty {
                let n = absolute(next, base: source.bookSourceUrl) ?? next
                if n == url { break }
                url = n
            } else { break }
        }
        return full.joined(separator: "\n")
    }
}

// MARK: - 内容净化引擎（三级规则）
struct CleanupEngine {
    // 应用全局 / 单书 / 单源 三级净化规则
    static func apply(rules: [ReplaceRule], to text: String, bookId: String?, sourceId: String?) -> String {
        var out = text
        for rule in rules where shouldApply(rule, bookId: bookId, sourceId: sourceId) {
            out = applyRule(rule, on: out)
        }
        return out
    }

    private static func shouldApply(_ rule: ReplaceRule, bookId: String?, sourceId: String?) -> Bool {
        switch rule.scope {
        case .global: return true
        case .book:   return rule.bookId == bookId
        case .source: return rule.sourceId == sourceId
        }
    }

    private static func applyRule(_ rule: ReplaceRule, on text: String) -> String {
        switch rule.action {
        case .replace:
            return replace(pattern: rule.pattern, with: rule.replacement, regex: rule.isRegex, on: text)
        case .deleteLine:
            return text.components(separatedBy: .newlines)
                .filter { line in
                    let hit = rule.isRegex
                        ? (try? NSRegularExpression(pattern: rule.pattern))?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
                        : line.contains(rule.pattern)
                    return !hit
                }.joined(separator: "\n")
        case .keepLine:
            return text.components(separatedBy: .newlines)
                .filter { line in
                    let hit = rule.isRegex
                        ? (try? NSRegularExpression(pattern: rule.pattern))?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
                        : line.contains(rule.pattern)
                    return hit
                }.joined(separator: "\n")
        }
    }

    static func replace(pattern: String, with replacement: String, regex: Bool, on text: String) -> String {
        if regex {
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
            return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: replacement)
        }
        return text.replacingOccurrences(of: pattern, with: replacement)
    }

    static func applyRegexOnly(pattern: String, on text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }
}

// MARK: - 书源导入 / 导出（Legado 标准 JSON）
struct SourceImporter {
    // 导入：支持数组或单对象；兼容 Legado 社区公开书源
    static func `import`(jsonData: Data) -> [BookSource] {
        let decoder = JSONDecoder()
        // 尝试数组
        if let arr = try? decoder.decode([BookSource].self, from: jsonData) { return arr }
        if let single = try? decoder.decode(BookSource.self, from: jsonData) { return [single] }
        return []
    }

    static func `import`(text: String) -> [BookSource] {
        guard let d = text.data(using: .utf8) else { return [] }
        return `import`(jsonData: d)
    }

    static func export(sources: [BookSource]) -> Data {
        // 仅导出非默认字段，保持 Legado 兼容
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(sources)) ?? Data()
    }
}
